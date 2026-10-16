//
//  File:      ssd_smart.c
//  Created:   2026-10-15
//  Updated:   2026-10-15
//  Developer: SiliconScope contributors
//  Overview:  Read the 512-byte NVMe SMART health log through Apple's plugin.
//  Notes:     ABI/UUIDs match NVMeSMARTLibExternal.h as documented by
//             smartmontools os_darwin.h and Stats Disk readers.swift.
//
#include "ssd_smart.h"
#include <IOKit/IOCFPlugIn.h>
#include <string.h>

typedef struct {
    IUNKNOWN_C_GUTS;
    UInt16 version;
    UInt16 revision;
    IOReturn (*SMARTReadData)(void *, void *);
} SSDNVMeInterface;

bool sscope_nvme_smart(io_service_t service, uint8_t *log) {
    CFUUIDRef client = CFUUIDGetConstantUUIDWithBytes(NULL,
        0xAA,0x0F,0xA6,0xF9,0xC2,0xD6,0x45,0x7F,0xB1,0x0B,0x59,0xA1,0x32,0x53,0x29,0x2F);
    CFUUIDRef interface = CFUUIDGetConstantUUIDWithBytes(NULL,
        0xCC,0xD1,0xDB,0x19,0xFD,0x9A,0x4D,0xAF,0xBF,0x95,0x12,0x45,0x4B,0x23,0x0A,0xB6);
    IOCFPlugInInterface **plugin = NULL;
    SSDNVMeInterface **smart = NULL;
    SInt32 score = 0;
    if (IOCreatePlugInInterfaceForService(service, client, kIOCFPlugInInterfaceID,
                                         &plugin, &score) != kIOReturnSuccess || !plugin) return false;
    HRESULT queried = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(interface), (LPVOID *)&smart);
    bool ok = false;
    if (queried == S_OK && smart) {
        memset(log, 0, 512);
        ok = (*smart)->SMARTReadData(smart, log) == kIOReturnSuccess;
        (*smart)->Release(smart);
    }
    IODestroyPlugInInterface(plugin);
    return ok;
}
