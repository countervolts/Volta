import Combine
import Darwin
import SwiftUI
import UIKit

enum PerformanceOverlayItem: String, CaseIterable, Identifiable {
    case frameRate
    case frameTime
    case frameChart
    case memory
    case cpu
    case threads
    case cpuPower
    case thermal
    case battery
    case lowPower
    case queue
    case queueIndex
    case transition
    case autoplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frameRate: return "Frame Rate"
        case .frameTime: return "Frame Time"
        case .frameChart: return "Frame Chart"
        case .memory: return "RAM"
        case .cpu: return "CPU"
        case .threads: return "Threads"
        case .cpuPower: return "CPU Power"
        case .thermal: return "Thermal State"
        case .battery: return "Battery"
        case .lowPower: return "Low Power Mode"
        case .queue: return "Queue Length"
        case .queueIndex: return "Queue Index"
        case .transition: return "Transition"
        case .autoplay: return "Autoplay"
        }
    }

    var shortLabel: String {
        switch self {
        case .frameRate: return "FPS"
        case .frameTime: return "Frame"
        case .frameChart: return "Chart"
        case .memory: return "RAM"
        case .cpu: return "CPU"
        case .threads: return "Thr"
        case .cpuPower: return "CPU Pwr"
        case .thermal: return "Therm"
        case .battery: return "Batt"
        case .lowPower: return "LowPwr"
        case .queue: return "Q"
        case .queueIndex: return "Idx"
        case .transition: return "Trans"
        case .autoplay: return "Auto"
        }
    }

    var subtitle: String {
        switch self {
        case .frameRate: return "Current FPS and VSync mode."
        case .frameTime: return "Frame duration in milliseconds."
        case .frameChart: return "Recent frame pacing graph."
        case .memory: return "Current app memory footprint."
        case .cpu: return "Estimated process CPU load."
        case .threads: return "Active process threads over total threads."
        case .cpuPower: return "Approximate CPU power draw."
        case .thermal: return "System thermal pressure."
        case .battery: return "Battery level and charging state."
        case .lowPower: return "System Low Power Mode state."
        case .queue: return "Number of queued tracks."
        case .queueIndex: return "Current queue position."
        case .transition: return "Active playback transition mode."
        case .autoplay: return "Autoplay mode."
        }
    }

    var systemImage: String {
        switch self {
        case .frameRate: return "speedometer"
        case .frameTime: return "timer"
        case .frameChart: return "chart.xyaxis.line"
        case .memory: return "memorychip"
        case .cpu: return "cpu"
        case .threads: return "cpu.fill"
        case .cpuPower: return "bolt"
        case .thermal: return "thermometer.medium"
        case .battery: return "battery.75percent"
        case .lowPower: return "leaf"
        case .queue: return "text.line.first.and.arrowtriangle.forward"
        case .queueIndex: return "number"
        case .transition: return "point.topleft.down.curvedto.point.bottomright.up"
        case .autoplay: return "infinity"
        }
    }

    var isGridMetric: Bool {
        switch self {
        case .frameRate, .frameTime, .frameChart: return false
        default: return true
        }
    }
}

enum PerformanceOverlayConfiguration {
    static let itemsKey = "performanceOverlayItems"
    static let defaultRaw = PerformanceOverlayItem.allCases.map(\.rawValue).joined(separator: ",")
    private static let legacyDefaultRaw = PerformanceOverlayItem.allCases
        .filter { $0 != .threads }
        .map(\.rawValue)
        .joined(separator: ",")

    static func items(from raw: String) -> [PerformanceOverlayItem] {
        if raw == legacyDefaultRaw { return PerformanceOverlayItem.allCases }
        return raw.split(separator: ",").compactMap { PerformanceOverlayItem(rawValue: String($0)) }
    }

    static func raw(from items: [PerformanceOverlayItem]) -> String {
        items.map(\.rawValue).joined(separator: ",")
    }
}

struct PerformanceOverlay: View {
    @Environment(AppState.self) private var appState
    @AppStorage("performanceModeEnabled") private var performanceModeEnabled = false
    @AppStorage("pmHalfFrameRate") private var halfFrameRate = true
    @AppStorage(PerformanceOverlayConfiguration.itemsKey) private var overlayItemsRaw = PerformanceOverlayConfiguration.defaultRaw
    @StateObject private var monitor = PerformanceOverlayMonitor()

    private var audio: AudioPlayer { appState.audioPlayer }
    private var selectedItems: [PerformanceOverlayItem] {
        PerformanceOverlayConfiguration.items(from: overlayItemsRaw)
    }
    private var selectedSet: Set<PerformanceOverlayItem> { Set(selectedItems) }
    private var selectedGridMetrics: [PerformanceOverlayItem] {
        selectedItems.filter(\.isGridMetric)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selectedSet.contains(.frameRate) || selectedSet.contains(.frameTime) {
                frameHeader
            }

            if selectedSet.contains(.frameChart) {
                frameChart
            }

            if !selectedGridMetrics.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    ForEach(selectedGridMetrics) { item in
                        metric(item.shortLabel, value(for: item))
                    }
                }
            } else if selectedItems.isEmpty {
                Text("No metrics selected")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(10)
        .frame(width: 222, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
        .onChange(of: performanceModeEnabled) { _, _ in
            monitor.refreshFrameRate(resetSamples: true)
        }
        .onChange(of: halfFrameRate) { _, _ in
            monitor.refreshFrameRate(resetSamples: true)
        }
    }

    private var frameHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            if selectedSet.contains(.frameRate) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Int(monitor.fps.rounded())) FPS")
                        .font(.system(.headline, design: .monospaced).weight(.bold))
                        .foregroundStyle(color(for: monitor.fps, target: monitor.targetFPS))
                    Text(monitor.frameRateLabel)
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 10)
            if selectedSet.contains(.frameTime) {
                Text("\(Int(monitor.frameMS.rounded())) ms")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var autoplayLabel: String {
        switch audio.autoplayMode {
        case .off: return "Off"
        case .random: return "On"
        case .algorithm: return "Algo"
        }
    }

    private var frameChart: some View {
        Canvas { context, size in
            let samples = monitor.frameSamples
            guard samples.count > 1, size.width > 1, size.height > 1 else { return }
            let targetMS = monitor.targetFrameMS
            let maxMS = max(targetMS * 2, samples.max() ?? targetMS)
            var path = Path()
            for (index, value) in samples.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(max(1, samples.count - 1))
                let y = size.height - (size.height * CGFloat(min(maxMS, value) / maxMS))
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(Theme.accent), lineWidth: 1.5)

            var budget = Path()
            let budgetY = size.height - (size.height * CGFloat(targetMS / maxMS))
            budget.move(to: CGPoint(x: 0, y: budgetY))
            budget.addLine(to: CGPoint(x: size.width, y: budgetY))
            context.stroke(budget, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .frame(height: 34)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func value(for item: PerformanceOverlayItem) -> String {
        switch item {
        case .frameRate:
            return "\(Int(monitor.fps.rounded())) FPS"
        case .frameTime:
            return "\(Int(monitor.frameMS.rounded())) ms"
        case .frameChart:
            return ""
        case .memory:
            return ByteCountFormatter.string(fromByteCount: Int64(monitor.memoryBytes), countStyle: .memory)
        case .cpu:
            return "\(Int(monitor.cpuPercent.rounded()))%"
        case .threads:
            return monitor.threadSummary
        case .cpuPower:
            return String(format: "%.2f W", monitor.cpuPowerWatts)
        case .thermal:
            return monitor.thermalState
        case .battery:
            return monitor.batterySummary
        case .lowPower:
            return ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off"
        case .queue:
            return "\(audio.queue.count)"
        case .queueIndex:
            return audio.queue.isEmpty ? "-" : "\(audio.currentIndex + 1)"
        case .transition:
            return audio.transitionMode.settingsLabel
        case .autoplay:
            return autoplayLabel
        }
    }

    private func color(for fps: Double, target: Double) -> Color {
        let target = max(1, target)
        if fps >= target * 0.9 { return .green }
        if fps >= target * 0.75 { return .yellow }
        return Theme.error
    }
}

@MainActor
private final class PerformanceOverlayMonitor: NSObject, ObservableObject {
    @Published var fps: Double = 0
    @Published var frameMS: Double = 0
    @Published var memoryBytes: UInt64 = 0
    @Published var cpuPercent: Double = 0
    @Published var threadSummary: String = "0/0"
    @Published var cpuPowerWatts: Double = 0
    @Published var thermalState: String = "Nom"
    @Published var batterySummary: String = "--"
    @Published var frameSamples: [Double] = Array(repeating: 16.7, count: 36)
    @Published var targetFPS: Double = Double(FrameRateGovernor.maxFPS)
    @Published var isHalfRate: Bool = FrameRateGovernor.isHalfRate

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frames = 0
    private var elapsed: TimeInterval = 0
    private var lastCPUTime: TimeInterval?

    var targetFrameMS: Double {
        1_000 / max(1, targetFPS)
    }

    var frameRateLabel: String {
        isHalfRate ? "Half VSync \(Int(targetFPS.rounded()))" : "Native VSync"
    }

    func start() {
        guard displayLink == nil else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        memoryBytes = Self.memoryFootprintBytes()
        threadSummary = Self.threadSummary()
        lastCPUTime = Self.processCPUTime()
        refreshFrameRate(resetSamples: true)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        refreshFrameRate(resetSamples: false)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
        frames = 0
        elapsed = 0
        lastCPUTime = nil
    }

    func refreshFrameRate(resetSamples: Bool) {
        isHalfRate = FrameRateGovernor.isHalfRate
        targetFPS = Double(FrameRateGovernor.maxFPS)
        if resetSamples {
            frameSamples = Array(repeating: targetFrameMS, count: 36)
            frameMS = targetFrameMS
            fps = targetFPS
            lastTimestamp = 0
            frames = 0
            elapsed = 0
        }
        if let displayLink {
            FrameRateGovernor.apply(to: displayLink)
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        if isHalfRate != FrameRateGovernor.isHalfRate ||
            abs(targetFPS - Double(FrameRateGovernor.maxFPS)) > 0.1 {
            refreshFrameRate(resetSamples: false)
        }
        defer { lastTimestamp = link.timestamp }
        guard lastTimestamp > 0 else { return }
        let delta = link.timestamp - lastTimestamp
        guard delta.isFinite, delta > 0 else { return }
        frameMS = delta * 1_000
        frameSamples.append(frameMS)
        if frameSamples.count > 36 { frameSamples.removeFirst(frameSamples.count - 36) }
        frames += 1
        elapsed += delta
        if elapsed >= 0.5 {
            fps = Double(frames) / elapsed
            memoryBytes = Self.memoryFootprintBytes()
            threadSummary = Self.threadSummary()
            updateCPUAndPower(elapsed: elapsed)
            thermalState = Self.thermalStateLabel(ProcessInfo.processInfo.thermalState)
            batterySummary = Self.batterySummary()
            frames = 0
            elapsed = 0
        }
    }

    private func updateCPUAndPower(elapsed: TimeInterval) {
        let nowCPU = Self.processCPUTime()
        defer { lastCPUTime = nowCPU }
        guard let lastCPUTime, elapsed > 0 else { return }
        let deltaCPU = max(0, nowCPU - lastCPUTime)
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        cpuPercent = min(999, (deltaCPU / elapsed) * 100)
        let normalizedLoad = min(1, cpuPercent / Double(cores * 100))
        cpuPowerWatts = normalizedLoad * Double(cores) * 0.55
    }

    private static func memoryFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }

    private static func processCPUTime() -> TimeInterval {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        let user = TimeInterval(usage.ru_utime.tv_sec) + TimeInterval(usage.ru_utime.tv_usec) / 1_000_000
        let system = TimeInterval(usage.ru_stime.tv_sec) + TimeInterval(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    private static func threadSummary() -> String {
        let counts = threadCounts()
        return "\(counts.active)/\(counts.total)"
    }

    private static func threadCounts() -> (active: Int, total: Int) {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threadList else { return (0, 0) }
        defer {
            let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), size)
        }

        var active = 0
        for index in 0..<Int(threadCount) {
            var info = thread_basic_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
            let infoResult = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                    thread_info(threadList[index], thread_flavor_t(THREAD_BASIC_INFO), rebound, &count)
                }
            }
            guard infoResult == KERN_SUCCESS else { continue }
            let idle = (info.flags & TH_FLAGS_IDLE) != 0
            let workingState = info.run_state == TH_STATE_RUNNING
                || info.run_state == TH_STATE_UNINTERRUPTIBLE
                || info.cpu_usage > 0
            if !idle, workingState {
                active += 1
            }
        }
        return (active, Int(threadCount))
    }

    private static func thermalStateLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nom"
        case .fair: return "Fair"
        case .serious: return "Hot"
        case .critical: return "Crit"
        @unknown default: return "?"
        }
    }

    private static func batterySummary() -> String {
        let device = UIDevice.current
        let level = device.batteryLevel >= 0 ? "\(Int((device.batteryLevel * 100).rounded()))%" : "--"
        switch device.batteryState {
        case .charging: return "\(level)+"
        case .full: return "Full"
        case .unplugged: return level
        case .unknown: return "--"
        @unknown default: return "--"
        }
    }
}
