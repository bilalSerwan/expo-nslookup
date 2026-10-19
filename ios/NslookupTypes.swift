import ExpoModulesCore

/// Mirrors `LookupReason` in src/ExpoNslookup.types.ts.
enum LookupReason: String, Enumerable {
  case resolved
  case notFound
  case timeout
  case offline
}

/// Mirrors `CustomDnsLookupResult` in src/ExpoNslookup.types.ts.
struct LookupResult: Record {
  @Field var isPrivate: Bool = false
  @Field var reason: LookupReason = .timeout
  @Field var domain: String = ""
  @Field var ip: [String] = []
  @Field var server: String? = nil
  @Field var elapsedMs: Int = 0

  init() {}

  init(outcome: LookupOutcome, domain: String, elapsedMs: Int) {
    self.domain = domain
    self.elapsedMs = elapsedMs
    switch outcome {
    case .resolved(let server, let ips):
      isPrivate = true
      reason = .resolved
      ip = ips
      self.server = server
    case .notFound(let server):
      reason = .notFound
      self.server = server
    case .timedOut:
      reason = .timeout
    case .offline:
      reason = .offline
    }
  }
}

/// Mirrors `DnsServerComparison` in src/ExpoNslookup.types.ts.
struct DnsServerComparison: Record {
  @Field var deviceServers: [String] = []
  @Field var expectedServers: [String] = []
  @Field var matchedServers: [String] = []
  @Field var isMatch: Bool = false

  init() {}

  init(deviceServers: [String], expectedServers: [String]) {
    let matched = deviceServers.filter(expectedServers.contains)
    self.deviceServers = deviceServers
    self.expectedServers = expectedServers
    self.matchedServers = matched
    self.isMatch = !matched.isEmpty
  }
}

/// A coded JS error. The code is explicit so it never depends on a type name.
func nslookupException(_ code: NslookupErrorCode, _ message: String) -> Exception {
  Exception(name: "NslookupException", description: message, code: code.rawValue)
}

/// Runs `body`, turning an `InvalidArgumentError` into a coded JS error.
func rejectingInvalidArguments<T>(_ body: () throws -> T) throws -> T {
  do {
    return try body()
  } catch let error as InvalidArgumentError {
    throw nslookupException(error.code, error.message)
  }
}
