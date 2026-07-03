import Foundation
import Darwin
import UIKit

enum AppDiagnostics {
    static func logLaunch(context: String = "launch") {
        AppLogger.shared.logAlways(diagnosticsLine(context: context), category: .other)
    }

    static func logMainTabDecision() {
        AppLogger.shared.logAlways(tabDecisionLine(), category: .other)
    }

    private static func diagnosticsLine(context: String) -> String {
        let device = UIDevice.current
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let bundleID = Bundle.main.bundleIdentifier ?? "?"
        let display = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "?"

        return [
            "Diagnostics[\(context)]",
            "app=\(display)",
            "bundle=\(bundleID)",
            "version=\(version)",
            "build=\(build)",
            "deviceName=\(device.name)",
            "model=\(device.model)",
            "localizedModel=\(device.localizedModel)",
            "machine=\(machineIdentifier())",
            "uideviceOS=\(device.systemName) \(device.systemVersion)",
            "processOS=\(ProcessInfo.processInfo.operatingSystemVersionString)",
            "ios26=\(availability26())",
            "ios261=\(availability261())",
            "reduceTransparency=\(UIAccessibility.isReduceTransparencyEnabled)",
            "reduceMotion=\(UIAccessibility.isReduceMotionEnabled)",
            "darkerColors=\(UIAccessibility.isDarkerSystemColorsEnabled)"
        ].joined(separator: "; ")
    }

    private static func tabDecisionLine() -> String {
        [
            "TabDecision",
            "shell=\(availability26() ? "modern-iOS26" : "legacy-fallback")",
            "mini=\(availability26() ? "tabViewBottomAccessory" : "safeAreaInset")",
            "ios26=\(availability26())",
            "ios261=\(availability261())",
            "systemVersion=\(UIDevice.current.systemVersion)",
            "machine=\(machineIdentifier())",
            "reduceTransparency=\(UIAccessibility.isReduceTransparencyEnabled)"
        ].joined(separator: "; ")
    }

    private static func availability26() -> Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    private static func availability261() -> Bool {
        if #available(iOS 26.1, *) { return true }
        return false
    }

    private static func machineIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "?"
            }
        }
    }
}
