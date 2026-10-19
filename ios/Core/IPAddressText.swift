import Foundation

/// Strict IP-literal parsing and canonical formatting through the system `inet_pton`/`inet_ntop`.
///
/// android/.../IpAddressText.kt reimplements the same rules; the shared vectors in
/// CoreTests/IPAddressTextTests.swift and IpAddressTextTest.kt keep the two in step.
///
/// Canonical text:
/// - IPv4: dotted quad.
/// - IPv4-mapped IPv6 (`::ffff:0:0/96`): the embedded IPv4 as a dotted quad.
/// - Other IPv6: `inet_ntop` output, lowercased.
enum IPAddressText {
  /// Parses an IPv4 or IPv6 literal. A `%zone` suffix is ignored. Returns 4 or 16 bytes, or nil if invalid.
  static func parse(_ text: String) -> [UInt8]? {
    // A C string stops at NUL, so "1.2.3.4\0junk" would otherwise be accepted.
    guard !text.utf8.contains(0) else { return nil }
    let literal = text.firstIndex(of: "%").map { String(text[..<$0]) } ?? text
    guard hasStrictSyntax(literal) else { return nil }
    if literal.contains(":") {
      var address = in6_addr()
      guard inet_pton(AF_INET6, literal, &address) == 1 else { return nil }
      return withUnsafeBytes(of: &address) { Array($0) }
    }
    var address = in_addr()
    guard inet_pton(AF_INET, literal, &address) == 1 else { return nil }
    return withUnsafeBytes(of: &address) { Array($0) }
  }

  /// Canonical text for 4 or 16 address bytes; nil for any other length.
  static func format(_ bytes: [UInt8]) -> String? {
    switch bytes.count {
    case 4:
      return dotted(bytes[...])
    case 16 where isIPv4Mapped(bytes):
      return dotted(bytes[12...])
    case 16:
      var address = in6_addr()
      withUnsafeMutableBytes(of: &address) { $0.copyBytes(from: bytes) }
      var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
      let text: String? = buffer.withUnsafeMutableBufferPointer { out in
        guard inet_ntop(AF_INET6, &address, out.baseAddress, socklen_t(out.count)) != nil else { return nil }
        return String(cString: out.baseAddress!)
      }
      return text?.lowercased()
    default:
      return nil
    }
  }

  /// Canonical text for an IP literal, or nil if the literal is invalid.
  static func canonical(_ text: String) -> String? {
    parse(text).flatMap(format)
  }

  /// The bytes to connect to: an IPv4-mapped IPv6 address becomes its 4 IPv4 bytes.
  static func routable(_ bytes: [UInt8]) -> [UInt8] {
    bytes.count == 16 && isIPv4Mapped(bytes) ? Array(bytes[12...]) : bytes
  }

  /// Apple's inet_pton is more lenient than the ISC rules Android implements: it accepts leading zeros in
  /// IPv4 octets ("010.0.0.1", which some C parsers read as octal) and more than 4 digits in an IPv6 group
  /// ("00001::"). Reject both so the two platforms accept exactly the same literals.
  private static func hasStrictSyntax(_ literal: String) -> Bool {
    for part in literal.split(separator: ":") {
      if part.contains(".") {
        let octets = part.split(separator: ".", omittingEmptySubsequences: false)
        if octets.contains(where: { $0.count > 1 && $0.first == "0" }) { return false }
      } else if part.count > 4 {
        return false
      }
    }
    return true
  }

  private static func isIPv4Mapped(_ bytes: [UInt8]) -> Bool {
    bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xff && bytes[11] == 0xff
  }

  private static func dotted(_ bytes: ArraySlice<UInt8>) -> String {
    bytes.map(String.init).joined(separator: ".")
  }
}
