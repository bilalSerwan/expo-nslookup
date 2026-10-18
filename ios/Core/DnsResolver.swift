import Foundation

/// How one lookup ended. `server` is the canonical IP text of the deciding DNS server.
enum LookupOutcome: Equatable, Sendable {
  case resolved(server: String, ips: [String])
  case notFound(server: String)
  case timedOut
  case offline
}

/// Queries every server in parallel and returns the first positive answer.
/// android/.../DnsResolver.kt implements the same behaviour.
///
/// The first `.answered` wins and cancels the rest. When every server is done: any `.negative` gives
/// `.notFound` (the first one to arrive), otherwise `.timedOut`. One negative never stops the others,
/// because another server may still resolve the domain.
struct DnsResolver: Sendable {
  static let dnsPort: UInt16 = 53
  static let defaultSendOffsetsMs = [0, 500, 1_500, 3_500]

  /// One serial queue for every connection and timer; the work on it is tiny.
  static let queue = DispatchQueue(label: "expo.modules.nslookup")

  var port: UInt16 = dnsPort
  var sendOffsetsMs: [Int] = defaultSendOffsetsMs
  var nextId: @Sendable () -> UInt16 = { UInt16.random(in: .min ... .max) }

  func resolve(_ request: LookupRequest) async -> LookupOutcome {
    let deadline = DispatchTime.now() + .milliseconds(request.timeoutMs)
    return await withTaskGroup(of: (DnsServer, ServerOutcome).self) { group in
      for server in request.servers {
        group.addTask {
          guard let exchange = DnsUdpExchange(
            server: server,
            port: port,
            question: request.question,
            id: nextId(),
            deadline: deadline,
            sendOffsetsMs: sendOffsetsMs,
            queue: Self.queue
          ) else {
            return (server, .unreachable)
          }
          return (server, await exchange.run())
        }
      }

      var firstNegative: DnsServer?
      for await (server, outcome) in group {
        switch outcome {
        case .answered(let ips):
          group.cancelAll()
          return .resolved(server: server.text, ips: ips)
        case .negative:
          if firstNegative == nil { firstNegative = server }
        case .timedOut, .unreachable, .cancelled:
          break
        }
      }
      return firstNegative.map { .notFound(server: $0.text) } ?? .timedOut
    }
  }
}
