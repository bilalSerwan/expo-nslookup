import type {
  CustomDnsLookupOptions,
  CustomDnsLookupResult,
  DnsServerComparison,
} from "./ExpoNslookup.types";
import ExpoNslookupModule from "./ExpoNslookupModule";

export * from "./ExpoNslookup.types";

export const DEFAULT_TIMEOUT_MS = 5000;

/**
 * Looks up `domain` by sending DNS queries directly to `dnsServers` (IP literals), all in parallel.
 *
 * Never rejects for a "public" outcome: a network where none of the servers resolves the domain
 * comes back as `isPrivate: false` with a `reason`. Rejects only for invalid arguments, with a code
 * from `NslookupErrorCode`.
 */
export async function nsLookupWithCustomDns(
  domain: string,
  dnsServers: string[],
  options: CustomDnsLookupOptions = {},
): Promise<CustomDnsLookupResult> {
  const result = await ExpoNslookupModule.nsLookupWithCustomDns(
    domain,
    dnsServers,
    options.timeoutMs ?? DEFAULT_TIMEOUT_MS,
  );
  return { ...result, server: result.server ?? null };
}

/**
 * Returns the IPs of the DNS servers the device currently uses to resolve names.
 * Empty when there is no active network. iOS reports at most 3 servers.
 */
export function getDnsServers(): Promise<string[]> {
  return ExpoNslookupModule.getDnsServers();
}

/**
 * Compares the device's current DNS servers with `expectedServers` (IP literals in any valid form).
 * Both sides are compared in canonical IP text, so `2001:DB8:0::1` matches `2001:db8::1`.
 */
export function compareDnsServers(
  expectedServers: string[],
): Promise<DnsServerComparison> {
  return ExpoNslookupModule.compareDnsServers(expectedServers);
}
