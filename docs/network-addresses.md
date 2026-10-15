# Network addresses

Network shows compact Local IP and Public IP rows in the dashboard and menu dropdown.
Expand Local IP for all usable running interfaces, full copyable IPv6 addresses and
public-IP observation time. IPv6 values wrap instead of being clipped.

Local addresses come from `getifaddrs` (`IFF_UP`, `IFF_RUNNING`, non-loopback).
SystemConfiguration `State:/Network/Global/IPv4` and `IPv6` `PrimaryInterface` identify
the default-route interface for each family. VPN interfaces participate in address
selection even though the existing throughput totals exclude tunnels to avoid double
counting. Default-route addresses come first, IPv4 before IPv6; other usable addresses
remain in details. No default-route address means the headline is unknown, not a claim
that the Internet is reachable. Loopback, unspecified, multicast and link-local-only
addresses are excluded. Addresses and route properties are read on each network tick;
they are not carried forward across failures or disconnects.

Public IP is **off by default**. The Settings toggle explicitly names **ipify** and says
that enabling it contacts `https://api64.ipify.org?format=json`. ipify sees the source
public IP of that HTTPS connection. This is a requested exception to the project's
usual no-outbound-requests rule; the local-address feature needs no external service.
It requires maintainer acceptance of that exception before merge.

Public lookup runs asynchronously, separately from metric sampling. Stable routes
refresh every 10 minutes, including retries after a failed attempt (no immediate retry loop);
changed routes can refresh after at least 60 seconds since
the last attempt. A disabled option, missing route, lost network demand, changed
local route/address set or failed refresh clears the old value. Late results from an
old route are discarded. A five-second timeout, no redirect following, ephemeral
session without cookies/cache, bounded JSON decoding and literal IPv4/IPv6 validation
limit the request. There is at most one in-flight lookup and no separate polling timer:
the existing sampling tick checks the monotonic-clock deadline, and UI rendering never
starts requests. With lookup disabled or no Network demand, route fingerprint work is skipped.
No geolocation or network-provider metadata is requested.

The value is the exit address **seen by ipify**, not an assertion about every app's
route. A VPN may provide it; split tunneling, proxies and separate IPv4/IPv6 routes
can have different exits. Offline/error values show “—”; disabled lookup shows “Off”.
Full addresses and check time are in details. Requests and addresses are not logged.

New NetworkSample fields are optional. Older recordings and remote agents show unknown
addresses; Fleet wire fields are unchanged. New `.ssrec` recordings retain observed
addresses locally, like other snapshot fields. CSV columns are unchanged. Treat an
exported recording as containing these addresses.

Tests and public screenshots use documentation addresses (192.0.2.0/24,
198.51.100.0/24 and 2001:db8::/32). No real public lookup is needed to test decoding,
refresh policy, route invalidation or layout.
