import * as ExpoNslookup from 'expo-nslookup';
import { Button, SafeAreaView, ScrollView, Text, View, TextInput } from 'react-native';
import { useState } from 'react';

export default function App() {
  const [result, setResult] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [domain, setDomain] = useState('s-fl-auth.newrozholdings.com');

  const onLookup = async () => {
    try {
      setLoading(true);
      const ok = await ExpoNslookup.lookup(domain.trim());
      setResult(ok ? 'true' : 'false');
    } catch (e: any) { 
      const message = e?.message ?? (typeof e === 'string' ? e : JSON.stringify(e))
      setResult(`error: ${message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.container}>
        <Text style={styles.header}>Module API Example</Text>
        <Text> {ExpoNslookup.default.hello()} </Text>
        <View style={styles.group}>
          <Text style={styles.groupHeader}>DNS Lookup</Text>
          <TextInput
            style={styles.input}
            placeholder="Enter domain"
            value={domain}
            autoCapitalize="none"
            autoCorrect={false}
            onChangeText={setDomain}
            editable={!loading}
            
          />
          <Button title={loading ? 'Looking up…' : 'Lookup'} onPress={onLookup} disabled={loading} />
          <Text style={{ marginTop: 10 }}>Result: {result ?? '-'}</Text>
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
    backgroundColor: '#fff',
    borderRadius: 10,
    padding: 20,
  },
  input: {
    borderWidth: 1,
    borderColor: '#ccc',
    padding: 10,
    borderRadius: 6,
    marginBottom: 10,
    backgroundColor: '#fff',
  },
  container: {
    flex: 1,
    backgroundColor: '#eee',
  },
  view: {
    flex: 1,
    height: 200,
  },
};
