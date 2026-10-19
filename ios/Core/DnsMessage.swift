/*
 * DNS wire format for one A-record question. android/.../DnsMessage.kt implements the same rules;
 * change both files together.
 *
 * Domain: drop one trailing '.'; 1-253 characters; labels of 1-63 characters from [A-Za-z0-9_-]
 * (ASCII only, so IDNs must be passed as punycode). Case is kept as given.
 *
 * Query: header = ID, flags 0x0100 (RD), QDCOUNT 1, other counts 0; question = QNAME, QTYPE A, QCLASS IN.
 *
 * classify(response):
 * 1. Ignore when shorter than 12 bytes, the ID differs, QR is 0 or OPCODE is not 0.
 * 2. QDCOUNT 1: the question section must equal ours (ASCII case-insensitive), else Ignore.
 *    QDCOUNT 0 is accepted only with a non-zero RCODE. Any other QDCOUNT: Ignore.
 * 3. RCODE 2 (SERVFAIL): Transient. Any other non-zero RCODE: Negative.
 * 4. RCODE 0: walk ANCOUNT records, collecting TYPE A / CLASS IN / RDLENGTH 4. Owner names are not checked,
 *    so CNAME chains work. Stop at the first malformed record. Then: any address -> Addresses (even if TC is
 *    set); else TC set or malformed -> Transient; else Negative.
 *
 * skipName never follows compression pointers, so it cannot loop: 0 ends the name, 0b11 prefix is a 2-byte
 * pointer that ends the name, 0b00 prefix is a label; 0b01 and 0b10 label types are malformed.
 */
enum DnsMessage {
  static let maxDomainLength = 253
  static let maxLabelLength = 63

  private static let headerSize = 12
  private static let typeA: UInt16 = 1
  private static let classIN: UInt16 = 1
  private static let rcodeServfail: UInt16 = 2

  enum Classification: Equatable, Sendable {
    case ignore
    case addresses([String])
    case negative
    case transient
  }

  /// Returns the domain without one trailing dot, or nil when it breaks the domain rules above.
  static func normalizeDomain(_ domain: String) -> String? {
    let name = domain.hasSuffix(".") ? String(domain.dropLast()) : domain
    let bytes = Array(name.utf8)
    guard !bytes.isEmpty, bytes.count <= maxDomainLength else { return nil }
    let labelsValid = bytes.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false).allSatisfy { label in
      (1...maxLabelLength).contains(label.count) && label.allSatisfy(isLabelByte)
    }
    return labelsValid ? name : nil
  }

  /// Encodes the question section (QNAME, QTYPE A, QCLASS IN) for a domain already passed through `normalizeDomain`.
  static func encodeQuestion(_ domain: String) -> [UInt8] {
    var out: [UInt8] = []
    out.reserveCapacity(domain.utf8.count + 6)
    for label in domain.utf8.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false) {
      out.append(UInt8(label.count))
      out.append(contentsOf: label)
    }
    out.append(0)
    out.append(contentsOf: [0, UInt8(typeA), 0, UInt8(classIN)])
    return out
  }

  static func buildQuery(id: UInt16, question: [UInt8]) -> [UInt8] {
    let header: [UInt8] = [
      UInt8(id >> 8), UInt8(id & 0xff),
      0x01, 0x00, // flags: RD
      0x00, 0x01, // QDCOUNT
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // ANCOUNT, NSCOUNT, ARCOUNT
    ]
    return header + question
  }

  static func classify(_ packet: [UInt8], id: UInt16, question: [UInt8]) -> Classification {
    let length = packet.count
    guard length >= headerSize, u16(packet, 0) == id else { return .ignore }
    let flags = u16(packet, 2)
    let isResponse = flags & 0x8000 != 0
    let opcode = (flags >> 11) & 0x0f
    let truncated = flags & 0x0200 != 0
    let rcode = flags & 0x000f
    guard isResponse, opcode == 0 else { return .ignore }

    let answersStart: Int
    switch u16(packet, 4) {
    case 1:
      guard questionMatches(packet, question) else { return .ignore }
      answersStart = headerSize + question.count
    case 0 where rcode != 0:
      answersStart = headerSize
    default:
      return .ignore
    }

    if rcode == rcodeServfail { return .transient }
    if rcode != 0 { return .negative }

    var ips: [String] = []
    var malformed = false
    var p = answersStart
    for _ in 0..<u16(packet, 6) {
      guard let afterName = skipName(packet, from: p), afterName + 10 <= length else {
        malformed = true
        break
      }
      let type = u16(packet, afterName)
      let klass = u16(packet, afterName + 2)
      let rdLength = Int(u16(packet, afterName + 8))
      let rdata = afterName + 10
      guard rdata + rdLength <= length else {
        malformed = true
        break
      }
      if type == typeA, klass == classIN, rdLength == 4,
         let ip = IPAddressText.format(Array(packet[rdata..<rdata + 4])), !ips.contains(ip) {
        ips.append(ip)
      }
      p = rdata + rdLength
    }

    if !ips.isEmpty { return .addresses(ips) }
    return truncated || malformed ? .transient : .negative
  }

  /// Returns the offset just past the name starting at `start`, or nil when the name is malformed.
  static func skipName(_ packet: [UInt8], from start: Int) -> Int? {
    var p = start
    while p < packet.count {
      let b = Int(packet[p])
      switch b & 0xc0 {
      case 0x00:
        if b == 0 { return p + 1 }
        p += 1 + b
      case 0xc0:
        return p + 1 < packet.count ? p + 2 : nil
      default:
        return nil
      }
    }
    return nil
  }

  private static func isLabelByte(_ b: UInt8) -> Bool {
    switch b {
    case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
         UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"):
      return true
    default:
      return false
    }
  }

  private static func questionMatches(_ packet: [UInt8], _ question: [UInt8]) -> Bool {
    guard headerSize + question.count <= packet.count else { return false }
    return question.indices.allSatisfy { asciiLower(packet[headerSize + $0]) == asciiLower(question[$0]) }
  }

  private static func asciiLower(_ b: UInt8) -> UInt8 {
    (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(b) ? b + 32 : b
  }

  private static func u16(_ packet: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(packet[offset]) << 8 | UInt16(packet[offset + 1])
  }
}
