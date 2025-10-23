import ExpoNslookupModule, { DNSLookupResult } from "./ExpoNslookupModule";
export { default } from "./ExpoNslookupModule";
export type { DNSLookupResult, DNSLookupOptions } from "./ExpoNslookupModule";

export async function lookup(domain: string): Promise<boolean> {
  const result = await ExpoNslookupModule.lookup(domain);
  return result.success && result.hasAddresses;
}

export async function advanceLookup(
  domain: string,
  timeout: number
): Promise<DNSLookupResult> {
  return await ExpoNslookupModule.lookup(domain, { timeout });
}
