import Foundation
import SystemProbe

public actor Collector {
    private var lastCPU: [UInt64]?
    private var lastNetwork: (UInt64, UInt64)?
    private var lastTime: TimeInterval?
    private struct ProcessCounter {
        let start: UInt64
        let cpu_ns: UInt64
        let disk_read: UInt64
        let disk_write: UInt64
        let io_valid: Int32
    }
    private var lastProcesses: [Int32: ProcessCounter] = [:]
    private var cachedProcesses: [ProcessSample] = []
    private var cachedApps: [AppResource] = []
    private var cachedMonitor: (Double?, UInt64) = (nil, 0)
    private var processTime: TimeInterval?
    private var lastCores: [[UInt64]] = []
    private var lastDisk: [UInt64]?
    private var lastSwap: [UInt64]?
    private var mlxDetector = MLXDetector()
    public init() {}

    public func sample() -> SystemSample {
        let start = ProcessInfo.processInfo.systemUptime
        var raw = as_system_sample()
        var sample = SystemSample()
        sample.gpu = raw.gpu_valid != 0 ? raw.gpu_percent : nil
        sample.gpuRenderer = raw.gpu_renderer_percent >= 0 ? raw.gpu_renderer_percent : nil
        sample.gpuTiler = raw.gpu_tiler_percent >= 0 ? raw.gpu_tiler_percent : nil
        sample.gpuAllocated = raw.gpu_memory_valid != 0 ? raw.gpu_allocated_bytes : nil
        sample.gpuInUse = raw.gpu_memory_valid != 0 ? raw.gpu_in_use_bytes : nil
        let elapsed = lastTime.map { start - $0 } ?? 0
        let ticks = [raw.cpu_user, raw.cpu_system, raw.cpu_idle, raw.cpu_nice]
        sample.cpu = raw.cpu_valid != 0 && elapsed < 60 ? Measurement.cpu(current: ticks, previous: lastCPU) : nil
        if let previous = lastCPU, sample.cpu != nil {
            let delta = zip(ticks, previous).map(-)
            let total = Double(delta.reduce(0, +))
            if total > 0 { sample.userCPU = Double(delta[0] + delta[3]) / total * 100; sample.systemCPU = Double(delta[1]) / total * 100 }
        }
        lastCPU = raw.cpu_valid != 0 ? ticks : nil
        var coreBuffer = [UInt64](repeating: 0, count: 1024)
        let coreCount = Int(as_core_ticks(&coreBuffer, Int32(coreBuffer.count)))
        let cores = (0..<coreCount).map { Array(coreBuffer[($0 * 4)..<($0 * 4 + 4)]) }
        sample.cores = cores.enumerated().map { index, ticks in
            elapsed < 60 ? Measurement.cpu(current: ticks, previous: lastCores.indices.contains(index) ? lastCores[index] : nil) : nil
        }
        lastCores = cores
        sample.performanceCores = Int(as_topology(0)); sample.efficiencyCores = Int(as_topology(1))
        if raw.memory_valid != 0 {
            sample.memoryTotal = raw.memory_total; sample.memoryUsed = raw.memory_used
            sample.compressed = raw.memory_compressed; sample.swap = raw.swap_used
            sample.wired = raw.memory_wired; sample.cached = raw.memory_cached
        } else { sample.warnings.append("Memory measurement unavailable") }
        sample.pressure = [1: "Normal", 2: "Elevated", 4: "Critical"][Int(raw.memory_pressure)] ?? "Unavailable"
        sample.diskTotal = raw.disk_total; sample.diskFree = raw.disk_free
        let disk = [raw.disk_read, raw.disk_write, raw.disk_reads, raw.disk_writes]
        if raw.disk_io_valid != 0 {
            let rates = disk.enumerated().map { Measurement.rate(current: $0.element, previous: lastDisk?[$0.offset], seconds: elapsed) }
            sample.diskRead = rates[0]; sample.diskWrite = rates[1]; sample.diskReadOps = rates[2]; sample.diskWriteOps = rates[3]
            lastDisk = disk
        } else { lastDisk = nil }
        sample.swapIn = Measurement.rate(current: raw.swap_in, previous: lastSwap?[0], seconds: elapsed)
        sample.swapOut = Measurement.rate(current: raw.swap_out, previous: lastSwap?[1], seconds: elapsed)
        lastSwap = [raw.swap_in, raw.swap_out]
        sample.networkReceived = raw.network_in; sample.networkSent = raw.network_out
        sample.networkInterfaces = withUnsafePointer(to: &raw.network_interfaces) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
        if raw.network_valid != 0 {
            sample.download = Measurement.rate(current: raw.network_in, previous: lastNetwork?.0, seconds: elapsed)
            sample.upload = Measurement.rate(current: raw.network_out, previous: lastNetwork?.1, seconds: elapsed)
            lastNetwork = (raw.network_in, raw.network_out)
        } else { lastNetwork = nil }
        sample.battery = raw.battery_percent >= 0 ? raw.battery_percent : nil
        sample.onPower = raw.battery_charging != 0
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: sample.thermal = "Nominal"
        case .fair: sample.thermal = "Fair"
        case .serious: sample.thermal = "Serious"
        case .critical: sample.thermal = "Critical"
        @unknown default: sample.thermal = "Unavailable"
        }
        if let processTime, start - processTime < 2 {
            sample.processes = cachedProcesses; sample.apps = cachedApps
            sample.monitorCPU = cachedMonitor.0; sample.monitorMemory = cachedMonitor.1
            lastTime = start
            sample.collectionMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
            return sample
        }
        let processElapsed = processTime.map { start - $0 } ?? 0
        var buffer = [ASProcess](repeating: ASProcess(), count: 4096)
        let count = as_process_sample(&buffer, Int32(buffer.count))
        let processes = Array(buffer.prefix(max(0, Int(count))))
        if count < 0 { sample.warnings.append("App resource access unavailable") }
        if count == buffer.count { sample.warnings.append("Process inventory capacity reached; attribution is partial") }
        let parents = Dictionary(processes.map { ($0.pid, $0.parent) }, uniquingKeysWith: { first, _ in first })
        let roots = Dictionary(processes.filter { $0.app > 0 }.map { ($0.pid, Int($0.app)) }, uniquingKeysWith: { first, _ in first })
        var apps = AgentApp.allCases.map { AppResource(app: $0) }
        for process in processes {
            let previous = lastProcesses[process.pid]
            let cpu = Measurement.rate(current: process.cpu_ns, previous: previous?.start == process.start ? previous?.cpu_ns : nil, seconds: processElapsed).map { $0 / 1_000_000_000 * 100 }
            var mutable = process
            let name = withUnsafePointer(to: &mutable.name) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
            let path = withUnsafePointer(to: &mutable.path) { $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) } }
            let ioPrevious = previous?.start == process.start && previous?.io_valid == 1 ? previous : nil
            sample.processes.append(ProcessSample(pid: process.pid, parent: process.parent, started: process.start, name: name, path: path,
                cpu: process.task_valid == 1 ? cpu : nil, cpuTimeSeconds: process.task_valid == 1 ? Double(process.cpu_ns) / 1_000_000_000 : nil, memory: process.task_valid == 1 ? process.resident_bytes : nil,
                threads: process.task_valid == 1 ? Int(process.threads) : nil,
                read: process.io_valid == 1 ? Measurement.rate(current: process.disk_read, previous: ioPrevious?.disk_read, seconds: processElapsed) : nil,
                write: process.io_valid == 1 ? Measurement.rate(current: process.disk_write, previous: ioPrevious?.disk_write, seconds: processElapsed) : nil,
                state: [1: "Starting", 2: "Runnable", 3: "Sleeping", 4: "Stopped", 5: "Zombie"][Int(process.status)] ?? "Unknown",
                user: process.uid == getuid(), category: Int(process.app)))
            guard let owner = Measurement.owner(pid: process.pid, parents: parents, roots: roots) else { continue }
            if owner == 4 {
                sample.monitorCPU = cpu; sample.monitorMemory = process.resident_bytes
            } else if (1...3).contains(owner) {
                apps[owner - 1].processes += 1
                apps[owner - 1].memoryBytes += process.resident_bytes
                if let cpu { apps[owner - 1].cpuPercent = (apps[owner - 1].cpuPercent ?? 0) + cpu }
            }
        }
        let runtimes = mlxDetector.detect(in: sample.processes, now: start)
        if !runtimes.isEmpty {
            sample.processes = sample.processes.map { runtimes.contains($0.pid) ? $0.with(category: AgentApp.mlx.category) : $0 }
        }
        apps = AgentApp.allCases.map { AppResource(app: $0) }
        for workload in WorkloadAttribution.group(sample.processes) {
            guard let app = workload.root.agent, let index = apps.firstIndex(where: { $0.app == app }) else { continue }
            apps[index].processes += workload.members.count
            apps[index].memoryBytes += workload.memory
            if let cpu = workload.cpu { apps[index].cpuPercent = (apps[index].cpuPercent ?? 0) + cpu }
        }
        sample.apps = apps
        lastProcesses = Dictionary(processes.map { ($0.pid, ProcessCounter(start: $0.start, cpu_ns: $0.cpu_ns, disk_read: $0.disk_read, disk_write: $0.disk_write, io_valid: $0.io_valid)) }, uniquingKeysWith: { first, _ in first })
        cachedProcesses = sample.processes; cachedApps = apps
        cachedMonitor = (sample.monitorCPU, sample.monitorMemory)
        processTime = start
        lastTime = start
        sample.collectionMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
        return sample
    }
}
