#include "Sensors.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>

// Read-only private HID API. Resolve every symbol before use; unavailable = no readings.
int systra_temperatures(SystraTemperature *out, int capacity) {
    typedef CFTypeRef (*Create)(CFAllocatorRef);
    typedef void (*Match)(CFTypeRef, CFDictionaryRef);
    typedef CFArrayRef (*Services)(CFTypeRef);
    typedef CFTypeRef (*Property)(CFTypeRef, CFStringRef);
    typedef CFTypeRef (*Event)(CFTypeRef, int64_t, int32_t, int64_t);
    typedef double (*Value)(CFTypeRef, uint32_t);
    static void *library;
    static CFTypeRef client;
    static Services services;
    static Property property;
    static Event event;
    static Value value;
    static int initialized;
    if (!initialized) {
        initialized = 1;
        library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        if (!library) return -1;
        Create create = (Create)dlsym(library, "IOHIDEventSystemClientCreate");
        Match match = (Match)dlsym(library, "IOHIDEventSystemClientSetMatching");
        services = (Services)dlsym(library, "IOHIDEventSystemClientCopyServices");
        property = (Property)dlsym(library, "IOHIDServiceClientCopyProperty");
        event = (Event)dlsym(library, "IOHIDServiceClientCopyEvent");
        value = (Value)dlsym(library, "IOHIDEventGetFloatValue");
        if (!create || !match || !services || !property || !event || !value) return -1;
        client = create(kCFAllocatorDefault);
        if (!client) return -1;
        int page = 0xff00, usage = 5;
        CFNumberRef pageNumber = CFNumberCreate(NULL, kCFNumberIntType, &page);
        CFNumberRef usageNumber = CFNumberCreate(NULL, kCFNumberIntType, &usage);
        const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
        const void *values[] = { pageNumber, usageNumber };
        CFDictionaryRef matching = CFDictionaryCreate(NULL, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        match(client, matching);
        CFRelease(matching); CFRelease(pageNumber); CFRelease(usageNumber);
    }
    if (!client) return -1;
    CFArrayRef list = services(client);
    if (!list) return 0;
    int count = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(list) && count < capacity; i++) {
        CFTypeRef service = CFArrayGetValueAtIndex(list, i);
        CFTypeRef reading = event(service, 15, 0, 0);
        if (!reading) continue;
        double temperature = value(reading, 15 << 16);
        CFRelease(reading);
        if (!isfinite(temperature) || temperature < 1 || temperature > 130) continue;
        CFTypeRef name = property(service, CFSTR("Product"));
        if (name && CFGetTypeID(name) == CFStringGetTypeID() &&
            CFStringGetCString((CFStringRef)name, out[count].name, sizeof(out[count].name), kCFStringEncodingUTF8)) {
            out[count].celsius = temperature;
            count++;
        }
        if (name) CFRelease(name);
    }
    CFRelease(list);
    return count;
}

#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <mach/mach_time.h>
int systra_processes(SystraProcess *out, int capacity) {
    int available = proc_listallpids(NULL, 0);
    if (available <= 0) return -1;
    int allocated = available + 512;
    pid_t *pids = calloc(allocated, sizeof(pid_t));
    if (!pids) return -1;
    int found = proc_listallpids(pids, allocated * sizeof(pid_t));
    if (found < 0) { free(pids); return -1; }
    int count = 0;
    for (int i = 0; i < found && i < allocated && count < capacity; i++) {
        if (pids[i] <= 0) continue;
        struct proc_bsdinfo bsd = {0};
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) != sizeof(bsd)) continue;
        SystraProcess row = {0};
        row.pid = pids[i]; row.parent = bsd.pbi_ppid; row.uid = bsd.pbi_uid;
        row.startSeconds = bsd.pbi_start_tvsec; row.startMicroseconds = bsd.pbi_start_tvusec;
        if (proc_pidpath(row.pid, row.executable, sizeof(row.executable)) <= 0)
            strncpy(row.executable, bsd.pbi_comm, sizeof(row.executable) - 1);
        struct proc_taskinfo task = {0};
        if (proc_pidinfo(row.pid, PROC_PIDTASKINFO, 0, &task, sizeof(task)) == sizeof(task)) {
            row.hasUsage = 1;
            mach_timebase_info_data_t timebase = {0};
            mach_timebase_info(&timebase);
            row.cpuNanoseconds = (uint64_t)((long double)(task.pti_total_user + task.pti_total_system) * timebase.numer / timebase.denom);
            row.resident = task.pti_resident_size;
        }
        struct rusage_info_v2 usage = {0};
        if (proc_pid_rusage(row.pid, RUSAGE_INFO_V2, (rusage_info_t *)&usage) == 0) {
            row.hasDisk = 1;
            row.footprint = usage.ri_phys_footprint;
            row.readBytes = usage.ri_diskio_bytesread;
            row.writtenBytes = usage.ri_diskio_byteswritten;
        }
        out[count++] = row;
    }
    free(pids);
    return count;
}
int systra_same_process(int32_t pid, uint64_t seconds, uint64_t micros) {
    struct proc_bsdinfo bsd = {0};
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) == sizeof(bsd) &&
        bsd.pbi_start_tvsec == seconds && bsd.pbi_start_tvusec == micros;
}
