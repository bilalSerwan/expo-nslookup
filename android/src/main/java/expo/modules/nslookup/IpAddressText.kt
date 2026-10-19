package expo.modules.nslookup

/**
 * Strict IP-literal parsing and canonical formatting.
 *
 * Parsing mirrors the C library's `inet_pton` and formatting mirrors `inet_ntop` (the ISC code that iOS
 * also uses), so Android produces exactly the same text as iOS. Nothing here performs a DNS lookup.
 *
 * Canonical text:
 * - IPv4: dotted quad.
 * - IPv4-mapped IPv6 (`::ffff:0:0/96`): the embedded IPv4 as a dotted quad.
 * - Other IPv6: `inet_ntop` output, lowercase, longest zero run (first on a tie, at least 2 groups) as `::`.
 */
internal object IpAddressText {
  private const val IPV4_SIZE = 4
  private const val IPV6_SIZE = 16

  /** Parses an IPv4 or IPv6 literal. A `%zone` suffix is ignored. Returns 4 or 16 bytes, or null if invalid. */
  fun parse(text: String): ByteArray? {
    val literal = text.substringBefore('%')
    return if (literal.contains(':')) parseIpv6(literal) else parseIpv4(literal)
  }

  /** Canonical text for 4 or 16 address bytes. */
  fun format(bytes: ByteArray): String {
    require(bytes.size == IPV4_SIZE || bytes.size == IPV6_SIZE) { "Expected 4 or 16 bytes, got ${bytes.size}" }
    if (bytes.size == IPV4_SIZE) return formatIpv4(bytes, 0)
    if (isIpv4Mapped(bytes)) return formatIpv4(bytes, 12)
    return formatIpv6(bytes)
  }

  /** Canonical text for an IP literal, or null if the literal is invalid. */
  fun canonical(text: String): String? = parse(text)?.let(::format)

  private fun isIpv4Mapped(b: ByteArray): Boolean =
    (0 until 10).all { b[it].toInt() == 0 } && b[10].toInt() == -1 && b[11].toInt() == -1

  private fun formatIpv4(b: ByteArray, offset: Int): String =
    (offset until offset + IPV4_SIZE).joinToString(".") { (b[it].toInt() and 0xff).toString() }

  // inet_pton4: exactly four decimal octets, each 0-255, no leading zeros, nothing else.
  private fun parseIpv4(src: String): ByteArray? {
    val out = ByteArray(IPV4_SIZE)
    var octets = 0
    var sawDigit = false
    var current = 0
    for (ch in src) {
      when {
        ch in '0'..'9' -> {
          if (sawDigit && current == 0) return null
          current = current * 10 + (ch - '0')
          if (current > 255) return null
          if (!sawDigit) {
            if (++octets > IPV4_SIZE) return null
            sawDigit = true
          }
          out[octets - 1] = current.toByte()
        }
        ch == '.' && sawDigit -> {
          if (octets == IPV4_SIZE) return null
          sawDigit = false
          current = 0
        }
        else -> return null
      }
    }
    return if (octets < IPV4_SIZE) null else out
  }

  // inet_pton6: 1-4 hex digits per group, at most one "::" standing for at least one group,
  // an optional trailing dotted IPv4, exactly 16 bytes in total.
  private fun parseIpv6(src: String): ByteArray? {
    val out = ByteArray(IPV6_SIZE)
    var i = 0
    if (src.startsWith(":")) {
      if (src.length < 2 || src[1] != ':') return null
      i = 1
    }
    var tp = 0
    var colonp = -1
    var curtok = i
    var seenXDigits = 0
    var value = 0
    while (i < src.length) {
      val ch = src[i++]
      val digit = Character.digit(ch, 16)
      if (digit >= 0 && ch.code < 128) {
        value = (value shl 4) or digit
        if (++seenXDigits > 4) return null
        continue
      }
      if (ch == ':') {
        curtok = i
        if (seenXDigits == 0) {
          if (colonp >= 0) return null
          colonp = tp
          continue
        } else if (i == src.length) {
          return null
        }
        if (tp + 2 > IPV6_SIZE) return null
        out[tp++] = (value shr 8).toByte()
        out[tp++] = value.toByte()
        seenXDigits = 0
        value = 0
        continue
      }
      if (ch == '.' && tp + IPV4_SIZE <= IPV6_SIZE) {
        val v4 = parseIpv4(src.substring(curtok)) ?: return null
        v4.copyInto(out, tp)
        tp += IPV4_SIZE
        seenXDigits = 0
        i = src.length
        break
      }
      return null
    }
    if (seenXDigits > 0) {
      if (tp + 2 > IPV6_SIZE) return null
      out[tp++] = (value shr 8).toByte()
      out[tp++] = value.toByte()
    }
    if (colonp >= 0) {
      if (tp == IPV6_SIZE) return null
      val n = tp - colonp
      for (k in 1..n) {
        out[IPV6_SIZE - k] = out[colonp + n - k]
        out[colonp + n - k] = 0
      }
      tp = IPV6_SIZE
    }
    return if (tp == IPV6_SIZE) out else null
  }

  // inet_ntop6, including its dotted form for IPv4-compatible addresses (::a.b.c.d).
  private fun formatIpv6(b: ByteArray): String {
    val words = IntArray(8) { ((b[2 * it].toInt() and 0xff) shl 8) or (b[2 * it + 1].toInt() and 0xff) }
    var bestBase = -1
    var bestLen = 0
    var curBase = -1
    var curLen = 0
    for (i in 0 until 8) {
      if (words[i] == 0) {
        if (curBase == -1) {
          curBase = i
          curLen = 1
        } else {
          curLen++
        }
      } else if (curBase != -1) {
        if (bestBase == -1 || curLen > bestLen) {
          bestBase = curBase
          bestLen = curLen
        }
        curBase = -1
      }
    }
    if (curBase != -1 && (bestBase == -1 || curLen > bestLen)) {
      bestBase = curBase
      bestLen = curLen
    }
    if (bestBase != -1 && bestLen < 2) bestBase = -1

    val out = StringBuilder()
    for (i in 0 until 8) {
      if (bestBase != -1 && i >= bestBase && i < bestBase + bestLen) {
        if (i == bestBase) out.append(':')
        continue
      }
      if (i != 0) out.append(':')
      val ipv4Tail = i == 6 && bestBase == 0 &&
        (bestLen == 6 || (bestLen == 7 && words[7] != 0x0001) || (bestLen == 5 && words[5] == 0xffff))
      if (ipv4Tail) {
        out.append(formatIpv4(b, 12))
        return out.toString()
      }
      out.append(Integer.toHexString(words[i]))
    }
    if (bestBase != -1 && bestBase + bestLen == 8) out.append(':')
    return out.toString()
  }
}
