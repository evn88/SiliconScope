//
//  File:      ssd_smart.h
//  Created:   2026-10-15
//  Updated:   2026-10-15
//  Developer: SiliconScope contributors
//  Overview:  Read-only macOS NVMe SMART log access.
//  Notes:     Private ABI stays in CIOReport. No enable, test or write commands.
//
#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <stdbool.h>
bool sscope_nvme_smart(io_service_t service, uint8_t *log);
