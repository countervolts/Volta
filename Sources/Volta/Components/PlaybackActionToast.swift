import SwiftUI
import Observation

enum VoltaNotificationTone: String, CaseIterable, Identifiable {
    case queue
    case success
    case info
    case warning
    case error

    var id: String { rawValue }

    var settingsLabel: String {
        switch self {
        case .queue:   return "Queue"
        case .success: return "Success"
        case .info:    return "Info"
        case .warning: return "Warning"
        case .error:   return "Error"
        }
    }

    var testMessage: String {
        switch self {
        case .queue:   return "Playing Next"
        case .success: return "Saved playlist"
        case .info:    return "Library refreshed"
        case .warning: return "Server is slow"
        case .error:   return "Playback failed"
        }
    }

    var icon: String {
        switch self {
        case .queue:   return "text.line.first.and.arrowtriangle.forward"
        case .success: return "checkmark.circle.fill"
        case .info:    return "sparkles"
        case .warning: return Symbols.warning
        case .error:   return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .queue:   return Theme.accent
        case .success: return .green
        case .info:    return .white
        case .warning: return .yellow
        case .error:   return Theme.error
        }
    }

    static func inferred(from message: String) -> VoltaNotificationTone {
        let lower = message.lowercased()
        if lower == "playing next" { return .queue }
        if lower.contains("error") || lower.contains("failed") { return .error }
        if lower.contains("warning") || lower.contains("offline") { return .warning }
        if lower.contains("added") || lower.contains("saved") || lower.contains("downloaded") { return .success }
        return .info
    }
}

struct VoltaNotificationItem: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let tone: VoltaNotificationTone
    let duration: TimeInterval
}

@MainActor
@Observable
final class VoltaNotificationCenter {
    static let shared = VoltaNotificationCenter()

    private(set) var current: VoltaNotificationItem?

    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var sequenceTask: Task<Void, Never>?
    @ObservationIgnored private var lastMessage = ""
    @ObservationIgnored private var lastPostedAt = Date.distantPast

    func post(_ message: String, tone: VoltaNotificationTone? = nil, duration: TimeInterval = 2.6, force: Bool = false) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let resolvedTone = tone ?? .inferred(from: trimmed)
        let showWarnings = UserDefaults.standard.object(forKey: "showWarningNotifications") as? Bool ?? false
        guard force || resolvedTone != .warning || showWarnings else { return }
        let showOfflineErrors = UserDefaults.standard.object(forKey: "showOfflineErrorNotifications") as? Bool ?? false
        guard force || resolvedTone != .error || !Self.isOfflineMessage(trimmed) || showOfflineErrors else { return }

        let now = Date()
        guard trimmed != lastMessage || now.timeIntervalSince(lastPostedAt) > 1.0 else { return }
        lastMessage = trimmed
        lastPostedAt = now

        let item = VoltaNotificationItem(
            message: trimmed,
            tone: resolvedTone,
            duration: duration
        )
        current = item
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0.8, duration) * 1_000_000_000))
            guard !Task.isCancelled, current?.id == item.id else { return }
            current = nil
        }
    }

    func postLog(_ entry: LogEntry) {
        guard entry.level != .info else { return }
        if entry.level == .error,
           Self.isOfflineMessage(entry.message),
           !(UserDefaults.standard.object(forKey: "showOfflineErrorNotifications") as? Bool ?? false) {
            return
        }
        let tone: VoltaNotificationTone = entry.level == .error ? .error : .warning
        let prefix = entry.level == .error ? "Error" : "Warning"
        post("\(prefix): \(shortMessage(entry.message))", tone: tone, duration: entry.level == .error ? 3.4 : 3.0)
    }

    func postTestNotifications() {
        sequenceTask?.cancel()
        sequenceTask = Task { @MainActor in
            for tone in VoltaNotificationTone.allCases {
                post(tone.testMessage, tone: tone, duration: 1.5, force: true)
                try? await Task.sleep(nanoseconds: 950_000_000)
                guard !Task.isCancelled else { return }
            }
        }
    }

    private func shortMessage(_ message: String) -> String {
        let cleaned = message
            .replacingOccurrences(of: "✗ ", with: "")
            .replacingOccurrences(of: "⚠ ", with: "")
            .replacingOccurrences(of: "✓ ", with: "")
        guard cleaned.count > 110 else { return cleaned }
        return String(cleaned.prefix(107)) + "..."
    }

    private static func isOfflineMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("offline")
            || lower.contains("unreachable")
            || lower.contains("no network")
            || lower.contains("not connected")
            || lower.contains("network connection was lost")
            || lower.contains("could not reach")
            || lower.contains("connection test failed")
    }
}

struct VoltaNotificationHost: View {
    @State private var center = VoltaNotificationCenter.shared

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if let item = center.current {
                VoltaNotificationToast(message: item.message, tone: item.tone)
                    .id(item.id)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 84)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: center.current?.id)
        .allowsHitTesting(false)
    }
}

struct VoltaNotificationToast: View {
    let message: String
    var tone: VoltaNotificationTone?
    @State private var appeared = false

    private var resolvedTone: VoltaNotificationTone {
        tone ?? .inferred(from: message)
    }

    var body: some View {
        let tone = resolvedTone
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tone.tint.opacity(0.18))
                Image(systemName: tone.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tone.tint)
            }
            .frame(width: 30, height: 30)
            .symbolEffect(.bounce, value: appeared)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(.white)
        .padding(.leading, 10)
        .padding(.trailing, 18)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.66))
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.20), tone.tint.opacity(0.18), .white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: tone.tint.opacity(0.24), radius: 18, x: 0, y: 8)
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 8)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                appeared = true
            }
        }
        .accessibilityLabel(message)
    }
}

struct PlaybackActionToast: View {
    let message: String

    var body: some View {
        VoltaNotificationToast(message: message)
    }
}
