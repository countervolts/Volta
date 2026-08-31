import AVFoundation
import Combine
import Foundation

enum EqualizerProfileKind: String, Codable, Sendable {
    case builtIn
    case custom
    case autoEQ

    var detail: String {
        switch self {
        case .builtIn: return "Built-in"
        case .custom: return "Custom"
        case .autoEQ: return "AutoEQ"
        }
    }
}

struct EqualizerProfile: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var gains: [Double]
    var preampDB: Double
    var kind: EqualizerProfileKind
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        gains: [Double],
        preampDB: Double = 0,
        kind: EqualizerProfileKind,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.gains = Self.normalizedGains(gains)
        self.preampDB = EqualizerBiquadDesigner.sanitizedPreampDB(preampDB)
        self.kind = kind
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, gains, preampDB, kind, createdAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        gains = Self.normalizedGains(try values.decode([Double].self, forKey: .gains))
        preampDB = EqualizerBiquadDesigner.sanitizedPreampDB(
            try values.decodeIfPresent(Double.self, forKey: .preampDB) ?? 0
        )
        kind = try values.decode(EqualizerProfileKind.self, forKey: .kind)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(gains, forKey: .gains)
        try values.encode(preampDB, forKey: .preampDB)
        try values.encode(kind, forKey: .kind)
        try values.encode(createdAt, forKey: .createdAt)
    }

    static func normalizedGains(_ values: [Double]) -> [Double] {
        let padded = values + [Double](repeating: 0, count: max(0, EqualizerEngine.bandCount - values.count))
        return Array(padded.prefix(EqualizerEngine.bandCount)).map(EqualizerBiquadDesigner.sanitizedGain)
    }
}

struct EqualizerDeviceProfileAssignment: Identifiable, Hashable {
    let routeKey: String
    let deviceName: String
    let profile: EqualizerProfile

    var id: String { routeKey }
}

enum AutoEQTenBandPasteImporter {
    enum ImportError: LocalizedError {
        case unsupportedFormat

        var errorDescription: String? {
            "Paste all ten AutoEQ rows from 31 Hz through 16000 Hz, plus the Preamp line."
        }
    }

    static func profile(from text: String) throws -> EqualizerProfile {
        let frequencies = [31.0, 63.0, 125.0, 250.0, 500.0, 1_000.0, 2_000.0, 4_000.0, 8_000.0, 16_000.0]
        var gains = [Double?](repeating: nil, count: frequencies.count)
        var preampDB: Double?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
                .replacingOccurrences(of: "−", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.range(of: "preamp", options: [.caseInsensitive]) != nil {
                guard let value = firstNumber(in: line) else { throw ImportError.unsupportedFormat }
                preampDB = value
                continue
            }

            let frequency: Double
            let gain: Double
            if let labeledFrequency = labeledNumber(after: "fc", in: line),
               let labeledGain = labeledNumber(after: "gain", in: line) {
                // Equalizer APO / AutoEQ FixedBandEQ:
                // Filter 1: ON PK Fc 31 Hz Gain -2.3 dB Q 1.41
                frequency = labeledFrequency
                gain = labeledGain
            } else {
                // Plain rows and Markdown tables. A leading band number is also
                // accepted, for example: | 1 | 31 Hz | -2.3 dB |
                let numbers = allNumbers(in: line)
                if numbers.count >= 3,
                   (1...frequencies.count).contains(Int(numbers[0])),
                   frequencies.contains(where: { abs($0 - numbers[1]) <= 1 }) {
                    frequency = numbers[1]
                    // AutoEQ's official table is # / Type / Fc / Q / Gain,
                    // while simpler tables omit Q. Gain is the final number.
                    gain = numbers.last ?? 0
                } else if numbers.count >= 2 {
                    frequency = numbers[0]
                    gain = numbers[1]
                } else {
                    continue
                }
            }
            guard frequency.isFinite,
                  gain.isFinite,
                  let index = frequencies.firstIndex(where: { abs($0 - frequency) <= 1 }) else { continue }
            guard gains[index] == nil else { throw ImportError.unsupportedFormat }
            gains[index] = gain
        }

        guard let preampDB, gains.allSatisfy({ $0 != nil }) else {
            throw ImportError.unsupportedFormat
        }
        return EqualizerProfile(
            name: "Pasted AutoEQ",
            gains: gains.compactMap { $0 },
            preampDB: preampDB,
            kind: .autoEQ
        )
    }

    private static func firstNumber(in text: String) -> Double? {
        allNumbers(in: text).first
    }

    private static func allNumbers(in text: String) -> [Double] {
        let pattern = #"[-+]?\d+(?:[.,]\d+)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return Double(text[swiftRange].replacingOccurrences(of: ",", with: "."))
        }
    }

    private static func labeledNumber(after label: String, in text: String) -> Double? {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        let pattern = #"(?i)\b"# + escaped + #"\s*[:=]?\s*([-+]?\d+(?:[.,]\d+)?)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let searchRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: searchRange),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[valueRange].replacingOccurrences(of: ",", with: "."))
    }
}

@MainActor
final class EqualizerProfileStore: ObservableObject {
    static let shared = EqualizerProfileStore()

    @Published private(set) var userProfiles: [EqualizerProfile] = []
    @Published private(set) var selectedProfileID: String?
    @Published private(set) var routeAssignments: [String: String] = [:]
    @Published private(set) var routeNames: [String: String] = [:]
    @Published var automaticallyApplyDeviceProfile: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyApplyDeviceProfile, forKey: Self.autoApplyKey)
            if automaticallyApplyDeviceProfile { applyProfileForCurrentRoute() }
        }
    }

    private static let profilesKey = "equalizerProfiles"
    private static let selectedProfileKey = "selectedEqualizerProfileID"
    private static let routeAssignmentsKey = "equalizerRouteAssignments"
    private static let routeNamesKey = "equalizerRouteNames"
    private static let autoApplyKey = "equalizerAutoApplyDeviceProfile"
    private var routeObserver: NSObjectProtocol?

    static let builtInProfiles: [EqualizerProfile] = [
        EqualizerProfile(id: "flat", name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], kind: .builtIn),
        EqualizerProfile(id: "bass-boost", name: "Bass Boost", gains: [9, 7, 5, 3, 1, 0, 0, 0, 0, 0], kind: .builtIn),
        EqualizerProfile(id: "treble-boost", name: "Treble Boost", gains: [0, 0, 0, 0, 0, 1, 3, 5, 7, 8], kind: .builtIn),
        EqualizerProfile(id: "vocal", name: "Vocal", gains: [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1], kind: .builtIn),
        EqualizerProfile(id: "loudness", name: "Loudness", gains: [6, 4, 1, 0, -1, 0, 1, 3, 5, 6], kind: .builtIn),
        EqualizerProfile(id: "acoustic", name: "Acoustic", gains: [4, 3, 2, 0, 1, 1, 3, 3, 2, 1], kind: .builtIn),
    ]

    var profiles: [EqualizerProfile] {
        userProfiles.sorted { $0.createdAt > $1.createdAt } + Self.builtInProfiles
    }

    var selectedProfile: EqualizerProfile? {
        selectedProfileID.flatMap(profile(id:))
    }

    var deviceProfileAssignments: [EqualizerDeviceProfileAssignment] {
        routeAssignments.compactMap { routeKey, profileID in
            guard let profile = profile(id: profileID) else { return nil }
            let savedName = routeNames[routeKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return EqualizerDeviceProfileAssignment(
                routeKey: routeKey,
                deviceName: savedName.isEmpty ? "Audio Device" : savedName,
                profile: profile
            )
        }
        .sorted { $0.deviceName.localizedCaseInsensitiveCompare($1.deviceName) == .orderedAscending }
    }

    private init() {
        automaticallyApplyDeviceProfile = UserDefaults.standard.object(forKey: Self.autoApplyKey) as? Bool ?? true
        reload()
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyProfileForCurrentRoute() }
        }
        applyProfileForCurrentRoute()
    }

    deinit {
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    }

    func profile(id: String) -> EqualizerProfile? {
        profiles.first { $0.id == id }
    }

    func saveProfile(
        name: String,
        gains: [Double],
        preampDB: Double = 0,
        kind: EqualizerProfileKind = .custom
    ) -> EqualizerProfile? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let profile = EqualizerProfile(
            name: uniqueName(for: trimmed),
            gains: gains,
            preampDB: preampDB,
            kind: kind
        )
        userProfiles.append(profile)
        save()
        return profile
    }

    func delete(_ profile: EqualizerProfile) {
        guard profile.kind != .builtIn else { return }
        userProfiles.removeAll { $0.id == profile.id }
        if selectedProfileID == profile.id { selectedProfileID = nil }
        routeAssignments = routeAssignments.filter { $0.value != profile.id }
        routeNames = routeNames.filter { routeAssignments[$0.key] != nil }
        save()
    }

    func apply(_ profile: EqualizerProfile, enablingEqualizer: Bool = true) {
        EqualizerEngine.shared.setAll(profile.gains, preampDB: profile.preampDB)
        selectedProfileID = profile.id
        if enablingEqualizer { UserDefaults.standard.set(true, forKey: "equalizerEnabled") }
        UserDefaults.standard.set(selectedProfileID, forKey: Self.selectedProfileKey)
        NotificationCenter.default.post(name: .equalizerToggled, object: nil)
    }

    func noteManualAdjustment() {
        guard selectedProfileID != nil else { return }
        selectedProfileID = nil
        UserDefaults.standard.removeObject(forKey: Self.selectedProfileKey)
    }

    func assign(_ profile: EqualizerProfile?, toCurrentRoute: Bool = true) {
        guard toCurrentRoute, let routeKey = currentRouteKey else { return }
        if let profile {
            routeAssignments[routeKey] = profile.id
            routeNames[routeKey] = currentRouteName()
        } else {
            routeAssignments.removeValue(forKey: routeKey)
            routeNames.removeValue(forKey: routeKey)
        }
        save()
    }

    func removeDeviceProfileAssignment(for routeKey: String) {
        routeAssignments.removeValue(forKey: routeKey)
        routeNames.removeValue(forKey: routeKey)
        save()
    }

    func assignedProfileForCurrentRoute() -> EqualizerProfile? {
        guard let routeKey = currentRouteKey,
              let profileID = routeAssignments[routeKey] else { return nil }
        return profile(id: profileID)
    }

    func currentRouteName() -> String {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "This Device"
    }

    func applyProfileForCurrentRoute() {
        guard automaticallyApplyDeviceProfile,
              let profile = assignedProfileForCurrentRoute() else { return }
        apply(profile)
    }

    private var currentRouteKey: String? {
        AVAudioSession.sharedInstance().currentRoute.outputs.first?.uid.nonBlank
    }

    private func reload() {
        if let data = UserDefaults.standard.data(forKey: Self.profilesKey),
           let decoded = try? JSONDecoder().decode([EqualizerProfile].self, from: data) {
            userProfiles = decoded.filter { $0.kind != .builtIn }
        }
        selectedProfileID = UserDefaults.standard.string(forKey: Self.selectedProfileKey)
        routeAssignments = UserDefaults.standard.dictionary(forKey: Self.routeAssignmentsKey) as? [String: String] ?? [:]
        routeNames = UserDefaults.standard.dictionary(forKey: Self.routeNamesKey) as? [String: String] ?? [:]
    }

    private func save() {
        if let data = try? JSONEncoder().encode(userProfiles) {
            UserDefaults.standard.set(data, forKey: Self.profilesKey)
        }
        UserDefaults.standard.set(routeAssignments, forKey: Self.routeAssignmentsKey)
        UserDefaults.standard.set(routeNames, forKey: Self.routeNamesKey)
        if let selectedProfileID {
            UserDefaults.standard.set(selectedProfileID, forKey: Self.selectedProfileKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedProfileKey)
        }
    }

    private func uniqueName(for base: String) -> String {
        let names = Set(profiles.map { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) })
        guard names.contains(base.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)) else { return base }
        for index in 2...99 {
            let candidate = "\(base) \(index)"
            if !names.contains(candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)) {
                return candidate
            }
        }
        return "\(base) \(Date().formatted(date: .numeric, time: .shortened))"
    }
}
