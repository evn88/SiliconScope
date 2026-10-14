# SSD metrics

The Disk card shows SSD totals below Used. The SSD menu dropdown shows totals above
Activity. Both surfaces show one SSD health/endurance line. Secondary SMART
values are collapsed under that line; nonzero warnings appear as readable text.

- **SSD since boot:** `IOBlockStorageDriver` Statistics `Bytes (Read)` and `Bytes
  (Write)` for physical devices whose Device Characteristics report `Medium Type =
  Solid State`, Protocol Characteristics report `Physical Interconnect Location =
  Internal`, and driver `IOMatchedAtBoot = true`. Apple initializes these counters
  to zero in `IOBlockStorageDriver::init`; the first app sample includes earlier
  traffic. This is host I/O, not NAND writes. There is no app-session accumulator.
- **Activity:** the existing per-second delta across all block storage drivers,
  including external disks. It deliberately has a broader scope than SSD totals.
- **SSD lifetime:** NVMe SMART health-log Data Units Read/Written at offsets 32/48,
  read through the macOS NVMe SMART plugin on each internal SSD. These are device
  lifetime host counters in units of 512,000 bytes, rounded up by the device. They
  are independent of OS boot counters and do not measure write amplification.
- **Health · endurance:** `max(0, 100 - Percentage Used)` (log byte 5). Percentage
  Used is a vendor estimate of consumed rated endurance, can exceed 100, and uses
  255 for more than 254. Remaining endurance is not a failure prediction. Neither
  zero critical warnings nor SMART pass status implies 100% health.
- **Temperature:** composite temperature (bytes 1–2, little-endian kelvin).
  Zero and 65535 are unavailable.
- **Spare:** Available Spare (byte 3); its threshold (byte 4) is in the expanded details.
- **Warnings:** Critical Warning bits (byte 0), displayed individually in plain English
  only when set. Unknown reserved bits show “Other device warning”.
- **Data integrity errors:** lifetime Media and Data Integrity Errors (offset 160),
  shown in expanded details. These are unrecovered media/ECC/CRC/LBA tag errors,
  not all OS read/write errors. No error counters are added together.

Sizes use decimal MB/GB/TB, as in the existing Disk card. An unavailable reading is
`—`; reported zero boot bytes, errors, warnings and spare remain real zeroes.
NVMe zero Data Units means not reported. 128-bit counters that cannot fit UInt64,
byte-conversion overflow and aggregation overflow are unavailable, never truncated.
Lifetime totals require every internal SSD to supply the corresponding counter;
SMART diagnostics are per device, without combining health percentages.

Boot totals become unavailable after an observed driver replacement/removal or
counter decrease and remain unavailable for that sampler's lifetime. Missing
statistics never become zero or replace the last known reset-detection baseline.
A reset that occurred before the app observed the driver cannot be detected; the
boot label relies on macOS's boot-match property and uninterrupted driver counters.
There is no reconstruction or persistence of missed I/O.

SMART is read at most once per 30 seconds while disk sampling is demanded, with an
immediate refresh on a device change. Cached readings are cleared on device changes
and replaced with unavailable on a failed refresh. Only SMARTReadData is called;
no SMART enable, self-test, write or subprocess commands are used. SATA, USB bridges
and devices without the NVMe plugin return unavailable SMART. Boot totals can still
be available on internal SATA SSDs. Fleet fields are unchanged; older recordings
lack the new optional DiskSample fields and decode as unknown.

## Source references

- [Apple IOBlockStorageDriver](https://github.com/apple-oss-distributions/IOStorageFamily/blob/main/IOBlockStorageDriver.cpp)
- [macOS NVMe SMART ABI](https://github.com/smartmontools/smartmontools/blob/master/smartmontools/os_darwin.h)
- [NVMe SMART log structure](https://github.com/smartmontools/smartmontools/blob/master/smartmontools/nvme.h)
- [Stats macOS disk reader](https://github.com/exelban/stats/blob/master/Modules/Disk/readers.swift)

The command `xcrun swift run sscope-cli --disk` prints these sources' readings without
initializing unrelated power and temperature samplers. No serial numbers are printed.
