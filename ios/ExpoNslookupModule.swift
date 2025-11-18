import ExpoModulesCore
import CoreFoundation
import SwiftDNS

public class ExpoNslookupModule: Module {
    public func definition() -> ModuleDefinition {
        Name("ExpoNslookup")
        
        // MARK: - DNS Lookup Function
        AsyncFunction("advanceLookUp") { (domain: String, timeout:Double , promise: Promise) in
            // Validate input domain
            guard !domain.isEmpty else {
                promise.reject(
                    DNSError.invalidDomain.code,
                    DNSError.invalidDomain.message
                )
                return
            }
            
            // Perform DNS lookup on background queue to avoid blocking
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Call with 1 second timeout
                    
                    let result = try self.performDNSLookupWithTimeout(for: domain, timeout: timeout)
                    
                    // Return to main queue for promise resolution
                    DispatchQueue.main.async {
                        promise.resolve([
                            "success": true,
                            "domain": domain,
                            "hasAddresses": result
                        ])
                    }
                } catch let error as DNSError {
                    DispatchQueue.main.async {
                        promise.reject(error.code, error.message)
                    }
                } catch {
                    DispatchQueue.main.async {
                        promise.reject(
                            DNSError.unknown.code,
                            "Unexpected error: \(error.localizedDescription)"
                        )
                    }
                }
            }
        }
        
        AsyncFunction("nsLookUpWithCustomDnsServer") { (domain: String, dnsServers: [String], timeoutInSeconds: Int) -> [String: Any] in
                  return try await resolveDomainWithMultipleServers(domain: domain, dnsServers: dnsServers, timeout: timeoutInSeconds)
              }
    }
    
    // MARK: - Private Helper Methods
    
    /// Performs DNS lookup for a given domain with timeoutoptions: [String: Any]?
    /// - Parameters:
    ///   - domain: The domain name to resolve
    ///   - timeout: Timeout in seconds
    /// - Returns: Boolean indicating if addresses were found
    /// - Throws: DNSError if lookup fails or times out
    private func performDNSLookupWithTimeout(for domain: String, timeout: TimeInterval) throws -> Bool {
        // Create CFHost object for DNS resolution
        let host = CFHostCreateWithName(kCFAllocatorDefault, domain as CFString).takeRetainedValue()
        
        // Set up timeout mechanism using DispatchSemaphore
        let semaphore = DispatchSemaphore(value: 0)
        var lookupResult: Result<Bool, DNSError>?
        
        // Perform DNS lookup on a separate queue
        DispatchQueue.global(qos: .userInitiated).async {
            var streamError = CFStreamError()
            let resolutionStarted = CFHostStartInfoResolution(host, .addresses, &streamError)
            
            // Check if resolution started successfully
            guard resolutionStarted else {
                lookupResult = .failure(.resolutionFailed(
                    domain: Int32(streamError.domain),
                    errorCode: streamError.error
                ))
                semaphore.signal()
                return
            }
            
            // Retrieve resolved addresses
            var success: DarwinBoolean = false
            guard let addressesRef = CFHostGetAddressing(host, &success),
                  success.boolValue else {
                lookupResult = .failure(.noAddressesFound(domain: domain))
                semaphore.signal()
                return
            }
            
            // Convert to Swift array and validate
            let addresses = addressesRef.takeUnretainedValue() as NSArray
            
            guard addresses.count > 0 else {
                lookupResult = .failure(.emptyAddressList(domain: domain))
                semaphore.signal()
                return
            }
            
            lookupResult = .success(true)
            semaphore.signal()
        }
        
        // Wait for either completion or timeout
        let result = semaphore.wait(timeout: .now() + timeout)
        
        // Check if timeout occurred
        if result == .timedOut {
            // Cancel the DNS resolution
            CFHostCancelInfoResolution(host, .addresses)
            throw DNSError.timeout(domain: domain, seconds: timeout)
        }
        
        // Return the result or throw error
        switch lookupResult {
        case .success(let hasAddresses):
            return hasAddresses
        case .failure(let error):
            throw error
        case .none:
            throw DNSError.unknown
        }
    }
}

private func resolveDomainWithMultipleServers(domain: String, dnsServers: [String], timeout: Int) async throws -> [String: Any] {
       var errors: [String] = []
    var isPublic: Bool = false
       // Try each DNS server in order
       for server in dnsServers {
           do {
               // Query the DNS server with timeout
               let ips = try await performDNSQuery(
                   domain: domain,
                   dnsServer: server,
                   timeout: timeout
               )
               
               // Check if we got IPs
               if !ips.isEmpty {
                   // Success - return immediately (matching Android's early return)
                   return [
                       "isPrivate": true,
                       "domain": domain,
                       "ip": ips,
                       "server": server
                   ]
               }
           } catch {
               // Collect error and continue to next server
               errors.append(error.localizedDescription)
           }
       }
       
       // All servers failed - throw error (matching Android's promise.reject)
    var code = if isPublic { 50 } else { 100 }
       throw NSError(
            domain: "\(errors)",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: errors.joined(separator: ", ")]
       )
   }
   
// MARK: - Helper Function: Perform DNS Query with Timeout
  
  private func performDNSQuery(domain: String, dnsServer: String, timeout: Int) async throws -> [String] {
      return try await withCheckedThrowingContinuation { continuation in
          var hasReturned = false
          
          // Create timeout task
          let timeoutTask = DispatchWorkItem {
              if !hasReturned {
                  hasReturned = true
                  continuation.resume(throwing: NSError(
                      domain:"Time out Issue",
                      code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "DNS query timeout after \(timeout) seconds"]
                  ))
              }
          }
          
          // Schedule timeout
          DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeout), execute: timeoutTask)
          
          // Perform DNS query (SwiftDNS default query - no type parameter)
          DNSService.query(host: NWEndpoint.Host(dnsServer), domain: domain, queue: .global()) { (response, error) in
              // Cancel timeout
              timeoutTask.cancel()
              
              if hasReturned {
                  return
              }
              hasReturned = true
              
              if let error = error {
                  continuation.resume(throwing: error)
                  return
              }
              
              guard let response = response else {
                  continuation.resume(throwing: NSError(
                      domain: "No Response",
                      code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "No response from DNS server"]
                  ))
                  return
              }
              
              // Extract IP addresses from A records
              let ipAddresses = response.Answers.compactMap { answer -> String? in
                      return answer.RData
              }
              
              continuation.resume(returning: ipAddresses)
          }
      }
  }


// MARK: - Error Types
/// Custom error types for DNS operations
enum DNSError: Error {
    case invalidDomain
    case resolutionFailed(domain: Int32, errorCode: Int32)
    case noAddressesFound(domain: String)
    case emptyAddressList(domain: String)
    case timeout(domain: String, seconds: TimeInterval)
    case unknown
    
    var code: String {
        switch self {
        case .invalidDomain:
            return "INVALID_DOMAIN"
        case .resolutionFailed:
            return "RESOLUTION_FAILED"
        case .noAddressesFound:
            return "NO_ADDRESSES_FOUND"
        case .emptyAddressList:
            return "EMPTY_ADDRESS_LIST"
        case .timeout:
            return "TIMEOUT"
        case .unknown:
            return "UNKNOWN_ERROR"
        }
    }
    
    var message: String {
        switch self {
        case .invalidDomain:
            return "The provided domain name is empty or invalid"
        case .resolutionFailed(let domain, let errorCode):
            return "DNS resolution failed - Domain: \(domain), Error code: \(errorCode)"
        case .noAddressesFound(let domain):
            return "No addresses found for domain: '\(domain)'"
        case .emptyAddressList(let domain):
            return "Address list is empty for domain: '\(domain)'"
        case .timeout(let domain, let seconds):
            return "DNS lookup timed out after \(seconds) second(s) for domain: '\(domain)'"
        case .unknown:
            return "An unknown error occurred during DNS lookup"
        }
    }
}
