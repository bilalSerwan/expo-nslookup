import { advanceLookup, lookup, nsLookupWithCustomDns } from "expo-nslookup";
import {
  Button,
  SafeAreaView,
  ScrollView,
  Text,
  View,
  TextInput,
} from "react-native";
import { useState } from "react";

export default function App() {
  const [result, setResult] = useState<string | null>(null);
  const [defaultResult, setDefaultResult] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [domain, setDomain] = useState("s-fl-auth.newrozholdings.com");
  const [timeout, setTimeout] = useState("5");
  const [customDns, setCustomDns] = useState("8.8.8.8");
  const [customResult, setCustomResult] = useState<string | null>(null);

  const onLookup = async () => {
    try {
      setLoading(true);
      const timeoutValue = parseFloat(timeout) || 5;

      // Run both lookups in parallel
      const [lookupResult, simpleExists] = await Promise.all([
        advanceLookup(domain.trim(), timeoutValue),
        lookup(domain.trim()),
      ]);

      // Format the advanced result in a user-friendly way
      const formattedResult = `Domain: ${lookupResult.domain}
Success: ${lookupResult.success ? "Yes" : "No"}
Has Addresses: ${lookupResult.hasAddresses ? "Yes" : "No"}
Status: ${
        lookupResult.success && lookupResult.hasAddresses
          ? "✅ DNS lookup successful"
          : "❌ DNS lookup failed"
      }`;

      setResult(formattedResult);
      setDefaultResult(
        simpleExists
          ? "✅ Default lookup: resolves"
          : "❌ Default lookup: not found"
      );
    } catch (e: any) {
      console.error(e);
      const message =
        e?.message ?? (typeof e === "string" ? e : JSON.stringify(e));
      setResult(`❌ Error: ${message}`);
      setDefaultResult(null);
    } finally {
      setLoading(false);
    }
  };

  const onCustomLookup = async () => {
    try {
      setLoading(true);
      const timeoutValue = parseFloat(timeout) || 5;
      const result = await nsLookupWithCustomDns(
        domain.trim(),
        [customDns.trim()],
        timeoutValue
      );

      const formatted = `Domain: ${result.domain}\nServer: ${
        result.server
      }\nIs Private: ${result.isPrivate ? "Yes" : "No"}\nIPs: ${result.ip.join(
        ", "
      )}`;
      setCustomResult(formatted);
    } catch (e: any) {
      console.log(e);
      const message =
        e?.message ?? (typeof e === "string" ? e : JSON.stringify(e));
      setCustomResult(`❌ Error: ${message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.container}>
        <Text style={styles.header}>Module API Example</Text>
        <View style={styles.group}>
          <Text style={styles.groupHeader}>Advanced DNS Lookup</Text>
          <TextInput
            style={styles.input}
            placeholder="Enter domain"
            value={domain}
            autoCapitalize="none"
            autoCorrect={false}
            onChangeText={setDomain}
            editable={!loading}
          />
          <TextInput
            style={styles.input}
            placeholder="Timeout (seconds)"
            value={timeout}
            keyboardType="numeric"
            onChangeText={setTimeout}
            editable={!loading}
          />
          <Button
            title={loading ? "Looking up…" : "Advanced Lookup"}
            onPress={onLookup}
            disabled={loading}
          />
          <Text style={styles.resultLabel}>Advanced Result:</Text>
          <Text style={styles.resultText}>{result ?? "-"}</Text>

          <Text style={styles.resultLabel}>Default Mobile Lookup:</Text>
          <Text style={styles.resultText}>{defaultResult ?? "-"}</Text>

          <View style={{ marginTop: 20 }}>
            <Text style={styles.groupHeader}>Custom DNS Lookup</Text>
            <TextInput
              style={styles.input}
              placeholder="Custom DNS server (comma separated)"
              value={customDns}
              autoCapitalize="none"
              autoCorrect={false}
              onChangeText={setCustomDns}
              editable={!loading}
            />
            <Button
              title={loading ? "Looking up…" : "Lookup with Custom DNS"}
              onPress={onCustomLookup}
              disabled={loading}
            />
            <Text style={styles.resultLabel}>Custom DNS Result:</Text>
            <Text style={styles.resultText}>{customResult ?? "-"}</Text>
          </View>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = {
  header: {
    fontSize: 30,
    margin: 20,
  },
  groupHeader: {
    fontSize: 20,
    marginBottom: 20,
  },
  group: {
    margin: 20,
    backgroundColor: "#fff",
    borderRadius: 10,
    padding: 20,
  },
  input: {
    borderWidth: 1,
    borderColor: "#ccc",
    padding: 10,
    borderRadius: 6,
    marginBottom: 10,
    backgroundColor: "#fff",
  },
  resultLabel: {
    fontSize: 16,
    fontWeight: "bold" as const,
    marginTop: 15,
    marginBottom: 5,
  },
  resultText: {
    fontSize: 14,
    fontFamily: "monospace",
    backgroundColor: "#f5f5f5",
    padding: 12,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: "#ddd",
    lineHeight: 20,
  },
  container: {
    flex: 1,
    backgroundColor: "#eee",
  },
  view: {
    flex: 1,
    height: 200,
  },
};
