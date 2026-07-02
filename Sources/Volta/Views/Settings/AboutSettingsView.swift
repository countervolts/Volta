import Foundation
import SwiftUI

extension SettingsView {
    // MARK: - About

    @ViewBuilder
    var aboutSection: some View {
        let s = "About"
        if sectionVisible(s, [["app", "version", "build", "volta", "developer", "ayo", "countervolts", "source code", "github", "repository"], ["changelog", "changes", "commits", "history", "release notes", "git"]]) {
            Section(sectionTitle(s)) {
                LabeledContent("App", value: "Volta")
                    .foregroundStyle(Theme.primaryText)
                LabeledContent("Developer", value: "ayo/countervolts")
                    .foregroundStyle(Theme.primaryText)
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    LabeledContent("Version", value: version)
                        .foregroundStyle(Theme.primaryText)
                        .contentShape(Rectangle())
                        .onTapGesture { registerSecretDeveloperTap() }
                }
                if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    LabeledContent("Build", value: build)
                        .foregroundStyle(Theme.primaryText)
                        .contentShape(Rectangle())
                        .onTapGesture { registerSecretDeveloperTap() }
                }
                Button {
                    openURL(AboutSettingsData.sourceCodeURL)
                } label: {
                    HStack {
                        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                        Spacer()
                        Text("GitHub")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .foregroundStyle(Theme.primaryText)

                NavigationLink(value: SettingsRoute.changelog) {
                    Label("Changelog", systemImage: "clock.arrow.circlepath")
                }
                .foregroundStyle(Theme.primaryText)
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }
}

private struct ChangelogEntry: Identifiable {
    let hash: String
    let title: String
    let changes: [String]

    var id: String { hash }
}

private enum AboutSettingsData {
    static let sourceCodeURL = URL(string: "https://github.com/countervolts/Volta")!
    static let commitsAPIURL = URL(string: "https://api.github.com/repos/countervolts/Volta/commits")!
}

struct ChangelogSettingsView: View {
    @State private var entries: [ChangelogEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section("Commits") {
                    if isLoading && entries.isEmpty {
                        HStack {
                            Label("Loading Changelog", systemImage: "arrow.down.circle")
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.accent)
                        }
                        .foregroundStyle(Theme.primaryText)
                    } else if let errorMessage, entries.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Could not load changelog")
                                .foregroundStyle(Theme.primaryText)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                            Button {
                                Task { await loadChangelog(force: true) }
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                            .foregroundStyle(Theme.primaryText)
                        }
                    } else if entries.isEmpty {
                        Text("No commits found")
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(entries) { entry in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(entry.changes.indices, id: \.self) { index in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "circle.fill")
                                                .font(.system(size: 4, weight: .bold))
                                                .foregroundStyle(Theme.accent)
                                                .padding(.top, 7)
                                            Text(entry.changes[index])
                                                .font(.footnote)
                                                .foregroundStyle(Theme.secondaryText)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .foregroundStyle(Theme.primaryText)
                                        .lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(entry.hash)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                            .tint(Theme.accent)
                            .foregroundStyle(Theme.primaryText)
                        }
                    }
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        }
        .navigationTitle("Changelog")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                GlassBackButton()
            }
        }
        .preferredColorScheme(Theme.colorScheme)
        .task {
            await loadChangelog()
        }
    }

    @MainActor
    private func loadChangelog(force: Bool = false) async {
        guard force || (entries.isEmpty && !isLoading) else { return }
        isLoading = true
        errorMessage = nil
        do {
            entries = try await GitHubChangelogFetcher.fetchCommits()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private enum GitHubChangelogFetcher {
    static func fetchCommits() async throws -> [ChangelogEntry] {
        var commits: [GitHubCommitResponse] = []
        var page = 1

        while page <= 10 {
            let pageCommits = try await fetchPage(page)
            commits.append(contentsOf: pageCommits)
            if pageCommits.count < 100 { break }
            page += 1
        }

        return commits.map { response in
            let message = response.commit.message
            let title = title(from: message, fallback: response.shortHash)
            return ChangelogEntry(
                hash: response.shortHash,
                title: title,
                changes: changes(from: message, title: title)
            )
        }
    }

    private static func fetchPage(_ page: Int) async throws -> [GitHubCommitResponse] {
        var components = URLComponents(url: AboutSettingsData.commitsAPIURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "page", value: "\(page)"),
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Volta-iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([GitHubCommitResponse].self, from: data)
    }

    private static func title(from message: String, fallback: String) -> String {
        let rawTitle = message
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? fallback
        return stripBulletPrefix(rawTitle)
    }

    private static func changes(from message: String, title: String) -> [String] {
        let lines = message.components(separatedBy: .newlines)
        var parsed: [String] = []
        var currentBullet: String?

        for rawLine in lines.dropFirst() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if let currentBullet {
                    parsed.append(currentBullet)
                }
                currentBullet = stripBulletPrefix(trimmed)
            } else if currentBullet != nil && rawLine.first?.isWhitespace == true {
                currentBullet = [currentBullet, trimmed].compactMap { $0 }.joined(separator: " ")
            }
        }

        if let currentBullet {
            parsed.append(currentBullet)
        }

        if !parsed.isEmpty {
            return parsed
        }

        return fallbackChanges(from: title)
    }

    private static func fallbackChanges(from title: String) -> [String] {
        let dashParts = title
            .components(separatedBy: " - ")
            .map { stripBulletPrefix($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        if dashParts.count > 1 {
            return dashParts
        }

        let commaParts = title
            .components(separatedBy: ", ")
            .map { stripBulletPrefix($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        if commaParts.count > 1 {
            return commaParts
        }

        return [title]
    }

    private static func stripBulletPrefix(_ value: String) -> String {
        if value.hasPrefix("- ") || value.hasPrefix("* ") {
            return String(value.dropFirst(2))
        }
        return value
    }
}

private struct GitHubCommitResponse: Decodable {
    let sha: String
    let commit: GitHubCommit

    var shortHash: String { String(sha.prefix(7)) }
}

private struct GitHubCommit: Decodable {
    let message: String
}
