import Testing
@testable import NslookupCore

/// Shared vectors: android/src/test/.../IpAddressTextTest.kt checks the same table. iOS uses the system
/// inet_pton/inet_ntop, so this suite is the reference; Android must give identical results.
@Suite struct IPAddressTextTests {
  static let canonical: [(String, String)] = [
    ("10.0.0.1", "10.0.0.1"),
    ("0.0.0.0", "0.0.0.0"),
    ("255.255.255.255", "255.255.255.255"),
    ("2001:DB8::1", "2001:db8::1"),
    ("2001:0db8:0000:0000:0000:0000:0000:0001", "2001:db8::1"),
    ("1:0:0:1:0:0:1:1", "1::1:0:0:1:1"),
    ("1:0:1:0:1:0:1:0", "1:0:1:0:1:0:1:0"),
    ("2001:db8:0:0:1:0:0:0", "2001:db8:0:0:1::"),
    ("1:2:3:4:5:6:7::", "1:2:3:4:5:6:7:0"),
    ("::ffff:10.0.0.1", "10.0.0.1"),
    ("::ffff:a00:1", "10.0.0.1"),
    ("fe80::1%en0", "fe80::1"),
    ("FE80::1", "fe80::1"),
    ("::1", "::1"),
    ("::", "::"),
    ("0:0:0:0:0:0:0:0", "::"),
    ("::1.2.3.4", "::1.2.3.4"),
    ("::2", "::2"),
    ("64:ff9b::a00:1", "64:ff9b::a00:1"),
  ]

  static let rejected = [
    "",
    "01.2.3.4",
    "1.2.3",
    "1.2.3.4.",
    "1.2.3.4.5",
    "256.1.1.1",
    "1::2::3",
    ":1::2",
    "1::2:",
    "12345::",
    "1:2:3:4:5:6:7:8:9",
    "1:2:3:4::5:6:7:8",
    "::ffff:1.2.3.4.5",
    "example.com",
    " 1.2.3.4",
    "1.2.3.4 ",
    "１.2.3.4",
    "1.2.3.4\u{0}junk",
    "1.2.3.04",
    "010.0.0.1",
    "00001::",
    "::01.2.3.4",
    "::ffff:01.2.3.4",
  ]

  @Test(arguments: canonical)
  func canonicalForm(input: String, expected: String) {
    #expect(IPAddressText.canonical(input) == expected)
  }

  @Test(arguments: rejected)
  func rejectsInvalidLiteral(input: String) {
    #expect(IPAddressText.parse(input) == nil)
  }

  @Test func formatsRawBytes() {
    #expect(IPAddressText.format([192, 168, 1, 1]) == "192.168.1.1")
    let mapped: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 10, 0, 0, 1]
    #expect(IPAddressText.format(mapped) == "10.0.0.1")
    #expect(IPAddressText.routable(mapped) == [10, 0, 0, 1])
    #expect(IPAddressText.format([1, 2, 3]) == nil)
  }
}
