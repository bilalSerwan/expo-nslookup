package expo.modules.nslookup

import expo.modules.nslookup.DnsMessage.Classification
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** ios/CoreTests/DnsMessageTests.swift checks the same cases. */
class DnsMessageTest {
  private val id = 0x1234
  private val question = DnsMessage.encodeQuestion("www.example.com")

  @Test
  fun normalizesValidDomains() {
    assertEquals("example.com", DnsMessage.normalizeDomain("example.com"))
    assertEquals("example.com", DnsMessage.normalizeDomain("example.com."))
    assertEquals("_dmarc.Example-1.com", DnsMessage.normalizeDomain("_dmarc.Example-1.com"))
    assertEquals("localhost", DnsMessage.normalizeDomain("localhost"))
  }

  @Test
  fun enforcesLabelAndNameLengths() {
    val label63 = "a".repeat(63)
    assertEquals("$label63.com", DnsMessage.normalizeDomain("$label63.com"))
    assertNull(DnsMessage.normalizeDomain("${label63}a.com"))

    val name253 = List(4) { "a".repeat(62) }.joinToString(".") + ".a" // 4*62 + 3 dots + 2 = 253
    assertEquals(253, name253.length)
    assertEquals(name253, DnsMessage.normalizeDomain(name253))
    assertEquals(name253, DnsMessage.normalizeDomain("$name253."))
    assertNull(DnsMessage.normalizeDomain(name253 + "a"))
  }

  @Test
  fun rejectsInvalidDomains() {
    for (domain in listOf("", ".", "..", "a..b", ".a", "a.b..", "exämple.com", "ex ample.com", "a/b", "1.2.3.4:53")) {
      assertNull("'$domain' should be rejected", DnsMessage.normalizeDomain(domain))
    }
  }

  @Test
  fun encodesQuery() {
    val expectedQuestion = byteArrayOf(3) + "www".toByteArray() + byteArrayOf(7) + "example".toByteArray() +
      byteArrayOf(3) + "com".toByteArray() + byteArrayOf(0, 0, 1, 0, 1)
    assertArrayEquals(expectedQuestion, question)

    val query = DnsMessage.buildQuery(id, question)
    assertArrayEquals(byteArrayOf(0x12, 0x34, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0), query.copyOfRange(0, 12))
    assertArrayEquals(question, query.copyOfRange(12, query.size))
  }

  @Test
  fun extractsARecordsWithCompressedOwnerName() {
    val response = Response(id, question).answer(pointerName, type = 1, rdata = ip(10, 0, 0, 5)).build()
    assertEquals(Classification.Addresses(listOf("10.0.0.5")), classify(response))
  }

  @Test
  fun skipsLabelsFollowedByAPointer() {
    val name = byteArrayOf(3) + "www".toByteArray() + pointerName
    val response = Response(id, question).answer(name, type = 1, rdata = ip(10, 0, 0, 6)).build()
    assertEquals(Classification.Addresses(listOf("10.0.0.6")), classify(response))
  }

  @Test
  fun followsCnameThenA() {
    val cnameTarget = byteArrayOf(4) + "edge".toByteArray() + pointerName
    val response = Response(id, question)
      .answer(pointerName, type = 5, rdata = cnameTarget)
      .answer(byteArrayOf(0xc0.toByte(), 0x2d), type = 1, rdata = ip(10, 1, 1, 1))
      .build()
    assertEquals(Classification.Addresses(listOf("10.1.1.1")), classify(response))
  }

  @Test
  fun dedupesAddressesInAnswerOrder() {
    val response = Response(id, question)
      .answer(pointerName, type = 1, rdata = ip(10, 0, 0, 2))
      .answer(pointerName, type = 1, rdata = ip(10, 0, 0, 1))
      .answer(pointerName, type = 1, rdata = ip(10, 0, 0, 2))
      .build()
    assertEquals(Classification.Addresses(listOf("10.0.0.2", "10.0.0.1")), classify(response))
  }

  @Test
  fun ignoresForeignOrMalformedHeaders() {
    assertEquals(Classification.Ignore, classify(Response(0x9999, question).build()))
    assertEquals(Classification.Ignore, classify(Response(id, question, flags = 0x0100).build())) // QR = 0
    assertEquals(Classification.Ignore, classify(Response(id, question, flags = 0x8000 or (2 shl 11)).build())) // OPCODE 2
    assertEquals(Classification.Ignore, classify(ByteArray(11)))
    val otherQuestion = DnsMessage.encodeQuestion("www.example.org")
    assertEquals(Classification.Ignore, classify(Response(id, otherQuestion).build()))
  }

  @Test
  fun matchesQuestionCaseInsensitively() {
    val upper = DnsMessage.encodeQuestion("WWW.Example.COM")
    val response = Response(id, upper).answer(pointerName, type = 1, rdata = ip(10, 0, 0, 7)).build()
    assertEquals(Classification.Addresses(listOf("10.0.0.7")), classify(response))
  }

  @Test
  fun classifiesRcodes() {
    assertEquals(Classification.Negative, classify(Response(id, question, rcode = 3).build())) // NXDOMAIN
    assertEquals(Classification.Negative, classify(Response(id, question, rcode = 5).build())) // REFUSED
    assertEquals(Classification.Negative, classify(Response(id, question, rcode = 1).build())) // FORMERR
    assertEquals(Classification.Transient, classify(Response(id, question, rcode = 2).build())) // SERVFAIL
    assertEquals(Classification.Negative, classify(Response(id, question).build())) // NOERROR, no data
  }

  @Test
  fun handlesMissingQuestionSection() {
    assertEquals(Classification.Negative, classify(Response(id, question, rcode = 5, includeQuestion = false).build()))
    assertEquals(Classification.Ignore, classify(Response(id, question, includeQuestion = false).build()))
  }

  @Test
  fun ignoresNonInternetAndNonARecords() {
    val chaos = Response(id, question).answer(pointerName, type = 1, klass = 3, rdata = ip(10, 0, 0, 8)).build()
    assertEquals(Classification.Negative, classify(chaos))
    val aaaa = Response(id, question).answer(pointerName, type = 28, rdata = ByteArray(16)).build()
    assertEquals(Classification.Negative, classify(aaaa))
  }

  @Test
  fun handlesTruncation() {
    val withAddress = Response(id, question, truncated = true).answer(pointerName, type = 1, rdata = ip(10, 0, 0, 9)).build()
    assertEquals(Classification.Addresses(listOf("10.0.0.9")), classify(withAddress))
    assertEquals(Classification.Transient, classify(Response(id, question, truncated = true).build()))
  }

  @Test
  fun treatsCutOffRecordsAsTransient() {
    val full = Response(id, question).answer(pointerName, type = 1, rdata = ip(10, 0, 0, 1)).build()
    assertEquals(Classification.Transient, classify(full.copyOf(full.size - 2)))

    val badLabelType = Response(id, question).answer(byteArrayOf(0x40, 0), type = 1, rdata = ip(10, 0, 0, 1)).build()
    assertEquals(Classification.Transient, classify(badLabelType))
  }

  @Test
  fun keepsAddressesBeforeAMalformedRecord() {
    val response = Response(id, question)
      .answer(pointerName, type = 1, rdata = ip(10, 0, 0, 1))
      .answer(byteArrayOf(0x80.toByte(), 0), type = 1, rdata = ip(10, 0, 0, 2))
      .build()
    assertEquals(Classification.Addresses(listOf("10.0.0.1")), classify(response))
  }

  private fun classify(packet: ByteArray) = DnsMessage.classify(packet, packet.size, id, question)

  companion object {
    /** A compression pointer to the question name at offset 12. */
    val pointerName = byteArrayOf(0xc0.toByte(), 0x0c)

    fun ip(a: Int, b: Int, c: Int, d: Int) = byteArrayOf(a.toByte(), b.toByte(), c.toByte(), d.toByte())
  }
}

/** Builds DNS response packets for tests. */
internal class Response(
  private val id: Int,
  private val question: ByteArray,
  private val rcode: Int = 0,
  private val truncated: Boolean = false,
  private val includeQuestion: Boolean = true,
  private val flags: Int = 0x8180 or rcode or (if (truncated) 0x0200 else 0),
) {
  private val answers = mutableListOf<ByteArray>()

  fun answer(name: ByteArray, type: Int, klass: Int = 1, rdata: ByteArray): Response {
    answers += name + u16(type) + u16(klass) + byteArrayOf(0, 0, 0x0e, 0x10) + u16(rdata.size) + rdata
    return this
  }

  fun build(): ByteArray {
    val header = u16(id) + u16(flags) + u16(if (includeQuestion) 1 else 0) + u16(answers.size) + u16(0) + u16(0)
    val body = if (includeQuestion) question else ByteArray(0)
    return answers.fold(header + body) { acc, a -> acc + a }
  }

  private fun u16(v: Int) = byteArrayOf((v shr 8).toByte(), v.toByte())
}
