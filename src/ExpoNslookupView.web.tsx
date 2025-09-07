import * as React from 'react';

import { ExpoNslookupViewProps } from './ExpoNslookup.types';

export default function ExpoNslookupView(props: ExpoNslookupViewProps) {
  return (
    <div>
      <iframe
        style={{ flex: 1 }}
        src={props.url}
        onLoad={() => props.onLoad({ nativeEvent: { url: props.url } })}
      />
    </div>
  );
}
