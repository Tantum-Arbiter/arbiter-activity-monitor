#ifndef SYSTEM_PROBE_H
#define SYSTEM_PROBE_H
#include <stdint.h>

typedef struct {
    uint64_t cpu_user, cpu_system, cpu_idle, cpu_nice;
    uint64_t memory_total, memory_used, memory_compressed, swap_used;
    uint64_t disk_total, disk_free, network_in, network_out;
    uint64_t memory_wired, memory_cached, swap_in, swap_out;
    uint64_t disk_read, disk_write, disk_reads, disk_writes;
    int disk_io_valid;
    char network_interfaces[256];
    double battery_percent;
    double gpu_percent, gpu_renderer_percent, gpu_tiler_percent;
    uint64_t gpu_allocated_bytes, gpu_in_use_bytes;
    int gpu_valid, gpu_memory_valid;
    int cpu_valid, memory_valid, disk_valid, network_valid, battery_charging, memory_pressure;
} ASSystem;

typedef struct {
    int32_t pid, parent;
    uint64_t start, cpu_ns, resident_bytes;
    int app; /* 1 Codex, 2 Claude, 3 Ollama, 4 monitor itself, 5 Blender, 6 Python, 7 Node, 8 FFmpeg, 9 VS Code.
                10 (MLX) is assigned by the collector from as_process_maps_mlx, not here. */
    uint64_t disk_read, disk_write;
    int io_valid, task_valid, threads, status, uid;
    char name[256], path[1024];
} ASProcess;

ASSystem as_system_sample(void);
int as_process_sample(ASProcess *out, int capacity);
int as_core_ticks(uint64_t *out, int capacity);
int as_topology(int level);
/* 1 when the process has the MLX runtime mapped, 0 when it does not, -1 when its regions cannot be read.
   Compares mapped file names only: no arguments, environment, file contents or model files are read. */
int as_process_maps_mlx(int32_t pid);
int as_path_is_mlx_runtime(const char *path);
/* Start time in microseconds since 1970 (the ASProcess.start encoding), or 0 when the process is gone or unreadable. */
uint64_t as_process_start(int32_t pid);
/* Physical footprint in bytes (Activity Monitor's Memory column, including GPU allocations charged to the task), or 0 when unreadable. */
uint64_t as_process_footprint(int32_t pid);
/* PID of a current-user process with a TCP socket listening on this port, or 0 when none is found. Reads socket metadata only. */
int32_t as_listening_pid(uint16_t port);
/* Footprint of pid plus its descendants (depth 4, at most 64 processes): a runtime server and its model runners. 0 when unreadable. */
uint64_t as_tree_footprint(int32_t pid);
#endif
