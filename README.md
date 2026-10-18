# expo-nslookup

[![npm version](https://img.shields.io/npm/v/expo-nslookup.svg)](https://www.npmjs.com/package/expo-nslookup)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Native DNS lookups against DNS servers you choose, for Expo and React Native apps on iOS and Android.

The typical use is telling a **private network** (for example your company's network) apart from a **public** one: query your internal DNS servers for an internal domain. If one of them answers, the device is on your network. If none does, it isn't. You get a result in both cases, never an error.

## Features

- **Custom DNS servers:** queries go straight to the server IPs you pass, all in parallel; the first answer wins.
- **Private/public verdict as a result:** `isPrivate` plus a `reason` (`resolved`, `notFound`, `timeout`, `offline`). Only invalid arguments reject.
- **Device DNS servers:** read the DNS servers the device is using right now, and compare them with yours.
- **Same behaviour on iOS and Android:** the same validation rules, the same canonical IP text and the same error codes on both platforms.
- **Fully typed** TypeScript API.

## Installation

Make sure your project has [the `expo` package installed and configured](https://docs.expo.dev/bare/installing-expo-modules/), then:

```bash
npx expo install expo-nslookup
```

On iOS, run `npx pod-install` afterwards (not needed with `expo prebuild` or EAS Build).

## Usage

```typescript
import { nsLookupWithCustomDns } from "expo-nslookup";

const OUR_DNS_SERVERS = ["10.10.0.53", "10.10.1.53"];

const result = await nsLookupWithCustomDns("intranet.example.internal", OUR_DNS_SERVERS, {
  timeoutMs: 3000,
});

if (result.isPrivate) {
  console.log(`On our network: ${result.server} resolved it to ${result.ip.join(", ")}`);
} else {
  console.log(`Public network (${result.reason})`);
}
```

Compare the device's DNS servers with yours:

```typescript
import { compareDnsServers } from "expo-nslookup";

const { isMatch, matchedServers, deviceServers } = await compareDnsServers(["10.10.0.53", "10.10.1.53"]);
```

## API

### `nsLookupWithCustomDns(domain, dnsServers, options?)`

Sends an A-record query for `domain` to every server in `dnsServers`, in parallel, over UDP port 53. Each server gets the same query again at 500 ms, 1.5 s and 3.5 s if it hasn't answered (as far as the timeout allows).

| Parameter | Type | Description |
|---|---|---|
| `domain` | `string` | Domain name. ASCII only (pass IDNs as punycode); labels of 1–63 characters from `A–Z a–z 0–9 - _`; up to 253 characters. One trailing dot is allowed. |
| `dnsServers` | `string[]` | 1 to 16 IPv4 or IPv6 **literals**. Hostnames are rejected. A `%zone` suffix is ignored. Duplicates are removed. |
| `options.timeoutMs` | `number` | Total time budget, 100 to 60000 ms. Default `5000`. |

Returns `Promise<CustomDnsLookupResult>`:

```typescript
interface CustomDnsLookupResult {
  isPrivate: boolean;      // true only when reason === "resolved"
  reason: "resolved" | "notFound" | "timeout" | "offline";
  domain: string;          // as queried, one trailing dot removed
  ip: string[];            // IPv4 addresses from the answer; [] unless resolved
  server: string | null;   // the server that decided the result, or null
  elapsedMs: number;
}
```

| `reason` | Meaning | `server` |
|---|---|---|
| `resolved` | A server answered with A records. **This is the only private outcome.** | the server that answered |
| `notFound` | At least one server answered, but none had an A record (NXDOMAIN, no data, or only SERVFAIL until the timeout). | the first server that answered negatively |
| `timeout` | No server gave a usable answer in time, or every server was unreachable. | `null` |
| `offline` | The device has no active network. Nothing was sent, and the result comes back immediately. | `null` |

**Timing:** on a public network your servers usually don't answer at all, so the lookup typically ends with `timeout` after `timeoutMs`. Choose `timeoutMs` with that in mind. An answer from any server, positive or negative, ends the wait for that server early, and the first positive answer ends the whole lookup.

### `getDnsServers()`

Returns `Promise<string[]>`: the IPs of the DNS servers the device currently uses. It's a local read with no network traffic. The list is empty when there is no active network.

### `compareDnsServers(expectedServers)`

Compares the device's DNS servers with `expectedServers` (1 to 16 IP literals, same rules as above). Both sides are compared in canonical form, so `2001:DB8:0::1` matches `2001:db8::1`.

```typescript
interface DnsServerComparison {
  deviceServers: string[];   // same as getDnsServers()
  expectedServers: string[]; // your input, canonical, deduplicated
  matchedServers: string[];  // device servers that are in expectedServers
  isMatch: boolean;          // matchedServers.length > 0
}
```

This check is advisory. What the device reports can differ from what actually resolves names, for example with Android Private DNS, iOS DNS profiles, a VPN, or DNS servers the user set by hand.

### Canonical IP text

All returned IPs use one format on both platforms: IPv4 as a dotted quad; IPv6 lowercase and compressed exactly like `inet_ntop` (the longest run of zero groups becomes `::`); no zone suffix; IPv4-mapped IPv6 (`::ffff:a.b.c.d`) shown as plain IPv4.

### Errors

Functions reject only for invalid arguments (and, on iOS, if the resolver configuration can't be read). **Branch on `error.code`, never on `error.message`**: the message text differs between iOS and Android.

```typescript
import { nsLookupWithCustomDns, NslookupErrorCode } from "expo-nslookup";

try {
  await nsLookupWithCustomDns(domain, servers);
} catch (e: any) {
  if (e.code === NslookupErrorCode.InvalidDnsServer) {
    // fix the server list
  }
}
```

| Code | When |
|---|---|
| `ERR_INVALID_DOMAIN` | `domain` breaks the rules above |
| `ERR_INVALID_DNS_SERVER` | `dnsServers`/`expectedServers` is empty, has more than 16 entries, or contains something that isn't an IP literal |
| `ERR_INVALID_TIMEOUT` | `timeoutMs` is not between 100 and 60000 |
| `ERR_DNS_CONFIG_UNAVAILABLE` | iOS only: the system resolver configuration could not be read |

Arguments are checked in order (domain, servers, timeout), so a call with several bad arguments rejects with the same code on both platforms.

## Platform notes

- **Android** permissions `INTERNET` and `ACCESS_NETWORK_STATE` are added to your app automatically. "Offline" means there is no active network; a network without internet access (for example a private APN) still counts as online.
- **iOS** reports at most 3 device DNS servers (the resolver's `MAXNS`).
- **iOS Local Network permission:** if one of your DNS servers is on the same subnet as the device, iOS asks the user for Local Network access, and you must add `NSLocalNetworkUsageDescription` to your Info.plist. If the user denies access, that server is treated as unreachable.
- **Closed ports:** if a server's IP is reachable but nothing listens on port 53, Android learns this from the ICMP reply and stops waiting early. iOS (Network.framework) doesn't report it and waits for the timeout. The result is `timeout` on both.
- **Web** is not supported.

## Requirements

- Expo SDK 53 or higher
- React Native 0.79 or higher
- iOS 15.1 or higher
- Android API 24 (Android 7.0) or higher

## Migrating from 0.2.x

0.3.0 is a breaking release.

- **"Public" is no longer an error.** Replace `try { await lookup… ; private } catch { public }` with a check on `result.isPrivate`. Treat any rejection as "unknown" (for example, assume public).
- **New signature:** `nsLookupWithCustomDns(domain, dnsServers, { timeoutMs })`. The timeout is now in **milliseconds** in an options object, instead of seconds as a positional argument.
- **Removed:** `lookup()`, `advanceLookup()` and the default export. They called a native function that no longer existed.
- **The native function was renamed** (`nsLookUpWithCustomDnsServer` → `nsLookupWithCustomDns`). That way an old JavaScript bundle running on the new native code fails loudly instead of reading every network as private. If you ship JavaScript over the air, **bump your app's `runtimeVersion`** with this upgrade.

## Contributing

Contributions are welcome! Please open an issue or a pull request.

## License

MIT

## Author

**Bilal Serwan**: [@bilalSerwan](https://github.com/bilalSerwan)

## Links

- [GitHub Repository](https://github.com/bilalSerwan/expo-nslookup)
- [Issue Tracker](https://github.com/bilalSerwan/expo-nslookup/issues)
- [npm Package](https://www.npmjs.com/package/expo-nslookup)
