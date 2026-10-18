import Foundation
import Testing
@testable import NslookupCore

/// Talks to fake DNS servers on the loopback interfaces (127.0.0.1 and ::1).
/// android/src/test/.../DnsResolverTest.kt covers the same cases. Serialized because the cases assert timings.
@Suite(.serialized) struct DnsResolverTests {
  @Test func resolvesFromAnsweringServer() async throws {
    let server = try FakeDnsServer { query in [answerA(query, [10, 0, 0, 5])] }
    defer { server.stop() }
    let outcome = try await resolve(["127.0.0.1"], port: server.port)
    #expect(outcome == .resolved(server: "127.0.0.1", ips: ["10.0.0.5"]))
  }

  @Test func ignoresResponseWithWrongIdThenAcceptsTheRightOne() async throws {
    let server = try FakeDnsServer { query in
      var wrongId = query
      wrongId[0] &+= 1
      return [answerA(wrongId, [10, 0, 0, 1]), answerA(query, [10, 0, 0, 2])]
    }
    defer { server.stop() }
    let outcome = try await resolve(["127.0.0.1"], port: server.port)
    #expect(outcome == .resolved(server: "127.0.0.1", ips: ["10.0.0.2"]))
  }

  @Test func resendsWhenTheFirstQueryIsDropped() async throws {
    let seen = Counter()
    let server = try FakeDnsServer { query in
      seen.increment() == 1 ? [] : [answerA(query, [10, 0, 0, 3])]
    }
    defer { server.stop() }
    let start = DispatchTime.now()
    let outcome = try await resolve(["127.0.0.1"], port: server.port, sendOffsetsMs: [0, 150], timeoutMs: 2_000)
    #expect(outcome == .resolved(server: "127.0.0.1", ips: ["10.0.0.3"]))
    #expect(elapsedMs(since: start) >= 140, "should wait for the resend")
    #expect(seen.value == 2)
  }

  @Test func returnsNotFoundQuicklyOnNxdomain() async throws {
    let server = try FakeDnsServer { query in [response(query, rcode: 3)] }
    defer { server.stop() }
    let start = DispatchTime.now()
    let outcome = try await resolve(["127.0.0.1"], port: server.port, timeoutMs: 3_000)
    #expect(outcome == .notFound(server: "127.0.0.1"))
    #expect(elapsedMs(since: start) < 1_000, "NXDOMAIN must not wait for the deadline")
  }

  @Test func timesOutWhenNoServerAnswers() async throws {
    let server = try FakeDnsServer { _ in [] }
    defer { server.stop() }
    let start = DispatchTime.now()
    let outcome = try await resolve(["127.0.0.1"], port: server.port, timeoutMs: 300)
    #expect(outcome == .timedOut)
    #expect((280...1_000).contains(elapsedMs(since: start)))
  }

  @Test func servfailOnlyBecomesNotFoundAtTheDeadline() async throws {
    let server = try FakeDnsServer { query in [response(query, rcode: 2)] }
    defer { server.stop() }
    let start = DispatchTime.now()
    let outcome = try await resolve(["127.0.0.1"], port: server.port, timeoutMs: 300)
    #expect(outcome == .notFound(server: "127.0.0.1"))
    #expect(elapsedMs(since: start) >= 280)
  }

  @Test func fastServerWinsWithoutWaitingForASilentOne() async throws {
    let fast = try FakeDnsServer { query in [answerA(query, [10, 0, 0, 4])] }
    defer { fast.stop() }
    let silent = try FakeDnsServer(ipv6: true, port: fast.port) { _ in [] }
    defer { silent.stop() }
    let start = DispatchTime.now()
    let outcome = try await resolve(["::1", "127.0.0.1"], port: fast.port, timeoutMs: 3_000)
    #expect(outcome == .resolved(server: "127.0.0.1", ips: ["10.0.0.4"]))
    #expect(elapsedMs(since: start) < 1_000, "must not wait for the silent server")
  }

  @Test func keepsWaitingForOtherServersAfterANegativeAnswer() async throws {
    let negative = try FakeDnsServer { query in [response(query, rcode: 3)] }
    defer { negative.stop() }
    let slow = try FakeDnsServer(ipv6: true, port: negative.port) { query in
      Thread.sleep(forTimeInterval: 0.2)
      return [answerA(query, [10, 0, 0, 6])]
    }
    defer { slow.stop() }
    let outcome = try await resolve(["127.0.0.1", "::1"], port: negative.port, timeoutMs: 3_000)
    #expect(outcome == .resolved(server: "::1", ips: ["10.0.0.6"]))
  }

  @Test func closedPortTimesOutAtTheDeadline() async throws {
    // Nothing listens on this port. Network.framework does not surface ICMP port unreachable for UDP
    // (Android does, and ends early), so iOS waits for the deadline. The outcome is the same.
    let closed = try FakeDnsServer { _ in [] }
    let port = closed.port
    closed.stop()
    let start = DispatchTime.now()
    let outcome = try await resolve(["127.0.0.1"], port: port, timeoutMs: 500)
    #expect(outcome == .timedOut)
    #expect((480...800).contains(elapsedMs(since: start)))
  }

  @Test func deadlineIsPrecise() async throws {
    let server = try FakeDnsServer { _ in [] }
    defer { server.stop() }
    let start = DispatchTime.now()
    _ = try await resolve(["127.0.0.1"], port: server.port, timeoutMs: 3_000)
    #expect((2_980...3_100).contains(elapsedMs(since: start)), "timer leeway must not stretch the deadline")
  }

  @Test func cancellationEndsTheLookupPromptly() async throws {
    let server = try FakeDnsServer { _ in [] }
    defer { server.stop() }
    let request = try LookupRequest(domain: "intranet.example", dnsServers: ["127.0.0.1"], timeoutMs: 10_000)
    let resolver = DnsResolver(port: server.port)
    let start = DispatchTime.now()
    let lookup = Task { await resolver.resolve(request) }
    try await Task.sleep(nanoseconds: 100_000_000)
    lookup.cancel()
    #expect(await lookup.value == .timedOut)
    #expect(elapsedMs(since: start) < 2_000, "cancellation must end the exchange promptly")
  }

  @Test func reportsOnlineOnThisMachine() async {
    #expect(await NetworkPath.isOffline() == false)
  }

  // MARK: - Helpers

  private func resolve(
    _ servers: [String],
    port: UInt16,
    sendOffsetsMs: [Int] = DnsResolver.defaultSendOffsetsMs,
    timeoutMs: Double = 2_000
  ) async throws -> LookupOutcome {
    let request = try LookupRequest(domain: "intranet.example", dnsServers: servers, timeoutMs: timeoutMs)
    return await DnsResolver(port: port, sendOffsetsMs: sendOffsetsMs).resolve(request)
  }

  private func elapsedMs(since start: DispatchTime) -> Int {
    Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
  }
}

/// Echoes the query's ID and question with the given RCODE and ANCOUNT.
private func response(_ query: [UInt8], rcode: UInt8 = 0, answers: UInt8 = 0) -> [UInt8] {
  var reply = query
  reply[2] = 0x81
  reply[3] = 0x80 | rcode
  reply[7] = answers
  return reply
}

private func answerA(_ query: [UInt8], _ ip: [UInt8]) -> [UInt8] {
  response(query, answers: 1) + [0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0x0e, 0x10, 0, 4] + ip
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int { lock.withLock { count } }

  func increment() -> Int {
    lock.withLock {
      count += 1
      return count
    }
  }
}

/// A UDP server on a background thread that answers each query with whatever `handler` returns.
final class FakeDnsServer: @unchecked Sendable {
  let port: UInt16
  private let fd: Int32
  private let lock = NSLock()
  private var stopped = false
  private let finished = DispatchSemaphore(value: 0)

  init(ipv6: Bool = false, port requestedPort: UInt16 = 0, handler: @escaping @Sendable ([UInt8]) -> [[UInt8]]) throws {
    let family = ipv6 ? AF_INET6 : AF_INET
    let fd = socket(family, SOCK_DGRAM, IPPROTO_UDP)
    guard fd >= 0 else { throw POSIXError(.EIO) }
    // Wake up regularly so stop() is noticed.
    var timeout = timeval(tv_sec: 0, tv_usec: 50_000)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var storage = sockaddr_storage()
    var length: socklen_t
    if ipv6 {
      var on: Int32 = 1
      setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &on, socklen_t(MemoryLayout<Int32>.size))
      var address = sockaddr_in6()
      address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
      address.sin6_family = sa_family_t(AF_INET6)
      address.sin6_port = requestedPort.bigEndian
      inet_pton(AF_INET6, "::1", &address.sin6_addr)
      length = socklen_t(MemoryLayout<sockaddr_in6>.size)
      withUnsafeBytes(of: &address) { bytes in
        withUnsafeMutableBytes(of: &storage) { $0.copyMemory(from: bytes) }
      }
    } else {
      var address = sockaddr_in()
      address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
      address.sin_family = sa_family_t(AF_INET)
      address.sin_port = requestedPort.bigEndian
      inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
      length = socklen_t(MemoryLayout<sockaddr_in>.size)
      withUnsafeBytes(of: &address) { bytes in
        withUnsafeMutableBytes(of: &storage) { $0.copyMemory(from: bytes) }
      }
    }
    let bound = withUnsafePointer(to: &storage) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
    }
    guard bound == 0 else {
      close(fd)
      throw POSIXError(.EADDRINUSE)
    }
    _ = withUnsafeMutablePointer(to: &storage) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
    }
    let networkPort = withUnsafeBytes(of: &storage) { raw in
      ipv6
        ? raw.load(fromByteOffset: MemoryLayout<sockaddr_in6>.offset(of: \.sin6_port)!, as: UInt16.self)
        : raw.load(fromByteOffset: MemoryLayout<sockaddr_in>.offset(of: \.sin_port)!, as: UInt16.self)
    }
    self.port = UInt16(bigEndian: networkPort)
    self.fd = fd

    let thread = Thread { [self] in serve(handler) }
    thread.start()
  }

  func stop() {
    lock.withLock { stopped = true }
    finished.wait()
  }

  private var isStopped: Bool { lock.withLock { stopped } }

  private func serve(_ handler: @Sendable ([UInt8]) -> [[UInt8]]) {
    var buffer = [UInt8](repeating: 0, count: 4096)
    while !isStopped {
      var from = sockaddr_storage()
      var fromLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
      let received = buffer.withUnsafeMutableBytes { bytes in
        withUnsafeMutablePointer(to: &from) {
          $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            recvfrom(fd, bytes.baseAddress, bytes.count, 0, $0, &fromLength)
          }
        }
      }
      guard received > 0 else { continue }
      for reply in handler(Array(buffer[0..<received])) {
        _ = reply.withUnsafeBytes { bytes in
          withUnsafePointer(to: &from) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
              sendto(fd, bytes.baseAddress, bytes.count, 0, $0, fromLength)
            }
          }
        }
      }
    }
    close(fd)
    finished.signal()
  }
}
