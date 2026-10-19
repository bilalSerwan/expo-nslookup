import ExpoModulesCore

public class ExpoNslookupModule: Module {
  private let resolver = DnsResolver()

  public func definition() -> ModuleDefinition {
    Name("ExpoNslookup")

    // Never rejects for a public network; only invalid arguments reject.
    AsyncFunction("nsLookupWithCustomDns") { (domain: String, dnsServers: [String], timeoutMs: Double) async throws -> LookupResult in
      let request = try rejectingInvalidArguments {
        try LookupRequest(domain: domain, dnsServers: dnsServers, timeoutMs: timeoutMs)
      }
      let start = DispatchTime.now().uptimeNanoseconds
      let outcome: LookupOutcome
      if await NetworkPath.isOffline() {
        outcome = .offline
      } else {
        outcome = await self.resolver.resolve(request)
      }
      let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
      return LookupResult(outcome: outcome, domain: request.domain, elapsedMs: elapsedMs)
    }

    AsyncFunction("getDnsServers") { () throws -> [String] in
      try Self.deviceServers()
    }

    AsyncFunction("compareDnsServers") { (expectedServers: [String]) throws -> DnsServerComparison in
      let expected = try rejectingInvalidArguments { try LookupRequest.parseServers(expectedServers) }.map(\.text)
      return DnsServerComparison(deviceServers: try Self.deviceServers(), expectedServers: expected)
    }
  }

  /// The resolver's DNS servers in canonical text (see `IPAddressText`).
  private static func deviceServers() throws -> [String] {
    guard let addresses = ExpoNslookupReadResolverAddresses() else {
      throw nslookupException(.dnsConfigUnavailable, "Failed to read the DNS resolver configuration.")
    }
    return addresses.compactMap { IPAddressText.format([UInt8]($0)) }
  }
}
