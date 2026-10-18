import Testing
@testable import NslookupCore

/// android/src/test/.../DnsMessageTest.kt checks the same cases.
@Suite struct DnsMessageTests {
  let id: UInt16 = 0x1234
  let question = DnsMessage.encodeQuestion("www.example.com")

  /// A compression pointer to the question name at offset 12.
  static let pointerName: [UInt8] = [0xc0, 0x0c]

  @Test func normalizesValidDomains() {
    #expect(DnsMessage.normalizeDomain("example.com") == "example.com")
    #expect(DnsMessage.normalizeDomain("example.com.") == "example.com")
    #expect(DnsMessage.normalizeDomain("_dmarc.Example-1.com") == "_dmarc.Example-1.com")
    #expect(DnsMessage.normalizeDomain("localhost") == "localhost")
  }

  @Test func enforcesLabelAndNameLengths() {
    let label63 = String(repeating: "a", count: 63)
    #expect(DnsMessage.normalizeDomain("\(label63).com") == "\(label63).com")
    #expect(DnsMessage.normalizeDomain("\(label63)a.com") == nil)

    let name253 = Array(repeating: String(repeating: "a", count: 62), count: 4).joined(separator: ".") + ".a"
    #expect(name253.count == 253)
    #expect(DnsMessage.normalizeDomain(name253) == name253)
    #expect(DnsMessage.normalizeDomain(name253 + ".") == name253)
    #expect(DnsMessage.normalizeDomain(name253 + "a") == nil)
  }

  @Test(arguments: ["", ".", "..", "a..b", ".a", "a.b..", "exämple.com", "ex ample.com", "a/b", "1.2.3.4:53", "a\u{0}b"])
  func rejectsInvalidDomain(domain: String) {
    #expect(DnsMessage.normalizeDomain(domain) == nil)
  }

  @Test func encodesQuery() {
    let expectedQuestion: [UInt8] = [3] + Array("www".utf8) + [7] + Array("example".utf8) + [3] + Array("com".utf8) + [0, 0, 1, 0, 1]
    #expect(question == expectedQuestion)

    let query = DnsMessage.buildQuery(id: id, question: question)
    #expect(Array(query[0..<12]) == [0x12, 0x34, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0])
    #expect(Array(query[12...]) == question)
  }

  @Test func extractsARecordsWithCompressedOwnerName() {
    let response = Response(id: id, question: question).answer(Self.pointerName, type: 1, rdata: [10, 0, 0, 5]).build()
    #expect(classify(response) == .addresses(["10.0.0.5"]))
  }

  @Test func skipsLabelsFollowedByAPointer() {
    let name: [UInt8] = [3] + Array("www".utf8) + Self.pointerName
    let response = Response(id: id, question: question).answer(name, type: 1, rdata: [10, 0, 0, 6]).build()
    #expect(classify(response) == .addresses(["10.0.0.6"]))
  }

  @Test func followsCnameThenA() {
    let cnameTarget: [UInt8] = [4] + Array("edge".utf8) + Self.pointerName
    let response = Response(id: id, question: question)
      .answer(Self.pointerName, type: 5, rdata: cnameTarget)
      .answer([0xc0, 0x2d], type: 1, rdata: [10, 1, 1, 1])
      .build()
    #expect(classify(response) == .addresses(["10.1.1.1"]))
  }

  @Test func dedupesAddressesInAnswerOrder() {
    let response = Response(id: id, question: question)
      .answer(Self.pointerName, type: 1, rdata: [10, 0, 0, 2])
      .answer(Self.pointerName, type: 1, rdata: [10, 0, 0, 1])
      .answer(Self.pointerName, type: 1, rdata: [10, 0, 0, 2])
      .build()
    #expect(classify(response) == .addresses(["10.0.0.2", "10.0.0.1"]))
  }

  @Test func ignoresForeignOrMalformedHeaders() {
    #expect(classify(Response(id: 0x9999, question: question).build()) == .ignore)
    #expect(classify(Response(id: id, question: question, flags: 0x0100).build()) == .ignore) // QR = 0
    #expect(classify(Response(id: id, question: question, flags: 0x8000 | (2 << 11)).build()) == .ignore) // OPCODE 2
    #expect(classify([UInt8](repeating: 0, count: 11)) == .ignore)
    let otherQuestion = DnsMessage.encodeQuestion("www.example.org")
    #expect(classify(Response(id: id, question: otherQuestion).build()) == .ignore)
  }

  @Test func matchesQuestionCaseInsensitively() {
    let upper = DnsMessage.encodeQuestion("WWW.Example.COM")
    let response = Response(id: id, question: upper).answer(Self.pointerName, type: 1, rdata: [10, 0, 0, 7]).build()
    #expect(classify(response) == .addresses(["10.0.0.7"]))
  }

  @Test func classifiesRcodes() {
    #expect(classify(Response(id: id, question: question, rcode: 3).build()) == .negative) // NXDOMAIN
    #expect(classify(Response(id: id, question: question, rcode: 5).build()) == .negative) // REFUSED
    #expect(classify(Response(id: id, question: question, rcode: 1).build()) == .negative) // FORMERR
    #expect(classify(Response(id: id, question: question, rcode: 2).build()) == .transient) // SERVFAIL
    #expect(classify(Response(id: id, question: question).build()) == .negative) // NOERROR, no data
  }

  @Test func handlesMissingQuestionSection() {
    #expect(classify(Response(id: id, question: question, rcode: 5, includeQuestion: false).build()) == .negative)
    #expect(classify(Response(id: id, question: question, includeQuestion: false).build()) == .ignore)
  }

  @Test func ignoresNonInternetAndNonARecords() {
    let chaos = Response(id: id, question: question).answer(Self.pointerName, type: 1, klass: 3, rdata: [10, 0, 0, 8]).build()
    #expect(classify(chaos) == .negative)
    let aaaa = Response(id: id, question: question).answer(Self.pointerName, type: 28, rdata: [UInt8](repeating: 0, count: 16)).build()
    #expect(classify(aaaa) == .negative)
  }

  @Test func handlesTruncation() {
    let withAddress = Response(id: id, question: question, truncated: true)
      .answer(Self.pointerName, type: 1, rdata: [10, 0, 0, 9]).build()
    #expect(classify(withAddress) == .addresses(["10.0.0.9"]))
    #expect(classify(Response(id: id, question: question, truncated: true).build()) == .transient)
  }

  @Test func treatsCutOffRecordsAsTransient() {
    let full = Response(id: id, question: question).answer(Self.pointerName, type: 1, rdata: [10, 0, 0, 1]).build()
    #expect(classify(Array(full.dropLast(2))) == .transient)

    let badLabelType = Response(id: id, question: question).answer([0x40, 0], type: 1, rdata: [10, 0, 0, 1]).build()
    #expect(classify(badLabelType) == .transient)
  }

  @Test func keepsAddressesBeforeAMalformedRecord() {
    let response = Response(id: id, question: question)
      .answer(Self.pointerName, type: 1, rdata: [10, 0, 0, 1])
      .answer([0x80, 0], type: 1, rdata: [10, 0, 0, 2])
      .build()
    #expect(classify(response) == .addresses(["10.0.0.1"]))
  }

  private func classify(_ packet: [UInt8]) -> DnsMessage.Classification {
    DnsMessage.classify(packet, id: id, question: question)
  }
}

/// Builds DNS response packets for tests.
struct Response {
  let id: UInt16
  let question: [UInt8]
  var rcode: UInt16 = 0
  var truncated = false
  var includeQuestion = true
  var flags: UInt16?
  private var answers: [[UInt8]] = []

  init(id: UInt16, question: [UInt8], rcode: UInt16 = 0, truncated: Bool = false, includeQuestion: Bool = true, flags: UInt16? = nil) {
    self.id = id
    self.question = question
    self.rcode = rcode
    self.truncated = truncated
    self.includeQuestion = includeQuestion
    self.flags = flags
  }

  func answer(_ name: [UInt8], type: UInt16, klass: UInt16 = 1, rdata: [UInt8]) -> Response {
    var copy = self
    copy.answers.append(name + u16(type) + u16(klass) + [0, 0, 0x0e, 0x10] + u16(UInt16(rdata.count)) + rdata)
    return copy
  }

  func build() -> [UInt8] {
    let headerFlags = flags ?? (0x8180 | rcode | (truncated ? 0x0200 : 0))
    let header = u16(id) + u16(headerFlags) + u16(includeQuestion ? 1 : 0) + u16(UInt16(answers.count)) + u16(0) + u16(0)
    return answers.reduce(header + (includeQuestion ? question : [])) { $0 + $1 }
  }

  private func u16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xff)] }
}
