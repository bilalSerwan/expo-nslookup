import ExpoNslookupModule, {
  DNSLookupResult,
  CustomDnsLookupResult,
} from "./ExpoNslookupModule";
export { default } from "./ExpoNslookupModule";
export type {
  DNSLookupResult,
  CustomDnsLookupResult,
} from "./ExpoNslookupModule";

/**
 * Simple lookup helper that returns a boolean. Uses a default timeout of 1 second.
 */
export async function lookup(domain: string, timeout = 1.0): Promise<boolean> {
  const result = await ExpoNslookupModule.advanceLookUp(domain, timeout);
  return result.success && result.hasAddresses;
}

/**
 * Advanced lookup returning the full DNSLookupResult
 */
export async function advanceLookup(
  domain: string,
  timeout: number
): Promise<DNSLookupResult> {
  return await ExpoNslookupModule.advanceLookUp(domain, timeout);
}

/**
 * Lookup using a custom DNS server. `dnsServers` should be a comma-separated string
 * or a single DNS server address. Returns a platform-specific detailed result.
 */
export async function nsLookupWithCustomDns(
  domain: string,
  dnsServers: string[],
  timeout = 5.0
): Promise<CustomDnsLookupResult> {
  return await ExpoNslookupModule.nsLookUpWithCustomDnsServer(
    domain,
    dnsServers,
    timeout
  );
}
