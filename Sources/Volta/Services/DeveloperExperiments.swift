import Foundation

enum DeveloperExperiments {
    static let disableRAMOptimizationsKey = "disableRAMOptimizations"
    static let appWorkerLimitKey = "appWorkerLimit"
    static let preciseTimestampsKey = "preciseTimestamps"
    static let fakeListeningStatsKey = "fakeListeningStats"
    private static let legacySingleThreadedModeKey = "singleThreadedMode"

    static var fakeListeningStats: Bool {
        UserDefaults.standard.bool(forKey: fakeListeningStatsKey)
    }

    static var disableRAMOptimizations: Bool {
        UserDefaults.standard.object(forKey: disableRAMOptimizationsKey) as? Bool ?? false
    }

    static var preciseTimestamps: Bool {
        UserDefaults.standard.object(forKey: preciseTimestampsKey) as? Bool ?? false
    }

    static var appWorkerLimit: Int {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: appWorkerLimitKey) == nil,
           defaults.object(forKey: legacySingleThreadedModeKey) as? Bool == true {
            defaults.set(1, forKey: appWorkerLimitKey)
        }

        let value = defaults.integer(forKey: appWorkerLimitKey)
        return [1, 2, 4].contains(value) ? value : 0
    }

    static var isAppWorkerLimitEnabled: Bool {
        appWorkerLimit > 0
    }

    static var isAppWorkerSerialized: Bool {
        appWorkerLimit == 1
    }

    static func constrainedConcurrency(default defaultCount: Int) -> Int {
        let limit = appWorkerLimit
        guard limit > 0 else { return max(1, defaultCount) }
        return max(1, min(limit, defaultCount))
    }

    static func runSync<T: Sendable>(
        priority: TaskPriority = .utility,
        _ operation: @escaping @Sendable () -> T
    ) async -> T {
        await withWorkerPermit {
            await Task.detached(priority: priority) { operation() }.value
        }
    }

    static func runThrowingSync<T: Sendable>(
        priority: TaskPriority = .utility,
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withThrowingWorkerPermit {
            try await Task.detached(priority: priority) { try operation() }.value
        }
    }

    static func runBlocking<T>(
        qos: DispatchQoS.QoSClass = .utility,
        _ operation: @escaping () -> T
    ) async -> T {
        await withWorkerPermit {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: qos).async {
                    continuation.resume(returning: operation())
                }
            }
        }
    }

    static func runConcurrently<Element: Sendable, Result: Sendable>(
        _ elements: [Element],
        defaultMaxConcurrent: Int,
        _ operation: @escaping @Sendable (Element) async -> Result
    ) async -> [Result] {
        guard !elements.isEmpty else { return [] }
        let maxConcurrent = constrainedConcurrency(default: defaultMaxConcurrent)
        if maxConcurrent <= 1 || elements.count == 1 {
            var results: [Result] = []
            results.reserveCapacity(elements.count)
            for element in elements {
                results.append(await operation(element))
            }
            return results
        }

        return await withTaskGroup(of: (Int, Result).self, returning: [Result].self) { group in
            var iterator = elements.enumerated().makeIterator()
            var enqueued = 0

            func addNext() {
                guard let next = iterator.next() else { return }
                enqueued += 1
                group.addTask {
                    let result = await withWorkerPermit {
                        await operation(next.element)
                    }
                    return (next.offset, result)
                }
            }

            for _ in 0..<min(maxConcurrent, elements.count) {
                addNext()
            }

            var ordered = Array<Result?>(repeating: nil, count: elements.count)
            while enqueued > 0, let (offset, result) = await group.next() {
                enqueued -= 1
                ordered[offset] = result
                addNext()
            }

            return ordered.compactMap { $0 }
        }
    }

    static func launch(
        priority: TaskPriority = .utility,
        _ operation: @escaping @Sendable () async -> Void
    ) {
        Task.detached(priority: priority) {
            await operation()
        }
    }

    static func queue(label: String, qos: DispatchQoS = .default) -> DispatchQueue {
        DispatchQueue(label: label, qos: qos)
    }

    private static func withWorkerPermit<T>(
        _ operation: () async -> T
    ) async -> T {
        let limit = appWorkerLimit
        guard limit > 0 else { return await operation() }
        await AppWorkerLimiter.shared.acquire(limit: limit)
        let result = await operation()
        AppWorkerLimiter.shared.release()
        return result
    }

    private static func withThrowingWorkerPermit<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        let limit = appWorkerLimit
        guard limit > 0 else { return try await operation() }
        await AppWorkerLimiter.shared.acquire(limit: limit)
        do {
            let result = try await operation()
            AppWorkerLimiter.shared.release()
            return result
        } catch {
            AppWorkerLimiter.shared.release()
            throw error
        }
    }
}

private final class AppWorkerLimiter: @unchecked Sendable {
    static let shared = AppWorkerLimiter()

    private let lock = NSLock()
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire(limit: Int) async {
        guard limit > 0 else { return }
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if active < limit {
                    active += 1
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
    }

    func release() {
        let next: CheckedContinuation<Void, Never>? = lock.withLock {
            if !waiters.isEmpty {
                return waiters.removeFirst()
            }
            active = max(0, active - 1)
            return nil
        }
        next?.resume()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
