# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`expo-nslookup` is an Expo native module (Expo Modules API, SDK 53) that does DNS lookups natively on iOS and Android. One native module, registered as `ExpoNslookup` on both platforms (see `expo-module.config.json`). The repo root is the library. `example/` is a separate Expo app that consumes it.

**Why it exists:** a telecommunications company in Iraq (Kurdistan Region) built it for its own app. The app needs to know whether the user is connected to the company's network (private) or to some other network (public). The main entry point is `nsLookupWithCustomDns`. The app passes in the company's own DNS server IPs and an internal domain. If one of those servers answers with A records, the device is on the company network.

The result is never an error for "public": the call resolves with `isPrivate` plus `reason` (`resolved` | `notFound` | `timeout` | `offline`), and only invalid arguments reject. On a public network the company servers usually don't answer, so the typical public outcome is `timeout` after the full `timeoutMs`; the timeout therefore sets how long the check takes there. Changes to timeouts, the resend schedule, the response classification or the reasons change how the app classifies networks.

## Minimum supported versions

- **iOS 15.1** (podspec `platforms`). This is the floor for Expo SDK 53 / React Native 0.79; nothing lower builds.
- **Android API 24** (`minSdk`). This is the React Native 0.79 floor; no host app can run below it.

Any API newer than these floors needs an availability guard: `if #available(iOS 16, *)` on iOS, `Build.VERSION.SDK_INT` on Android. APIs that are easy to reach for by accident:
- **iOS 16+:** `OSAllocatedUnfairLock`, `ContinuousClock`, `Task.sleep(for:)`. Use `NSLock` or a serial `DispatchQueue`, `DispatchTime`, and `Task.sleep(nanoseconds:)` instead.
- **Android API 29+:** `InetAddresses.parseNumericAddress`.

## Commands

Library (repo root). The scripts wrap `expo-module-scripts`:

- `npm run build`: runs `tsc` from `src/` into `build/`, which is gitignored but is the published entry point (`main: build/index.js`). In an interactive terminal it **runs in watch mode**. Use `CI=1 npm run build` for a one-shot build.
- `npm run lint`: ESLint 9 with the flat `eslint.config.js` from `expo-module-scripts` (universe/native rules). It lints `src/` only.
- `prepare`, which `npm pack`/`npm publish` run automatically, calls `expo-module configure`. That recreates `.eslintrc.js` and `tsconfig.json` from the `expo-module-scripts` templates and overwrites any file marked `@generated` (`eslint.config.js`, `babel.config.js`). Don't hand-edit those files; remove the `@generated` line first if a change must stick.
- `.npmignore` replaces `.gitignore` for publishing, so anything that must not ship (local Gradle/IDE state, `CLAUDE.md`, test-only files) has to be listed there. Check with `npm pack --dry-run` before publishing.
- `npm test`: Jest through `expo-module test` (preset `expo-module-scripts`, so every test runs in four projects: iOS, Android, Web, Node). It also watches in a TTY (`CI=1` turns that off). Run one file with `CI=1 npx jest src/__tests__/index.test.ts`. Tests live in `src/__tests__/`, which `tsconfig.json` and `.npmignore` exclude.
- `npm run clean`: removes `build/`.
- `npm run open:ios` / `npm run open:android`: open the example's native projects in Xcode or Android Studio.

Example app (`cd example`):

- `npx expo run:ios` / `npx expo run:android`: build and run against the local module. Native changes (Swift/ObjC/Kotlin, podspec, manifest) need a native rebuild, not just a Metro reload. After adding iOS source files, run `npx pod-install` (the podspec globs `ios/**/*.{h,m,mm,swift,...}`).
- The example resolves `expo-nslookup` to `..` through `metro.config.js` (`extraNodeModules`, `watchFolders`) and `package.json` (`expo.autolinking.nativeModulesDir: ".."`). It also blocks `../node_modules/react{,-native}` so only one copy of React is bundled.
- **`example/ios` and `example/android` are generated.** Never edit them by hand: `npx expo prebuild --clean` (the normal workflow here) rewrites them. Native project changes go in `example/app.json` or in a config plugin under `example/plugins/`, registered in `app.json` `plugins`. After changing either, run `npx expo prebuild --clean`.
- `example/plugins/withFmtCxx17.js` compiles the `fmt` pod as C++17. Without it, React Native 0.79's fmt 11.0.2 does not compile with Xcode 26 ("call to consteval function … is not a constant expression").
- The example app has two sections: "Compare device DNS" (`compareDnsServers`, with a "Use device DNS" button that fills in `getDnsServers()`) and "Lookup with custom DNS" (`nsLookupWithCustomDns`, with presets for the matrix below). It holds no company domain or DNS IPs; type them in.

## Verification

Run all of these after any change. Native changes must be checked on **both** platforms, because each platform has its own implementation of the same behaviour.

```bash
# JS: types, lint, Jest
npm run clean && CI=1 npm run build && npm run lint && CI=1 npm test

# Swift unit tests for ios/Core (repo root, macOS host; same inet_pton/inet_ntop and Network.framework as iOS)
swift test                                   # one suite: swift test --filter DnsResolverTests

# Android unit tests + full build (the module's Gradle project is :expo-nslookup)
cd example/android && ./gradlew :expo-nslookup:testDebugUnitTest :app:assembleDebug
# one class: ./gradlew :expo-nslookup:testDebugUnitTest --tests 'expo.modules.nslookup.DnsResolverTest'

# iOS build (prebuild --clean regenerates example/ios and runs pod install)
cd example && npx expo prebuild --clean --platform ios && cd ..
xcodebuild -workspace example/ios/exponslookupexample.xcworkspace -scheme exponslookupexample \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Then run the example app on a device or simulator for each platform (`cd example && npx expo run:ios` / `npx expo run:android`) and check this matrix. Both platforms must give the same result:

| Call | Expected |
|---|---|
| `example.com` via `['1.1.1.1']` | `reason: 'resolved'` |
| `nonexistent.invalid` via `['1.1.1.1']` | `'notFound'`, fast |
| via `['192.0.2.1']` (TEST-NET, never answers) | `'timeout'`, after about `timeoutMs` |
| via `['192.0.2.1', '1.1.1.1']` | `'resolved'`, fast |
| airplane mode | `'offline'`, in under 100 ms |
| `''`, `a..b`, servers `['example.com']` or `[]`, `timeoutMs: 0` | the same error `code` on both platforms |
| `compareDnsServers(await getDnsServers())` ("Use device DNS", then "Compare") | `isMatch: true` |

The real business check comes last: the company's internal domain and DNS IPs give `'resolved'` on the company network, and `'notFound'` or `'timeout'` on a public network.

**Error handling rule:** JS code must branch on `error.code`, never on `error.message`. The message text differs by platform: iOS wraps the error in a `FunctionCallException` and Android in a `DecoratedException`. Codes are explicit strings set in native code; never rely on inferred codes, which change under Android minification.

Install dependencies with `npm ci` (root and `example/`); the committed `package-lock.json` files are authoritative. The root also has a Yarn Berry config (`.yarnrc.yml`), but a Yarn install skips the `jest`, `eslint` and `prettier` peer dependencies that `expo-module-scripts` needs, which breaks `npm test` and `npm run lint`.

## Architecture

Three native functions, the same on both platforms: `nsLookupWithCustomDns(domain, dnsServers, timeoutMs)`, `getDnsServers()`, `compareDnsServers(expectedServers)`. When you change the public API, keep `src/ExpoNslookup.types.ts`, `src/ExpoNslookupModule.ts`, `src/index.ts`, both native modules and the README in sync.

### JS layer (`src/`)

- `ExpoNslookup.types.ts`: the public types and `NslookupErrorCode`.
- `ExpoNslookupModule.ts`: the native interface (`requireNativeModule("ExpoNslookup")`).
- `index.ts`: the public functions. It only applies the default `timeoutMs` (5000) and turns a missing `server` into `null` (iOS drops nil optional fields). All validation is native. No default export.

### Native layout: pure core plus a thin Expo layer

Each platform has an Expo-free core that holds all logic and is unit tested, plus a thin Expo module on top:

| | iOS | Android (`android/src/main/java/expo/modules/nslookup/`) |
|---|---|---|
| IP literal parsing and canonical text | `ios/Core/IPAddressText.swift` | `IpAddressText.kt` |
| DNS wire format (query, classification) | `ios/Core/DnsMessage.swift` | `DnsMessage.kt` |
| Argument validation, error codes | `ios/Core/LookupRequest.swift` | `LookupRequest.kt` |
| One UDP exchange per server | `ios/Core/DnsUdpExchange.swift` | `DnsResolver.kt` (`queryServer`/`exchange`) |
| Parallel aggregation | `ios/Core/DnsResolver.swift` | `DnsResolver.kt` (`resolve`) |
| Offline check | `ios/Core/NetworkPath.swift` (`NWPathMonitor`) | `DnsServers.kt` (`activeNetwork == null`) |
| Device DNS servers | `ios/ExpoNslookupResolv.{h,m}` (libresolv) | `DnsServers.kt` (`LinkProperties`) |
| Expo records, enum, exceptions | `ios/NslookupTypes.swift` | `NslookupTypes.kt` |
| Module definition | `ios/ExpoNslookupModule.swift` | `ExpoNslookupModule.kt` |

`ios/Core/` is compiled into the pod and also into the SwiftPM target `NslookupCore` (root `Package.swift`, tests in `ios/CoreTests/`, excluded from the pod and from npm). The SwiftPM package uses Swift 6 language mode, so `swift test` also checks data-race safety. The pod builds in Swift 5 mode.

### Protocol rules (mirrored on both platforms)

The rules are written out in the header comment of `DnsMessage.swift`/`DnsMessage.kt` and in the doc comments of the resolvers. A change on one platform needs the same change on the other, plus matching test cases in both suites (the suites share case names and vectors). In short:
- **Validation**, in argument order (domain, servers, timeout), so both platforms reject with the same code: ASCII domain of up to 253 characters with labels of 1–63 characters; 1–16 strict IP literals, never hostnames; `timeoutMs` 100–60000.
- **Strict IP parsing.** iOS uses `inet_pton` plus a pre-check, because Apple's `inet_pton` accepts leading-zero octets (`010.0.0.1`) and 5-digit groups (`00001::`). Android reimplements ISC `inet_pton`/`inet_ntop` in Kotlin, with no `InetAddress.getByName`, which would trigger a DNS lookup for a hostname.
- **Per server:** one connected UDP socket; the same query is resent at 0/500/1500/3500 ms until the deadline, and a late answer counts. The response must match the ID, QR=1, OPCODE 0 and the question. SERVFAIL, or TC/malformed without an address, is transient; any other non-zero RCODE, or no A record, is negative and ends that server.
- **Aggregate:** offline → `offline` with nothing sent; the first A answer → `resolved`, which cancels the rest; else any negative → `notFound`; else `timeout`.

Concurrency: iOS confines each exchange's state to one serial `DispatchQueue`, with a single `finish(_:)` that resumes the continuation exactly once (cancellation can race the start). Timers are `DispatchSourceTimer`s with a 5 ms leeway, because `asyncAfter` coalescing stretched a 3 s deadline by about 200 ms. Android uses `AsyncFunction … Coroutine`, structured concurrency (no `GlobalScope`), and a "closer" coroutine that closes the socket on cancellation, because `DatagramSocket.receive` ignores interrupts.

**Known platform difference:** a server whose IP is reachable but whose port 53 is closed ends early on Android (ICMP port unreachable), but runs to the deadline on iOS, because Network.framework doesn't surface ICMP for UDP. Both report `timeout`.

### Results and errors

- Results are Expo `Record`s (`LookupResult`, `DnsServerComparison`) with an `Enumerable` `LookupReason`, not dictionaries.
- Errors carry explicit codes (`ERR_INVALID_DOMAIN`, `ERR_INVALID_DNS_SERVER`, `ERR_INVALID_TIMEOUT`, and on iOS `ERR_DNS_CONFIG_UNAVAILABLE`). iOS uses `Exception(name:description:code:)`, Android a `CodedException` with an explicit code.
- The pure cores throw their own `InvalidArgumentError`/`InvalidArgumentException`, and the module layer converts it with `rejectingInvalidArguments`.

### Device DNS servers

- iOS reads `res_getservers` on a fresh `res_state` (at most `MAXNS` = 3), returns raw bytes, and Swift formats them with `IPAddressText`. The podspec links `libresolv`.
- Android reads `LinkProperties.dnsServers` of `activeNetwork`.
- The library manifest declares `INTERNET` and `ACCESS_NETWORK_STATE`; both merge into host apps.

### Versioning

- `package.json` is the single source of the version: the podspec and `android/build.gradle` both read it.
- Android uses the SDK 53 `expo-module-gradle-plugin` form with an explicit `minSdkVersion 24`.
- The native function name doubles as a compatibility guard: it was renamed from `nsLookUpWithCustomDnsServer` when its contract changed, so an old JS bundle fails instead of misreading results. Do the same for any future contract change, and tell app owners to bump `runtimeVersion`.
