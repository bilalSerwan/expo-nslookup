// swift-tools-version:6.0
// Only for unit-testing the Expo-free iOS code on macOS (`swift test`). The app build uses ios/ExpoNslookup.podspec.
import PackageDescription

let package = Package(
  name: "ExpoNslookupCore",
  platforms: [.macOS(.v12), .iOS("15.1")],
  targets: [
    .target(name: "NslookupCore", path: "ios/Core"),
    .testTarget(name: "NslookupCoreTests", dependencies: ["NslookupCore"], path: "ios/CoreTests"),
  ]
)
