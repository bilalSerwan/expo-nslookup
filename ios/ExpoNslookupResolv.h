#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Reads the resolver's DNS server addresses via libresolv into a fresh local res_state.
/// Each element holds the raw address bytes: 4 for IPv4, 16 for IPv6. Swift formats them, so
/// getDnsServers and compareDnsServers share one formatter.
/// Returns nil if res_ninit fails. At most MAXNS (3) servers are reported.
NSArray<NSData *> *_Nullable ExpoNslookupReadResolverAddresses(void);

NS_ASSUME_NONNULL_END
