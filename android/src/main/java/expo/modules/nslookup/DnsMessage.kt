package expo.modules.nslookup

/*
 * DNS wire format for one A-record question. ios/Core/DnsMessage.swift implements the same rules;
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
internal object DnsMessage {
  const val MAX_DOMAIN_LENGTH = 253
  const val MAX_LABEL_LENGTH = 63

  private const val HEADER_SIZE = 12
  private const val TYPE_A = 1
  private const val CLASS_IN = 1
  private const val RCODE_SERVFAIL = 2

  sealed interface Classification {
    data object Ignore : Classification
    data class Addresses(val ips: List<String>) : Classification
    data object Negative : Classification
    data object Transient : Classification
  }

  /** Returns the domain without one trailing dot, or null when it breaks the domain rules above. */
  fun normalizeDomain(domain: String): String? {
    val name = domain.removeSuffix(".")
    if (name.isEmpty() || name.length > MAX_DOMAIN_LENGTH) return null
    val labelsValid = name.split('.').all { label ->
      label.length in 1..MAX_LABEL_LENGTH && label.all(::isLabelChar)
    }
    return if (labelsValid) name else null
  }

  /** Encodes the question section (QNAME, QTYPE A, QCLASS IN) for a domain already passed through [normalizeDomain]. */
  fun encodeQuestion(domain: String): ByteArray {
    val out = ArrayList<Byte>(domain.length + 6)
    for (label in domain.split('.')) {
      out.add(label.length.toByte())
      label.forEach { out.add(it.code.toByte()) }
    }
    out.add(0)
    out.addAll(listOf(0, TYPE_A, 0, CLASS_IN).map(Int::toByte))
    return out.toByteArray()
  }

  fun buildQuery(id: Int, question: ByteArray): ByteArray {
    val header = byteArrayOf(
      (id shr 8).toByte(), id.toByte(),
      0x01, 0x00, // flags: RD
      0x00, 0x01, // QDCOUNT
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // ANCOUNT, NSCOUNT, ARCOUNT
    )
    return header + question
  }

  fun classify(packet: ByteArray, length: Int, id: Int, question: ByteArray): Classification {
    if (length < HEADER_SIZE || length > packet.size) return Classification.Ignore
    if (u16(packet, 0) != id) return Classification.Ignore
    val flags = u16(packet, 2)
    val isResponse = flags and 0x8000 != 0
    val opcode = (flags shr 11) and 0x0f
    val truncated = flags and 0x0200 != 0
    val rcode = flags and 0x000f
    if (!isResponse || opcode != 0) return Classification.Ignore

    val answersStart = when (u16(packet, 4)) {
      1 -> {
        if (!questionMatches(packet, length, question)) return Classification.Ignore
        HEADER_SIZE + question.size
      }
      0 -> if (rcode != 0) HEADER_SIZE else return Classification.Ignore
      else -> return Classification.Ignore
    }

    if (rcode == RCODE_SERVFAIL) return Classification.Transient
    if (rcode != 0) return Classification.Negative

    val ips = LinkedHashSet<String>()
    var malformed = false
    var p = answersStart
    for (record in 0 until u16(packet, 6)) {
      val afterName = skipName(packet, length, p)
      if (afterName == null || afterName + 10 > length) {
        malformed = true
        break
      }
      val type = u16(packet, afterName)
      val klass = u16(packet, afterName + 2)
      val rdLength = u16(packet, afterName + 8)
      val rdata = afterName + 10
      if (rdata + rdLength > length) {
        malformed = true
        break
      }
      if (type == TYPE_A && klass == CLASS_IN && rdLength == 4) {
        ips.add(IpAddressText.format(packet.copyOfRange(rdata, rdata + 4)))
      }
      p = rdata + rdLength
    }

    return when {
      ips.isNotEmpty() -> Classification.Addresses(ips.toList())
      truncated || malformed -> Classification.Transient
      else -> Classification.Negative
    }
  }

  /** Returns the offset just past the name starting at [start], or null when the name is malformed. */
  fun skipName(packet: ByteArray, length: Int, start: Int): Int? {
    var p = start
    while (p < length) {
      val b = packet[p].toInt() and 0xff
      when (b and 0xc0) {
        0x00 -> {
          if (b == 0) return p + 1
          p += 1 + b
        }
        0xc0 -> return if (p + 1 < length) p + 2 else null
        else -> return null
      }
    }
    return null
  }

  private fun isLabelChar(c: Char): Boolean =
    c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9' || c == '-' || c == '_'

  private fun questionMatches(packet: ByteArray, length: Int, question: ByteArray): Boolean {
    if (HEADER_SIZE + question.size > length) return false
    return question.indices.all { i -> asciiLower(packet[HEADER_SIZE + i]) == asciiLower(question[i]) }
  }

  private fun asciiLower(b: Byte): Int {
    val v = b.toInt() and 0xff
    return if (v in 'A'.code..'Z'.code) v + 32 else v
  }

  private fun u16(packet: ByteArray, offset: Int): Int =
    ((packet[offset].toInt() and 0xff) shl 8) or (packet[offset + 1].toInt() and 0xff)
}
