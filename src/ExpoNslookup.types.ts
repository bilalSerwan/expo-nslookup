/**
 * Why a lookup ended the way it did.
 *
 * - `resolved`: a DNS server answered with A records for the domain. This is the only "private" outcome.
 * - `notFound`: at least one server answered, but none had an A record (NXDOMAIN, no data, or SERVFAIL until the deadline).
 * - `timeout`: no server gave a usable answer before the deadline, or every server was unreachable.
 * - `offline`: the device has no active network, so nothing was sent.
 */
export type LookupReason = "resolved" | "notFound" | "timeout" | "offline";

export interface CustomDnsLookupResult {
  /** `true` only when `reason` is `'resolved'`. */
  isPrivate: boolean;
  reason: LookupReason;
  /** The queried domain, with one trailing dot removed. */
  domain: string;
  /** IPv4 addresses from the A records, deduplicated, in answer order. Empty unless `reason` is `'resolved'`. */
  ip: string[];
  /**
   * The DNS server (canonical IP text) that decided the result: the one that resolved the domain,
   * or the first one that answered negatively. `null` for `'timeout'` and `'offline'`.
   */
  server: string | null;
  /** Wall-clock duration of the lookup, measured natively, in whole milliseconds. */
  elapsedMs: number;
}

export interface CustomDnsLookupOptions {
  /**
   * Total time budget for the lookup, in milliseconds. Allowed range is 100 to 60000. Defaults to 5000.
   * On a public network the lookup usually ends with `'timeout'`, so this is roughly how long the check takes there.
   */
  timeoutMs?: number;
}

export interface DnsServerComparison {
  /** The device's current DNS servers, exactly as `getDnsServers()` returns them. */
  deviceServers: string[];
  /** The servers you passed in, in canonical IP text, deduplicated, in input order. */
  expectedServers: string[];
  /** The device servers that are also in `expectedServers`, in device order. */
  matchedServers: string[];
  /** `true` when at least one device server is in `expectedServers`. */
  isMatch: boolean;
}

/**
 * Error codes that functions in this module reject with. They are identical on iOS and Android.
 * Branch on `error.code`; the message text differs between platforms.
 */
export const NslookupErrorCode = {
  InvalidDomain: "ERR_INVALID_DOMAIN",
  InvalidDnsServer: "ERR_INVALID_DNS_SERVER",
  InvalidTimeout: "ERR_INVALID_TIMEOUT",
  /** iOS only: the system resolver configuration could not be read. */
  DnsConfigUnavailable: "ERR_DNS_CONFIG_UNAVAILABLE",
} as const;

export type NslookupErrorCode =
  (typeof NslookupErrorCode)[keyof typeof NslookupErrorCode];
