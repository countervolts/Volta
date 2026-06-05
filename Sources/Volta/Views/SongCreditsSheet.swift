import SwiftUI

// "View Credits" — shows only data about how the song was *made*: performing
// artists, writing, and production/engineering. Technical/playback fields live
// in the separate Info sheet.
struct SongCreditsSheet: View {
    let song: Song?
    @Environment(\.dismiss) private var dismiss

    // deduped by role+name (servers sometimes repeat a credit)
    private var contributors: [Contributor] {
        var seen = Set<String>()
        return (song?.contributors ?? []).filter {
            let key = ($0.role ?? "").lowercased() + "|" + ($0.artist?.name ?? "").lowercased()
            return seen.insert(key).inserted
        }
    }

    private func contributors(in bucket: RoleBucket) -> [Contributor] {
        contributors.filter { RoleBucket.classify($0.role) == bucket }
    }

    var body: some View {
        NavigationStack {
            List {
                if let song {
                    Section("Performance") {
                        creditRow("Artist", song.artist)
                        if let feat = song.contributes, !feat.isEmpty {
                            creditRow("Featured", feat)
                        }
                        ForEach(Array(contributors(in: .performance).enumerated()), id: \.offset) { _, c in
                            creditRow(roleLabel(c), c.artist?.name)
                        }
                    }

                    // when displayComposer is present it's the canonical composer
                    // list, so drop composer-role contributors to avoid showing the
                    // composer twice.
                    let writing = contributors(in: .writing).filter {
                        !(song.displayComposer != nil && (($0.role ?? "").lowercased().contains("composer")))
                    }
                    if song.displayComposer != nil || !writing.isEmpty {
                        Section("Writing") {
                            creditRow("Composer", song.displayComposer)
                            ForEach(Array(writing.enumerated()), id: \.offset) { _, c in
                                creditRow(roleLabel(c), c.artist?.name)
                            }
                        }
                    }

                    let production = contributors(in: .production)
                    if !production.isEmpty {
                        Section("Production & Engineering") {
                            ForEach(Array(production.enumerated()), id: \.offset) { _, c in
                                creditRow(roleLabel(c), c.artist?.name)
                            }
                        }
                    }

                    if contributors.isEmpty && song.displayComposer == nil {
                        Section {
                            Text("No additional credits provided by the server.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder
    private func creditRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty { LabeledContent(label, value: value) }
    }

    private func roleLabel(_ c: Contributor) -> String {
        let role = (c.role ?? "Credit").replacingOccurrences(of: "_", with: " ").capitalized
        if let sub = c.subRole, !sub.isEmpty { return "\(role) (\(sub))" }
        return role
    }
}

// groups OpenSubsonic contributor roles into creation-related buckets.
private enum RoleBucket {
    case performance, writing, production

    static func classify(_ role: String?) -> RoleBucket {
        let r = (role ?? "").lowercased()
        let writing = ["composer", "lyricist", "writer", "songwriter", "arranger", "author"]
        let production = ["producer", "engineer", "mixer", "mix", "mastering", "master",
                          "recording", "programmer", "remixer", "editor"]
        if writing.contains(where: r.contains) { return .writing }
        if production.contains(where: r.contains) { return .production }
        return .performance
    }
}
