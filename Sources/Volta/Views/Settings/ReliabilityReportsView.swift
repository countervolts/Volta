import SwiftUI

struct ReliabilityReportsView: View {
    @State private var reports: [ReliabilityReport] = []
    @State private var clearKind: ReliabilityReportKind?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                overviewSection
                reportSection(.crash)
                reportSection(.hang)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Hangs & Crashes")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { GlassBackButton() }
        }
        .preferredColorScheme(Theme.colorScheme)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .reliabilityReportsChanged)) { _ in
            reload()
        }
        .alert(
            "Clear \(clearKind?.title ?? "") reports?",
            isPresented: Binding(
                get: { clearKind != nil },
                set: { if !$0 { clearKind = nil } }
            ),
            presenting: clearKind
        ) { kind in
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                CrashHangReportStore.shared.deleteAll(kind: kind)
                clearKind = nil
                reload()
            }
        } message: { kind in
            Text("This removes the saved \(kind.rawValue) reports from this device.")
        }
    }

    private var overviewSection: some View {
        Section {
            LabeledContent("Crash Reports") {
                Text("\(reports(for: .crash).count) / \(CrashHangReportStore.maxReportsPerKind)")
                    .foregroundStyle(Theme.secondaryText)
            }
            LabeledContent("Hang Reports") {
                Text("\(reports(for: .hang).count) / \(CrashHangReportStore.maxReportsPerKind)")
                    .foregroundStyle(Theme.secondaryText)
            }
        } header: {
            Text("Local Reports")
        } footer: {
            Text("Reports remain on this device until you tap Send. Volta keeps the latest five crashes and five hangs; foreground hangs shorter than 250 ms are ignored.")
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    @ViewBuilder
    private func reportSection(_ kind: ReliabilityReportKind) -> some View {
        let kindReports = reports(for: kind)
        Section {
            if kindReports.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: kind == .crash ? "checkmark.shield" : "checkmark.circle")
                        .font(.title3)
                    Text("No \(kind.title.lowercased()) saved")
                        .font(.subheadline.weight(.semibold))
                    Text(emptyMessage(for: kind))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(kindReports) { report in
                    ReliabilityReportRow(
                        report: report,
                        send: { ShareSheet.present([report.url]) },
                        delete: {
                            CrashHangReportStore.shared.delete(report)
                            reload()
                        }
                    )
                }

                Button(role: .destructive) {
                    clearKind = kind
                } label: {
                    Label("Clear \(kind.title)", systemImage: "trash")
                }
            }
        } header: {
            Text(kind.title)
        } footer: {
            Text(kind == .crash
                ? "Crash reports are shared as .ips files. A local interrupted-session report is saved immediately on the next launch; iOS can later add a detailed MetricKit report."
                : "Hang reports are shared as .txt files and show the recorded main-thread stall duration.")
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    private func reports(for kind: ReliabilityReportKind) -> [ReliabilityReport] {
        reports.filter { $0.kind == kind }
    }

    private func emptyMessage(for kind: ReliabilityReportKind) -> String {
        switch kind {
        case .crash:
            return "New crash reports will appear here after Volta launches again."
        case .hang:
            return "A foreground main-thread stall of 250 ms or longer will appear here."
        }
    }

    private func reload() {
        reports = CrashHangReportStore.shared.reports()
    }
}

private struct ReliabilityReportRow: View {
    let report: ReliabilityReport
    let send: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(report.kind.singularTitle, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text(report.sizeDescription)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }

            Text(report.occurredAt.formatted(date: .abbreviated, time: .standard))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            HStack(spacing: 8) {
                if let duration = report.durationDescription {
                    Label(duration, systemImage: "stopwatch")
                }
                if let source = report.source {
                    Text(source)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)

            if report.kind == .crash,
               let crashType = report.crashType,
               let crashCause = report.crashCause {
                VStack(alignment: .leading, spacing: 3) {
                    Label(crashType, systemImage: "bolt.trianglebadge.exclamationmark")
                        .font(.caption.weight(.semibold))
                    Text(crashCause)
                        .font(.caption2)
                        .lineLimit(2)
                }
                .foregroundStyle(Theme.secondaryText)
            }

            HStack(spacing: 10) {
                Button(action: send) {
                    Label("Send", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)

                Button(role: .destructive, action: delete) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 4)
    }

    private var symbol: String {
        switch report.kind {
        case .crash: return "xmark.octagon.fill"
        case .hang: return "pause.circle.fill"
        }
    }
}
