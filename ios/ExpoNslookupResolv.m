#import "ExpoNslookupResolv.h"

#include <netinet/in.h>
#include <resolv.h>
#include <string.h>

NSArray<NSData *> *ExpoNslookupReadResolverAddresses(void) {
  // fresh local state every call, never the global _res
  struct __res_state state;
  memset(&state, 0, sizeof(state));
  if (res_ninit(&state) != 0) {
    return nil;
  }

  union res_sockaddr_union unions[MAXNS];
  memset(unions, 0, sizeof(unions));
  int found = res_getservers(&state, unions, MAXNS);
  res_ndestroy(&state);

  NSMutableArray<NSData *> *addresses = [NSMutableArray array];
  for (int i = 0; i < found && i < MAXNS; i++) {
    if (unions[i].sin.sin_family == AF_INET) {
      [addresses addObject:[NSData dataWithBytes:&unions[i].sin.sin_addr length:sizeof(struct in_addr)]];
    } else if (unions[i].sin6.sin6_family == AF_INET6) {
      [addresses addObject:[NSData dataWithBytes:&unions[i].sin6.sin6_addr length:sizeof(struct in6_addr)]];
    }
  }
  return addresses;
}
