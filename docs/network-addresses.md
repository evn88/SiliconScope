# Local network addresses

Network's existing interface rows show that interface's local address, associated by
BSD name (for example en0), in both the dashboard and menu dropdown. Expand a row
for its full copyable IPv4/IPv6 addresses and throughput. Long addresses are shortened
only in collapsed rows and wrap in details. More addresses includes interfaces not in
the two physical throughput rows, including VPN tunnels. No address is selected from
another interface merely because it carries a default route.

Addresses come from the network sampler's existing getifaddrs walk, using up/running,
non-loopback interfaces. Loopback, unspecified, multicast and link-local-only
addresses are excluded. The same walk supplies physical byte counters; tunnels stay
excluded from throughput totals to avoid double counting. One SystemConfiguration
store is retained per sampler; primary IPv4/IPv6 interface names are refreshed on
the existing five-second cadence. There is no extra timer or external request.
Device/network changes may take up to that cadence to change default-route labels;
addresses themselves are read on each demanded network sample.

Views only read snapshot data and never query live interfaces. Older recordings and
remote frames without localAddresses show unknown (—); an empty list means none
reported. Address scan failure returns unknown. Old experimental public-IP recording
fields are ignored and not reencoded. Fleet wire fields and CSV columns are unchanged;
new recordings retain observed local addresses and should be treated accordingly.

No public-IP model, service, store or setting remains. Public screenshots and fixtures
use documentation addresses only. No runtime CPU or energy improvement is claimed;
the duplicate getifaddrs walk and per-tick SystemConfiguration store creation were
removed by sharing the existing sampler path.
