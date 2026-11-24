#include "SystemProbe.h"
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <sys/sysctl.h>
#include <sys/mount.h>
#include <libproc.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/IOBlockStorageDriver.h>
#include <mach/processor_info.h>
#include <sys/resource.h>
#include <mach/mach_time.h>
#include <net/route.h>
#include <math.h>

static uint64_t dictionary_number(CFDictionaryRef d, CFStringRef key) {
    int64_t value = 0;
    CFTypeRef number = CFDictionaryGetValue(d, key);
    if (number && CFGetTypeID(number) == CFNumberGetTypeID()) CFNumberGetValue(number, kCFNumberSInt64Type, &value);
    return value < 0 ? 0 : (uint64_t)value;
}

static double dictionary_percent(CFDictionaryRef d, CFStringRef key) {
    double value = -1;
    CFTypeRef number = CFDictionaryGetValue(d, key);
    if (!number || CFGetTypeID(number) != CFNumberGetTypeID() ||
        !CFNumberGetValue(number, kCFNumberDoubleType, &value) ||
        !isfinite(value) || value < 0 || value > 100) return -1;
    return value;
}

// Capability-tested driver statistics, read directly without a helper or shell polling.
static void sample_gpu(ASSystem *s) {
    s->gpu_percent = s->gpu_renderer_percent = s->gpu_tiler_percent = -1;
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"), &iterator) != KERN_SUCCESS) return;
    io_object_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        CFTypeRef stats = IORegistryEntryCreateCFProperty(entry, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
        if (!s->gpu_valid && stats && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
            CFDictionaryRef d = (CFDictionaryRef)stats;
            double utilization = dictionary_percent(d, CFSTR("Device Utilization %"));
            if (utilization >= 0) {
                s->gpu_valid = 1; s->gpu_percent = utilization;
                s->gpu_renderer_percent = dictionary_percent(d, CFSTR("Renderer Utilization %"));
                s->gpu_tiler_percent = dictionary_percent(d, CFSTR("Tiler Utilization %"));
                if (CFDictionaryContainsKey(d, CFSTR("Alloc system memory")) && CFDictionaryContainsKey(d, CFSTR("In use system memory"))) {
                    s->gpu_memory_valid = 1;
                    s->gpu_allocated_bytes = dictionary_number(d, CFSTR("Alloc system memory"));
                    s->gpu_in_use_bytes = dictionary_number(d, CFSTR("In use system memory"));
                }
            }
        }
        if (stats) CFRelease(stats);
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
}

// MLX's Python wheels load mlx/core.<abi>.so, which links mlx/lib/libmlx.dylib. Both stay mapped for the life of
// the process (checked against mlx 0.32.4); mlx.metallib is read, not mapped, so it is not a usable marker.
int as_path_is_mlx_runtime(const char *path) {
    if (!path || !path[0]) return 0;
    const char *base = strrchr(path, '/'); base = base ? base + 1 : path;
    size_t length = strlen(base);
    if (!strncmp(base, "libmlx.", 7) && !strcmp(base + length - 6, ".dylib")) return 1;
    if (!strncmp(base, "core.", 5) && length > 3 && !strcmp(base + length - 3, ".so") &&
        base - path >= 5 && !strncmp(base - 5, "/mlx/", 5)) return 1;
    return 0;
}

int as_process_maps_mlx(int32_t pid) {
    uint64_t address = 0;
    // Bounded walk of the mapped regions; the kernel returns the region at or after the address.
    for (int i = 0; i < 16384; i++) {
        struct proc_regionwithpathinfo info;
        int size = proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &info, sizeof(info));
        if (size != (int)sizeof(info)) return i == 0 ? -1 : 0;
        info.prp_vip.vip_path[sizeof(info.prp_vip.vip_path) - 1] = 0;
        if (as_path_is_mlx_runtime(info.prp_vip.vip_path)) return 1;
        uint64_t next = info.prp_prinfo.pri_address + info.prp_prinfo.pri_size;
        if (next <= address) return 0;
        address = next;
    }
    return 0;
}

int as_topology(int level) {
    char key[64]; snprintf(key, sizeof(key), "hw.perflevel%d.logicalcpu", level);
    int result = 0; size_t size = sizeof(result);
    return sysctlbyname(key, &result, &size, NULL, 0) == 0 ? result : 0;
}

int as_core_ticks(uint64_t *out, int capacity) {
    processor_info_array_t info;
    mach_msg_type_number_t count;
    natural_t cores;
    mach_port_t host = mach_host_self();
    kern_return_t result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cores, &info, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (result != KERN_SUCCESS) return 0;
    int n = (int)cores < capacity / 4 ? (int)cores : capacity / 4;
    for (int i = 0; i < n * 4; i++) out[i] = (uint32_t)info[i];
    vm_deallocate(mach_task_self(), (vm_address_t)info, count * sizeof(integer_t));
    return n;
}

ASSystem as_system_sample(void) {
    ASSystem s = {0}; s.battery_percent = -1;
    sample_gpu(&s);
    mach_port_t host = mach_host_self();
    host_cpu_load_info_data_t cpu;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    if (host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&cpu, &count) == KERN_SUCCESS) {
        s.cpu_valid = 1;
        s.cpu_user = cpu.cpu_ticks[CPU_STATE_USER]; s.cpu_system = cpu.cpu_ticks[CPU_STATE_SYSTEM];
        s.cpu_idle = cpu.cpu_ticks[CPU_STATE_IDLE]; s.cpu_nice = cpu.cpu_ticks[CPU_STATE_NICE];
    }
    size_t size = sizeof(s.memory_total);
    sysctlbyname("hw.memsize", &s.memory_total, &size, NULL, 0);
    vm_statistics64_data_t vm;
    count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS && s.memory_total) {
        s.memory_valid = 1;
        // Approximate application+wired+compressed memory; exclude purgeable and file cache.
        uint64_t used = (uint64_t)vm.active_count + vm.inactive_count + vm.wire_count + vm.compressor_page_count;
        uint64_t reclaimable = (uint64_t)vm.external_page_count + vm.purgeable_count;
        s.memory_used = (used > reclaimable ? used - reclaimable : 0) * vm_kernel_page_size;
        if (s.memory_used > s.memory_total) s.memory_used = s.memory_total;
        s.memory_compressed = (uint64_t)vm.compressor_page_count * vm_kernel_page_size;
        s.memory_wired = (uint64_t)vm.wire_count * vm_kernel_page_size;
        s.memory_cached = (uint64_t)vm.external_page_count * vm_kernel_page_size;
        s.swap_in = vm.swapins * vm_kernel_page_size;
        s.swap_out = vm.swapouts * vm_kernel_page_size;
    }
    mach_port_deallocate(mach_task_self(), host);
    struct xsw_usage swap; size = sizeof(swap);
    if (!sysctlbyname("vm.swapusage", &swap, &size, NULL, 0)) s.swap_used = swap.xsu_used;
    size = sizeof(s.memory_pressure);
    sysctlbyname("kern.memorystatus_vm_pressure_level", &s.memory_pressure, &size, NULL, 0);
    struct statfs fs;
    if (!statfs("/System/Volumes/Data", &fs)) {
        s.disk_valid = 1; s.disk_total = fs.f_blocks * fs.f_bsize; s.disk_free = fs.f_bavail * fs.f_bsize;
    }
    io_iterator_t iterator;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS) {
        io_object_t entry;
        while ((entry = IOIteratorNext(iterator))) {
            CFTypeRef stats = IORegistryEntryCreateCFProperty(entry, CFSTR(kIOBlockStorageDriverStatisticsKey), kCFAllocatorDefault, 0);
            if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
                CFDictionaryRef d = (CFDictionaryRef)stats;
                if (CFDictionaryContainsKey(d, CFSTR(kIOBlockStorageDriverStatisticsBytesReadKey))) {
                    s.disk_io_valid = 1;
                    s.disk_read += dictionary_number(d, CFSTR(kIOBlockStorageDriverStatisticsBytesReadKey));
                    s.disk_write += dictionary_number(d, CFSTR(kIOBlockStorageDriverStatisticsBytesWrittenKey));
                    s.disk_reads += dictionary_number(d, CFSTR(kIOBlockStorageDriverStatisticsReadsKey));
                    s.disk_writes += dictionary_number(d, CFSTR(kIOBlockStorageDriverStatisticsWritesKey));
                }
            }
            if (stats) CFRelease(stats);
            IOObjectRelease(entry);
        }
        IOObjectRelease(iterator);
    }
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t network_size = 0;
    if (!sysctl(mib, 6, NULL, &network_size, NULL, 0) && network_size > 0 && network_size < 1048576) {
        char *network = malloc(network_size);
        if (network && !sysctl(mib, 6, network, &network_size, NULL, 0)) {
            s.network_valid = 1;
            for (char *cursor = network; cursor + sizeof(struct if_msghdr) <= network + network_size;) {
                struct if_msghdr *header = (struct if_msghdr *)cursor;
                if (!header->ifm_msglen || cursor + header->ifm_msglen > network + network_size) break;
                if (header->ifm_type == RTM_IFINFO2 && header->ifm_msglen >= sizeof(struct if_msghdr2)) {
                    struct if_msghdr2 *message = (struct if_msghdr2 *)cursor;
                    char name[IF_NAMESIZE] = {0};
                    if (if_indextoname(message->ifm_index, name) && !strncmp(name, "en", 2) && (message->ifm_flags & IFF_UP)) {
                        s.network_in += message->ifm_data.ifi_ibytes;
                        s.network_out += message->ifm_data.ifi_obytes;
                        if (s.network_interfaces[0]) strlcat(s.network_interfaces, ", ", sizeof(s.network_interfaces));
                        strlcat(s.network_interfaces, name, sizeof(s.network_interfaces));
                    }
                }
                cursor += header->ifm_msglen;
            }
        }
        free(network);
    }
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (info) {
        CFArrayRef sources = IOPSCopyPowerSourcesList(info);
        if (sources) {
            for (CFIndex i = 0; i < CFArrayGetCount(sources); i++) {
                CFDictionaryRef d = IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(sources, i));
                if (!d) continue;
                CFStringRef type = CFDictionaryGetValue(d, CFSTR(kIOPSTypeKey));
                if (!type || !CFEqual(type, CFSTR(kIOPSInternalBatteryType))) continue;
                int current = 0, max = 0;
                CFNumberRef c = CFDictionaryGetValue(d, CFSTR(kIOPSCurrentCapacityKey));
                CFNumberRef m = CFDictionaryGetValue(d, CFSTR(kIOPSMaxCapacityKey));
                if (c && m) {
                    CFNumberGetValue(c, kCFNumberIntType, &current); CFNumberGetValue(m, kCFNumberIntType, &max);
                    if (max > 0) s.battery_percent = 100.0 * current / max;
                }
                CFStringRef power = CFDictionaryGetValue(d, CFSTR(kIOPSPowerSourceStateKey));
                s.battery_charging = power && CFEqual(power, CFSTR(kIOPSACPowerValue));
            }
            CFRelease(sources);
        }
        CFRelease(info);
    }
    return s;
}

int as_process_sample(ASProcess *out, int capacity) {
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes <= 0) return -1;
    int slots = bytes / (int)sizeof(pid_t) + 256;
    pid_t *pids = calloc((size_t)slots, sizeof(pid_t));
    if (!pids) return -1;
    int result = proc_listpids(PROC_ALL_PIDS, 0, pids, slots * (int)sizeof(pid_t));
    int written = 0;
    for (int i = 0; i < result / (int)sizeof(pid_t) && written < capacity; i++) {
        struct proc_bsdinfo bsd;
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) != sizeof(bsd)) continue;
        struct proc_taskinfo task = {0};
        int task_valid = proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &task, sizeof(task)) == sizeof(task);
        char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
        proc_pidpath(pids[i], path, sizeof(path));
        const char *base = strrchr(path, '/'); base = base ? base + 1 : path;
        int app = 0;
        if (strstr(path, "/Codex.app/") || strstr(path, "/Codex Framework.framework/") || !strcmp(base, "codex")) app = 1;
        else if (strstr(path, "/Claude.app/") || !strcmp(base, "claude")) app = 2;
        else if (strstr(path, "/Ollama.app/") || !strcmp(base, "ollama")) app = 3;
        else if (strstr(path, "/Blender.app/") || !strcmp(base, "blender")) app = 5;
        else if (!strncasecmp(base, "python", 6)) app = 6; /* framework builds report "Python" */
        else if (!strcmp(base, "node")) app = 7;
        else if (!strcmp(base, "ffmpeg")) app = 8;
        else if (strstr(path, "/Visual Studio Code.app/")) app = 9;
        if (pids[i] == getpid()) app = 4;
        ASProcess p = {pids[i], (int32_t)bsd.pbi_ppid,
            bsd.pbi_start_tvsec * 1000000ULL + bsd.pbi_start_tvusec,
            (uint64_t)(((__uint128_t)task.pti_total_user + task.pti_total_system) * timebase.numer / timebase.denom), task.pti_resident_size, app};
        p.task_valid = task_valid; p.threads = task.pti_threadnum; p.status = bsd.pbi_status; p.uid = bsd.pbi_uid;
        strlcpy(p.name, bsd.pbi_name[0] ? bsd.pbi_name : bsd.pbi_comm, sizeof(p.name));
        strlcpy(p.path, path, sizeof(p.path));
        struct rusage_info_v2 usage = {0};
        if (!proc_pid_rusage(pids[i], RUSAGE_INFO_V2, (rusage_info_t *)&usage)) {
            p.io_valid = 1; p.disk_read = usage.ri_diskio_bytesread; p.disk_write = usage.ri_diskio_byteswritten;
        }
        out[written++] = p;
    }
    free(pids);
    return result < 0 ? -1 : written;
}
