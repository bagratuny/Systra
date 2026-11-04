#ifndef SYSTRA_SENSORS_H
#define SYSTRA_SENSORS_H
#include <stdint.h>
typedef struct { char name[128]; double celsius; } SystraTemperature;
int systra_temperatures(SystraTemperature *readings, int capacity);
typedef struct {
    int32_t pid;
    int32_t parent;
    uint32_t uid;
    uint64_t startSeconds;
    uint64_t startMicroseconds;
    uint64_t cpuNanoseconds;
    uint64_t resident;
    uint64_t footprint;
    uint64_t readBytes;
    uint64_t writtenBytes;
    int hasUsage;
    int hasDisk;
    char executable[4096];
} SystraProcess;
int systra_processes(SystraProcess *out, int capacity);
int systra_same_process(int32_t pid, uint64_t seconds, uint64_t micros);

#endif
