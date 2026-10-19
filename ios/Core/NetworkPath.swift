import Foundation
import Network

/// Checks whether the device currently has any usable network path.
enum NetworkPath {
  /// True when the current path is `.unsatisfied`. A path that `.requiresConnection` (for example cellular
  /// that is about to come up) counts as online. Takes a few milliseconds: it waits for the monitor's first update.
  static func isOffline() async -> Bool {
    await withCheckedContinuation { continuation in
      OfflineProbe(continuation: continuation).start()
    }
  }
}

/// Resumes its continuation once, on the monitor's first path update. State is confined to `queue`.
private final class OfflineProbe: @unchecked Sendable {
  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "expo.modules.nslookup.path")
  private var continuation: CheckedContinuation<Bool, Never>?

  init(continuation: CheckedContinuation<Bool, Never>) {
    self.continuation = continuation
  }

  func start() {
    // The handler keeps the probe alive until the first update; clearing it breaks the cycle.
    monitor.pathUpdateHandler = { path in
      guard let continuation = self.continuation else { return }
      self.continuation = nil
      self.monitor.pathUpdateHandler = nil
      self.monitor.cancel()
      continuation.resume(returning: path.status == .unsatisfied)
    }
    monitor.start(queue: queue)
  }
}
