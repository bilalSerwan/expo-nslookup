/// Error codes shared with Android and with `NslookupErrorCode` in src/ExpoNslookup.types.ts.
enum NslookupErrorCode: String, Sendable {
  case invalidDomain = "ERR_INVALID_DOMAIN"
  case invalidDnsServer = "ERR_INVALID_DNS_SERVER"
  case invalidTimeout = "ERR_INVALID_TIMEOUT"
  case dnsConfigUnavailable = "ERR_DNS_CONFIG_UNAVAILABLE"
}

/// A rejected argument. The module turns it into a coded JS error; it stays Expo-free so it can be unit tested.
struct InvalidArgumentError: Error, Equatable {
  let code: NslookupErrorCode
  let message: String
}

/// A DNS server given as an IP literal: its canonical text and the address bytes to connect to.
struct DnsServer: Equatable, Sendable {
  let text: String
  let bytes: [UInt8]
}

/// Validated arguments for one lookup.
struct LookupRequest: Sendable {
  static let minTimeoutMs = 100
  static let maxTimeoutMs = 60_000
  static let maxServers = 16

  let domain: String
  let question: [UInt8]
  let servers: [DnsServer]
  let timeoutMs: Int

  /// Validates in argument order (domain, servers, timeout), the same order as Android, so both reject with the same code.
  init(domain: String, dnsServers: [String], timeoutMs: Double) throws {
    guard let name = DnsMessage.normalizeDomain(domain) else {
      throw InvalidArgumentError(code: .invalidDomain, message: "Invalid domain name: '\(domain)'")
    }
    let servers = try Self.parseServers(dnsServers)
    guard timeoutMs.isFinite, timeoutMs >= Double(Self.minTimeoutMs), timeoutMs <= Double(Self.maxTimeoutMs) else {
      throw InvalidArgumentError(
        code: .invalidTimeout,
        message: "timeoutMs must be between \(Self.minTimeoutMs) and \(Self.maxTimeoutMs), got \(timeoutMs)"
      )
    }
    self.domain = name
    self.question = DnsMessage.encodeQuestion(name)
    self.servers = servers
    self.timeoutMs = Int(timeoutMs)
  }

  /// Validates 1-16 IP literals (never hostnames) and dedupes them by canonical text, keeping input order.
  static func parseServers(_ dnsServers: [String]) throws -> [DnsServer] {
    guard (1...maxServers).contains(dnsServers.count) else {
      throw InvalidArgumentError(
        code: .invalidDnsServer,
        message: "Expected 1 to \(maxServers) DNS servers, got \(dnsServers.count)"
      )
    }
    var seen = Set<String>()
    var servers: [DnsServer] = []
    for text in dnsServers {
      guard let bytes = IPAddressText.parse(text), let canonical = IPAddressText.format(bytes) else {
        throw InvalidArgumentError(
          code: .invalidDnsServer,
          message: "DNS server must be an IPv4 or IPv6 address, got '\(text)'"
        )
      }
      if seen.insert(canonical).inserted {
        servers.append(DnsServer(text: canonical, bytes: IPAddressText.routable(bytes)))
      }
    }
    return servers
  }
}
