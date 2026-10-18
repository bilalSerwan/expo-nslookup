import Foundation
import Network

/// How the exchange with one server ended.
enum ServerOutcome: Equatable, Sendable {
  case answered([String])
  case negative
  case timedOut
  case unreachable
  case cancelled
}

/// One DNS exchange with one server over a connected UDP `NWConnection`.
///
/// The same query is (re)sent at each `sendOffsetsMs` offset that falls before the deadline, and a late
/// answer to an earlier send still counts. A negative answer ends the exchange. Connection errors and the
/// `.waiting` state (no route, or Local Network access denied) end it as `.unreachable` at once. At the
/// deadline it is `.negative` if a SERVFAIL/truncated answer was seen, else `.timedOut`.
///
/// Unlike Android's DatagramSocket, Network.framework does not report ICMP port unreachable for UDP, so a
/// server whose port is closed runs until the deadline here. The outcome (`timedOut`) is the same.
///
/// All mutable state is confined to `queue`, which is also the connection's queue. `finish(_:)` is the only
/// place the continuation is resumed, and it runs at most once, so every path resumes exactly once even when
/// cancellation races the start.
final class DnsUdpExchange: @unchecked Sendable {
  private let queue: DispatchQueue
  private let connection: NWConnection
  private let query: Data
  private let id: UInt16
  private let question: [UInt8]
  private let sendOffsetsMs: [Int]
  private let deadline: DispatchTime

  private var continuation: CheckedContinuation<ServerOutcome, Never>?
  private var outcome: ServerOutcome?
  private var timers: [DispatchSourceTimer] = []
  private var sawTransient = false

  init?(
    server: DnsServer,
    port: UInt16,
    question: [UInt8],
    id: UInt16,
    deadline: DispatchTime,
    sendOffsetsMs: [Int],
    queue: DispatchQueue
  ) {
    // Built from bytes, never from a string: NWEndpoint.Host("name") would trigger a system DNS lookup.
    let host: NWEndpoint.Host
    switch server.bytes.count {
    case 4:
      guard let address = IPv4Address(Data(server.bytes)) else { return nil }
      host = .ipv4(address)
    case 16:
      guard let address = IPv6Address(Data(server.bytes)) else { return nil }
      host = .ipv6(address)
    default:
      return nil
    }
    guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }

    self.connection = NWConnection(host: host, port: nwPort, using: .udp)
    self.query = Data(DnsMessage.buildQuery(id: id, question: question))
    self.id = id
    self.question = question
    self.sendOffsetsMs = sendOffsetsMs
    self.deadline = deadline
    self.queue = queue
  }

  func run() async -> ServerOutcome {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        queue.async {
          if let outcome = self.outcome {
            // Cancelled before we started.
            continuation.resume(returning: outcome)
            return
          }
          self.continuation = continuation
          self.start()
        }
      }
    } onCancel: {
      queue.async { self.finish(.cancelled) }
    }
  }

  // MARK: - Everything below runs on `queue`

  private func start() {
    connection.stateUpdateHandler = { [weak self] state in self?.handle(state) }
    connection.start(queue: queue)
    schedule(at: deadline) { [weak self] in
      guard let self else { return }
      self.finish(self.sawTransient ? .negative : .timedOut)
    }
  }

  private func handle(_ state: NWConnection.State) {
    switch state {
    case .ready:
      startSending()
      receive()
    case .waiting, .failed:
      finish(.unreachable)
    default:
      break
    }
  }

  private func startSending() {
    let start = DispatchTime.now()
    for offset in sendOffsetsMs {
      let at = start + .milliseconds(offset)
      guard at < deadline else { continue }
      if offset == 0 {
        send()
      } else {
        schedule(at: at) { [weak self] in self?.send() }
      }
    }
  }

  private func send() {
    guard outcome == nil else { return }
    connection.send(content: query, completion: .contentProcessed { [weak self] error in
      if error != nil { self?.finish(.unreachable) }
    })
  }

  private func receive() {
    connection.receiveMessage { [weak self] data, _, _, error in
      guard let self, self.outcome == nil else { return }
      if error != nil {
        self.finish(.unreachable)
        return
      }
      if let data {
        switch DnsMessage.classify([UInt8](data), id: self.id, question: self.question) {
        case .addresses(let ips):
          self.finish(.answered(ips))
          return
        case .negative:
          self.finish(.negative)
          return
        case .transient:
          self.sawTransient = true
        case .ignore:
          break
        }
      }
      self.receive()
    }
  }

  /// A timer with a tight leeway: `asyncAfter` lets the system coalesce timers by up to ~10% of the interval,
  /// which would push the deadline of a 3 s lookup out by 200 ms or more.
  private func schedule(at time: DispatchTime, _ handler: @escaping @Sendable () -> Void) {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: time, leeway: .milliseconds(5))
    timer.setEventHandler(handler: handler)
    timers.append(timer)
    timer.resume()
  }

  private func finish(_ result: ServerOutcome) {
    guard outcome == nil else { return }
    outcome = result
    timers.forEach { $0.cancel() }
    timers.removeAll()
    connection.stateUpdateHandler = nil
    connection.cancel()
    continuation?.resume(returning: result)
    continuation = nil
  }
}
