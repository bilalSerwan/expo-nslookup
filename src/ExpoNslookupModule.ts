import { NativeModule, requireNativeModule } from "expo";

import type {
  CustomDnsLookupResult,
  DnsServerComparison,
} from "./ExpoNslookup.types";

// iOS omits a nil optional field from the returned object instead of sending null.
export type NativeLookupResult = Omit<CustomDnsLookupResult, "server"> & {
  server?: string | null;
};

declare class ExpoNslookupModule extends NativeModule {
  nsLookupWithCustomDns(
    domain: string,
    dnsServers: string[],
    timeoutMs: number,
  ): Promise<NativeLookupResult>;

  getDnsServers(): Promise<string[]>;

  compareDnsServers(expectedServers: string[]): Promise<DnsServerComparison>;
}

export default requireNativeModule<ExpoNslookupModule>("ExpoNslookup");
