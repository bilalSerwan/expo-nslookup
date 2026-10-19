import {
  compareDnsServers,
  CustomDnsLookupResult,
  DnsServerComparison,
  getDnsServers,
  nsLookupWithCustomDns,
} from "expo-nslookup";
import { useCallback, useState } from "react";
import {
  Button,
  SafeAreaView,
  ScrollView,
  Text,
  TextInput,
  View,
} from "react-native";

interface Failure {
  code: string;
  message: string;
}

const toFailure = (e: any): Failure => ({
  code: e?.code ?? "?",
  message: e?.message ?? String(e),
});

const splitList = (text: string) =>
  text
    .split(/[\s,]+/)
    .map((s) => s.trim())
    .filter(Boolean);

// Test cases from the verification matrix in CLAUDE.md
const PRESETS: {
  title: string;
  domain: string;
  servers: string;
  timeoutMs: string;
}[] = [
  {
    title: "Public resolver",
    domain: "example.com",
    servers: "1.1.1.1",
    timeoutMs: "5000",
  },
  {
    title: "NXDOMAIN",
    domain: "nonexistent.invalid",
    servers: "1.1.1.1",
    timeoutMs: "5000",
  },
  {
    title: "Silent server",
    domain: "example.com",
    servers: "192.0.2.1",
    timeoutMs: "2000",
  },
  {
    title: "Silent + public",
    domain: "example.com",
    servers: "192.0.2.1, 1.1.1.1",
    timeoutMs: "5000",
  },
];

export default function App() {
  const [expected, setExpected] = useState("");
  const [comparison, setComparison] = useState<{
    result?: DnsServerComparison;
    failure?: Failure;
  } | null>(null);

  const [domain, setDomain] = useState(PRESETS[0].domain);
  const [servers, setServers] = useState(PRESETS[0].servers);
  const [timeoutMs, setTimeoutMs] = useState(PRESETS[0].timeoutMs);
  const [lookup, setLookup] = useState<{
    result?: CustomDnsLookupResult;
    failure?: Failure;
    jsMs: number;
  } | null>(null);
  const [lookingUp, setLookingUp] = useState(false);

  const fillDeviceServers = useCallback(async () => {
    try {
      setExpected((await getDnsServers()).join(", "));
    } catch (e) {
      setComparison({ failure: toFailure(e) });
    }
  }, []);

  const runCompare = useCallback(async () => {
    try {
      setComparison({ result: await compareDnsServers(splitList(expected)) });
    } catch (e) {
      setComparison({ failure: toFailure(e) });
    }
  }, [expected]);

  const runLookup = useCallback(async () => {
    setLookingUp(true);
    const start = performance.now();
    try {
      const result = await nsLookupWithCustomDns(
        domain.trim(),
        splitList(servers),
        { timeoutMs: Number(timeoutMs) },
      );
      setLookup({ result, jsMs: performance.now() - start });
    } catch (e) {
      setLookup({ failure: toFailure(e), jsMs: performance.now() - start });
    } finally {
      setLookingUp(false);
    }
  }, [domain, servers, timeoutMs]);

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView keyboardShouldPersistTaps="handled">
        <Text style={styles.header}>expo-nslookup</Text>

        <View style={styles.group}>
          <Text style={styles.title}>Compare device DNS</Text>
          <Text style={styles.label}>
            Expected DNS servers (comma separated)
          </Text>
          <TextInput
            style={styles.input}
            value={expected}
            onChangeText={setExpected}
            placeholder="e.g. 1.1.1.1, 8.8.8.8"
            autoCapitalize="none"
            autoCorrect={false}
          />
          <View style={styles.presets}>
            <Button title="Use device DNS" onPress={fillDeviceServers} />
            <Button title="Compare" onPress={runCompare} />
          </View>
          {comparison?.result && (
            <>
              <Text
                style={[
                  styles.verdict,
                  { color: comparison.result.isMatch ? "#1b5e20" : "#b00020" },
                ]}
              >
                {comparison.result.isMatch ? "MATCH" : "NO MATCH"}
              </Text>
              <Text style={styles.mono}>
                {JSON.stringify(comparison.result, null, 2)}
              </Text>
            </>
          )}
          {comparison?.failure && (
            <Text style={styles.error}>
              {comparison.failure.code}: {comparison.failure.message}
            </Text>
          )}
        </View>

        <View style={styles.group}>
          <Text style={styles.title}>Lookup with custom DNS</Text>
          <View style={styles.presets}>
            {PRESETS.map((p) => (
              <Button
                key={p.title}
                title={p.title}
                onPress={() => {
                  setDomain(p.domain);
                  setServers(p.servers);
                  setTimeoutMs(p.timeoutMs);
                }}
              />
            ))}
          </View>
          <Text style={styles.label}>Domain</Text>
          <TextInput
            style={styles.input}
            value={domain}
            onChangeText={setDomain}
            autoCapitalize="none"
            autoCorrect={false}
          />
          <Text style={styles.label}>DNS servers (comma separated)</Text>
          <TextInput
            style={styles.input}
            value={servers}
            onChangeText={setServers}
            autoCapitalize="none"
            autoCorrect={false}
          />
          <Text style={styles.label}>Timeout (ms)</Text>
          <TextInput
            style={styles.input}
            value={timeoutMs}
            onChangeText={setTimeoutMs}
            keyboardType="number-pad"
          />
          <Button
            title={lookingUp ? "Looking up…" : "Look up"}
            onPress={runLookup}
            disabled={lookingUp}
          />
          {lookup?.result && (
            <>
              <Text
                style={[
                  styles.verdict,
                  { color: lookup.result.isPrivate ? "#1b5e20" : "#b00020" },
                ]}
              >
                {lookup.result.isPrivate ? "PRIVATE" : "PUBLIC"} ·{" "}
                {lookup.result.reason}
              </Text>
              <Text style={styles.mono}>
                {JSON.stringify(lookup.result, null, 2)}
              </Text>
            </>
          )}
          {lookup?.failure && (
            <Text style={styles.error}>
              {lookup.failure.code}: {lookup.failure.message}
            </Text>
          )}
          {lookup && (
            <Text style={styles.small}>
              JS round trip {lookup.jsMs.toFixed(0)} ms
            </Text>
          )}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = {
  container: { flex: 1, backgroundColor: "#eee" },
  header: { fontSize: 26, margin: 20 },
  group: {
    marginHorizontal: 20,
    marginBottom: 16,
    backgroundColor: "#fff",
    borderRadius: 10,
    padding: 16,
  },
  title: { fontSize: 18, fontWeight: "bold" as const, marginBottom: 8 },
  presets: { flexDirection: "row" as const, flexWrap: "wrap" as const, gap: 4 },
  label: {
    fontSize: 14,
    fontWeight: "bold" as const,
    marginTop: 14,
    marginBottom: 6,
  },
  input: {
    borderWidth: 1,
    borderColor: "#ccc",
    borderRadius: 6,
    padding: 8,
    marginBottom: 8,
    fontFamily: "monospace",
  },
  verdict: { fontSize: 20, fontWeight: "bold" as const, marginTop: 12 },
  mono: { fontSize: 13, fontFamily: "monospace", marginTop: 6 },
  error: { fontSize: 15, color: "#b00020", marginTop: 12 },
  small: { fontSize: 12, marginVertical: 6 },
};
