# expo-nslookup

[![npm version](https://img.shields.io/npm/v/expo-nslookup.svg)](https://www.npmjs.com/package/expo-nslookup)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A native DNS lookup module for Expo and React Native applications. Perform fast, native DNS lookups to check domain availability and DNS resolution with configurable timeout options.

## Features

- 🚀 **Native Performance**: Leverages platform-native DNS resolution (iOS and Android)
- ⚡ **Fast Lookups**: Optimized for speed with configurable timeout options
- 🎯 **Simple API**: Easy-to-use Promise-based interface
- 📱 **Cross-Platform**: Works seamlessly on iOS and Android
- 🔧 **TypeScript Support**: Fully typed for better development experience
- ⏱️ **Configurable Timeout**: Set custom timeout values for DNS queries

## Installation

### Prerequisites

Ensure you have [installed and configured the `expo` package](https://docs.expo.dev/bare/installing-expo-modules/) in your project.

### Install the package

```bash
npm install expo-nslookup
```

or with yarn:

```bash
yarn add expo-nslookup
```

### Platform-Specific Setup

#### iOS

Run the following command after installing the package:

```bash
npx pod-install
```

#### Android

No additional configuration required. The module will be automatically linked.

## Usage

### Basic Example

```typescript
import * as ExpoNslookup from "expo-nslookup";

// Simple domain lookup
const checkDomain = async () => {
  try {
    const isResolvable = await ExpoNslookup.lookup("example.com");
    console.log("Domain resolves:", isResolvable); // true or false
  } catch (error) {
    console.error("Lookup failed:", error);
  }
};
```

### Advanced Usage with Options

```typescript
import ExpoNslookupModule from "expo-nslookup";

// Lookup with custom timeout
const advancedLookup = async () => {
  try {
    const result = await ExpoNslookupModule.lookup("example.com", {
      timeout: 5.0, // 5 seconds timeout
    });

    console.log("Success:", result.success);
    console.log("Domain:", result.domain);
    console.log("Has Addresses:", result.hasAddresses);
  } catch (error) {
    console.error("Lookup failed:", error);
  }
};
```

### Complete Example

```typescript
import * as ExpoNslookup from 'expo-nslookup';
import { Button, Text, TextInput, View } from 'react-native';
import { useState } from 'react';

export default function App() {
  const [domain, setDomain] = useState('google.com');
  const [result, setResult] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const performLookup = async () => {
    try {
      setLoading(true);
      const isResolvable = await ExpoNslookup.lookup(domain.trim());
      setResult(isResolvable ? '✅ Domain resolves' : '❌ Domain not found');
    } catch (error: any) {
      setResult(`⚠️ Error: ${error.message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <View>
      <TextInput
        value={domain}
        onChangeText={setDomain}
        placeholder="Enter domain name"
        autoCapitalize="none"
        autoCorrect={false}
      />
      <Button
        title={loading ? 'Looking up...' : 'Check Domain'}
        onPress={performLookup}
        disabled={loading}
      />
      {result && <Text>{result}</Text>}
    </View>
  );
}
```

## API Reference

### `lookup(domain: string): Promise<boolean>`

Performs a DNS lookup for the specified domain.

**Parameters:**

- `domain` (string): The domain name to lookup (e.g., "example.com")

**Returns:**

- `Promise<boolean>`: Returns `true` if the domain resolves, `false` otherwise

**Example:**

```typescript
const exists = await ExpoNslookup.lookup("github.com");
```

---

### `ExpoNslookupModule.lookup(domain: string, options?: DNSLookupOptions): Promise<DNSLookupResult>`

Advanced lookup method with configurable options and detailed results.

**Parameters:**

- `domain` (string): The domain name to lookup
- `options` (optional): Configuration options
  - `timeout` (number): Timeout in seconds (default: 1.0)

**Returns:**

- `Promise<DNSLookupResult>`: An object containing:
  - `success` (boolean): Whether the lookup was successful
  - `domain` (string): The queried domain
  - `hasAddresses` (boolean): Whether DNS addresses were found

**Example:**

```typescript
const result = await ExpoNslookupModule.lookup("example.com", {
  timeout: 3.0,
});
```

## TypeScript Types

```typescript
interface DNSLookupResult {
  success: boolean;
  domain: string;
  hasAddresses: boolean;
}

interface DNSLookupOptions {
  timeout?: number; // Timeout in seconds (default: 1.0)
}
```

## Use Cases

- **Network Diagnostics**: Check if a domain is reachable before making requests
- **Domain Validation**: Verify domain existence in forms and inputs
- **Connectivity Testing**: Test DNS resolution as part of connectivity checks
- **Custom DNS Monitoring**: Build monitoring tools for domain availability
- **Offline Detection**: Determine if DNS resolution is working

## Troubleshooting

### iOS Issues

If you encounter build issues on iOS:

1. Run `npx pod-install` again
2. Clean the build folder in Xcode
3. Rebuild the project

### Android Issues

If you encounter build issues on Android:

1. Clean the build: `cd android && ./gradlew clean`
2. Rebuild the project

## Requirements

- Expo SDK 53 or higher
- React Native 0.79.1 or higher
- iOS 13.0 or higher
- Android API level 21 or higher

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

**Bilal Serwan**

- GitHub: [@bilalSerwan](https://github.com/bilalSerwan)
- Email: ensw02121@student.su.edu.krd

## Links

- [GitHub Repository](https://github.com/bilalSerwan/expo-nslookup)
- [Issue Tracker](https://github.com/bilalSerwan/expo-nslookup/issues)
- [npm Package](https://www.npmjs.com/package/expo-nslookup)

---

Made with ❤️ by [Bilal Serwan](https://github.com/bilalSerwan)
