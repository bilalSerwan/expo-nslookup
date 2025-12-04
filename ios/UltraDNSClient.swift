//
//  UltraDNSClient.swift
//  Pods
//
//  Created by Bilal Seerwan on 12/4/25.
//

import Foundation
import Network

public class UltraFastDNSResolver: @unchecked Sendable {
    
    public struct Config: Sendable {
        var maxRetries: Int = 2
        var retryTimeoutMs: Int = 500
        var totalTimeoutMs: Int = 3000
        
        public init(maxRetries: Int = 2, retryTimeoutMs: Int = 500, totalTimeoutMs: Int = 3000) {
            self.maxRetries = maxRetries
            self.retryTimeoutMs = retryTimeoutMs
            self.totalTimeoutMs = totalTimeoutMs
        }
    }
    
    public init() {}
    
    // MARK: - Public API
    
    public func resolve(
        domain: String,
        dnsServers: [String],
        config: Config = Config()
    ) async throws -> [String: Any] {
        
        return try await withThrowingTaskGroup(of: [String: Any]?.self) { group in
            
            for server in dnsServers {
                group.addTask { [self] in
                    try? await self.queryWithRetry(
                        domain: domain,
                        server: server,
                        maxRetries: config.maxRetries,
                        retryTimeoutMs: config.retryTimeoutMs
                    )
                }
            }
            
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(config.totalTimeoutMs) * 1_000_000)
                return nil
            }
            
            for try await result in group {
                if let result = result {
                    group.cancelAll()
                    return result
                }
            }
            
            throw NSError(
                domain: "No Address Founded",
                code: 50,
                userInfo: [NSLocalizedDescriptionKey: "All DNS servers failed or Timeout"]
            )
        }
    }
    
    // MARK: - Query with Retry
    
    private func queryWithRetry(
        domain: String,
        server: String,
        maxRetries: Int,
        retryTimeoutMs: Int
    ) async throws -> [String: Any]? {
        
        for _ in 0..<maxRetries {
            if Task.isCancelled { return nil }
            
            do {
                let ips = try await queryDNS(
                    domain: domain,
                    server: server,
                    timeoutMs: retryTimeoutMs
                )
                
                if !ips.isEmpty {
                    return [
                        "isPrivate": true,
                        "domain": domain,
                        "ip": ips,
                        "server": server
                    ]
                }
            } catch {
                continue
            }
        }
        
        return nil
    }
    
    // MARK: - Raw UDP Query (Thread-Safe)
    
    private func queryDNS(
        domain: String,
        server: String,
        timeoutMs: Int
    ) async throws -> [String] {
        
        let safeHandler = SafeContinuationHandler<[String]>()
        
        return try await withCheckedThrowingContinuation { continuation in
            
            Task {
                await safeHandler.setContinuation(continuation)
            }
            
            let host = NWEndpoint.Host(server)
            let port = NWEndpoint.Port(rawValue: 53)!
            let connection = NWConnection(host: host, port: port, using: .udp)
            
            // Timeout using Task
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                await safeHandler.resumeWithError(
                    NSError(domain: "Timeout", code: -1, userInfo: nil)
                )
                connection.cancel()
            }
            
            connection.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                
                switch state {
                case .ready:
                    let query = self.buildQuery(domain: domain)
                    
                    connection.send(content: query, completion: .contentProcessed { error in
                        if let error = error {
                            timeoutTask.cancel()
                            Task {
                                await safeHandler.resumeWithError(error)
                            }
                            connection.cancel()
                        }
                    })
                    
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 512) { [weak self] data, _, _, error in
                        timeoutTask.cancel()
                        
                        guard let self = self else { return }
                        
                        if let error = error {
                            Task {
                                await safeHandler.resumeWithError(error)
                            }
                            connection.cancel()
                            return
                        }
                        
                        let ips = self.parseResponse(data: data ?? Data())
                        Task {
                            await safeHandler.resumeWithValue(ips)
                        }
                        connection.cancel()
                    }
                    
                case .failed(let error):
                    timeoutTask.cancel()
                    Task {
                        await safeHandler.resumeWithError(error)
                    }
                    
                case .cancelled:
                    timeoutTask.cancel()
                    Task {
                        await safeHandler.resumeWithError(
                            NSError(domain: "Cancelled", code: -2, userInfo: nil)
                        )
                    }
                    
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
        }
    }
    
    // MARK: - Build DNS Query
    
    private func buildQuery(domain: String) -> Data {
        var query = Data()
        
        let id = UInt16.random(in: 0...UInt16.max)
        query.append(UInt8(id >> 8))
        query.append(UInt8(id & 0xFF))
        
        query.append(contentsOf: [0x01, 0x00])
        query.append(contentsOf: [0x00, 0x01])
        query.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        
        for label in domain.split(separator: ".") {
            query.append(UInt8(label.count))
            query.append(contentsOf: label.utf8)
        }
        query.append(0x00)
        
        query.append(contentsOf: [0x00, 0x01, 0x00, 0x01])
        
        return query
    }
    
    // MARK: - Parse DNS Response
    
    private func parseResponse(data: Data) -> [String] {
        guard data.count >= 12 else { return [] }
        
        let bytes = [UInt8](data)
        var ips: [String] = []
        
        let answerCount = Int(bytes[6]) << 8 | Int(bytes[7])
        if answerCount == 0 { return [] }
        
        var offset = 12
        while offset < bytes.count && bytes[offset] != 0 {
            offset += Int(bytes[offset]) + 1
        }
        offset += 5
        
        for _ in 0..<answerCount {
            guard offset + 12 <= bytes.count else { break }
            
            if bytes[offset] & 0xC0 == 0xC0 {
                offset += 2
            } else {
                while offset < bytes.count && bytes[offset] != 0 {
                    offset += Int(bytes[offset]) + 1
                }
                offset += 1
            }
            
            guard offset + 10 <= bytes.count else { break }
            
            let recordType = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            offset += 8
            
            let dataLength = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            offset += 2
            
            if recordType == 1 && dataLength == 4 && offset + 4 <= bytes.count {
                let ip = "\(bytes[offset]).\(bytes[offset+1]).\(bytes[offset+2]).\(bytes[offset+3])"
                ips.append(ip)
            }
            
            offset += dataLength
        }
        
        return ips
    }
}

// MARK: - Safe Continuation Handler (Actor)

actor SafeContinuationHandler<T> {
    private var continuation: CheckedContinuation<T, Error>?
    private var hasResumed = false
    
    func setContinuation(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }
    
    func resumeWithValue(_ value: T) {
        guard !hasResumed, let continuation = continuation else { return }
        hasResumed = true
        continuation.resume(returning: value)
    }
    
    func resumeWithError(_ error: Error) {
        guard !hasResumed, let continuation = continuation else { return }
        hasResumed = true
        continuation.resume(throwing: error)
    }
}
