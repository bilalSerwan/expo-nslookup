package expo.modules.nslookup

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Shared vectors: ios/CoreTests/IPAddressTextTests.swift checks the same table. iOS uses the system
 * inet_pton/inet_ntop, so it is the reference; Android must give identical results.
 */
class IpAddressTextTest {
  private val canonical = listOf(
    "10.0.0.1" to "10.0.0.1",
    "0.0.0.0" to "0.0.0.0",
    "255.255.255.255" to "255.255.255.255",
    "2001:DB8::1" to "2001:db8::1",
    "2001:0db8:0000:0000:0000:0000:0000:0001" to "2001:db8::1",
    "1:0:0:1:0:0:1:1" to "1::1:0:0:1:1",
    "1:0:1:0:1:0:1:0" to "1:0:1:0:1:0:1:0",
    "2001:db8:0:0:1:0:0:0" to "2001:db8:0:0:1::",
    "1:2:3:4:5:6:7::" to "1:2:3:4:5:6:7:0",
    "::ffff:10.0.0.1" to "10.0.0.1",
    "::ffff:a00:1" to "10.0.0.1",
    "fe80::1%en0" to "fe80::1",
    "FE80::1" to "fe80::1",
    "::1" to "::1",
    "::" to "::",
    "0:0:0:0:0:0:0:0" to "::",
    "::1.2.3.4" to "::1.2.3.4",
    "::2" to "::2",
    "64:ff9b::a00:1" to "64:ff9b::a00:1",
  )

  private val rejected = listOf(
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
    "1.2.3.04",
    "010.0.0.1",
    "00001::",
    "::01.2.3.4",
    "::ffff:01.2.3.4",
  )

  @Test
  fun canonicalForms() {
    for ((input, expected) in canonical) {
      assertEquals("canonical('$input')", expected, IpAddressText.canonical(input))
    }
  }

  @Test
  fun rejectsInvalidLiterals() {
    for (input in rejected) {
      assertNull("parse('$input') should be rejected", IpAddressText.parse(input))
    }
  }

  @Test
  fun formatsRawBytes() {
    assertEquals("192.168.1.1", IpAddressText.format(byteArrayOf(192.toByte(), 168.toByte(), 1, 1)))
    val mapped = ByteArray(16).also {
      it[10] = -1
      it[11] = -1
      it[12] = 10
      it[15] = 1
    }
    assertEquals("10.0.0.1", IpAddressText.format(mapped))
  }
}
