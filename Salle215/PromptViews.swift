import SwiftUI

struct PromptDiffBlock: Identifiable {
    let role: String
    let lines: [PromptDiffLine]
    var id: String { role }
    var unchanged: Bool { lines.allSatisfy { $0.kind == .same } }
}
struct PromptDiffLine: Identifiable {
    enum Kind { case same, added, removed }
    let id: Int
    let kind: Kind
    let text: String
}

extension PromptRecord {
    var diff: [PromptDiffBlock] {
        guard let comparison else { return [] }
        let before = version(comparison.from)?.prompt.messages ?? []
        let after = version(comparison.to)?.prompt.messages ?? []
        func blocks(_ messages: [ChatMessage]) -> [(key: String, content: String)] {
            var counts: [String: Int] = [:]
            return messages.map { message in
                counts[message.role, default: 0] += 1
                let number = counts[message.role]!
                return (number == 1 ? message.role : "\(message.role) · message \(number)", message.content)
            }
        }
        let previous = blocks(before), current = blocks(after)
        let roles = (previous + current).reduce(into: [String]()) { roles, message in
            if !roles.contains(message.key) { roles.append(message.key) }
        }
        return roles.map { role in
            let a = Self.sentences(previous.first { $0.key == role }?.content ?? "")
            let b = Self.sentences(current.first { $0.key == role }?.content ?? "")
            return PromptDiffBlock(role: role, lines: Self.diffLines(a, b))
        }
    }
    var addedCount: Int { diff.flatMap(\.lines).filter { $0.kind == .added }.count }
    var removedCount: Int { diff.flatMap(\.lines).filter { $0.kind == .removed }.count }

    private static func sentences(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).flatMap { line in
            line.matches(of: /[^.!?]+[.!?]?/).map { String($0.output).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }
    private static func diffLines(_ a: [String], _ b: [String]) -> [PromptDiffLine] {
        // Long real prompts should not allocate a quadratic matrix on the UI thread.
        // Retain shared edges and show the intervening region as a replacement.
        if a.count > 0 && b.count > 1_000_000 / a.count {
            var prefix = 0, suffix = 0
            while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
            while suffix < min(a.count, b.count) - prefix, a[a.count - suffix - 1] == b[b.count - suffix - 1] { suffix += 1 }
            let rows: [(PromptDiffLine.Kind, String)] = a.prefix(prefix).map { (.same, $0) }
                + a[prefix..<(a.count - suffix)].map { (.removed, $0) }
                + b[prefix..<(b.count - suffix)].map { (.added, $0) }
                + a.suffix(suffix).map { (.same, $0) }
            return rows.enumerated().map { .init(id: $0.offset, kind: $0.element.0, text: $0.element.1) }
        }
        var lengths = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in a.indices.reversed() {
            for j in b.indices.reversed() {
                lengths[i][j] = a[i] == b[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var output: [PromptDiffLine] = []
        var i = 0, j = 0
        func append(_ kind: PromptDiffLine.Kind, _ text: String) { output.append(.init(id: output.count, kind: kind, text: text)) }
        while i < a.count && j < b.count {
            if a[i] == b[j] { append(.same, a[i]); i += 1; j += 1 }
            else if lengths[i + 1][j] >= lengths[i][j + 1] { append(.removed, a[i]); i += 1 }
            else { append(.added, b[j]); j += 1 }
        }
        while i < a.count { append(.removed, a[i]); i += 1 }
        while j < b.count { append(.added, b[j]); j += 1 }
        return output
    }
}

struct PromptsView: View {
    @Environment(AppStore.self) private var store
    private var latestChange: PromptRecord? {
        store.data.prompts.filter { $0.comparison != nil }.max { $0.updated < $1.updated }
    }
    private var folders: [(name: String, prompts: [PromptRecord])] {
        Dictionary(grouping: store.data.prompts) { $0.folder ?? "" }
            .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.name < $1.name }
    }
    var body: some View {
        Screen {
            ScreenTitle(title: "Prompts")
            if let prompt = latestChange, let comparison = prompt.comparison {
                SectionHeading(title: "Latest change")
                NavigationLink(value: AppRoute.changes(prompt.name)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(prompt.shortName).font(.headline)
                            VersionBadge(text: prompt.title(for: comparison.to))
                            Spacer(minLength: 0)
                            Text(prompt.updated, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                                .font(.caption).foregroundStyle(Palette.muted)
                        }
                        if let note = prompt.version(comparison.to)?.commitMessage { Text(note).font(.subheadline) }
                        HStack(spacing: 6) {
                            Text("+\(prompt.addedCount)").foregroundStyle(Palette.green)
                            Text("−\(prompt.removedCount)").foregroundStyle(Palette.red)
                            Text("vs \(prompt.title(for: comparison.from))").foregroundStyle(Palette.muted)
                            Spacer(minLength: 0)
                            Chevron()
                        }.font(.caption)
                    }.padding(16).card(.rect(cornerRadius: 24))
                }.buttonStyle(.plain).accessibilityIdentifier("latestChange")
            }
            ForEach(folders, id: \.name) { folder in
                SectionHeading(title: folder.name.isEmpty ? "Prompts" : folder.name.capitalized)
                SurfaceGroup {
                    ForEach(folder.prompts) { prompt in
                        if prompt.id != folder.prompts.first?.id { RowDivider() }
                        NavigationLink(value: AppRoute.prompt(prompt.name)) {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(prompt.shortName).font(.headline)
                                    Text("\(prompt.type.capitalized) · \(prompt.versionCount) versions").font(.subheadline).foregroundStyle(Palette.muted)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                VersionBadge(text: prompt.title(for: prompt.production ?? prompt.latest))
                                Chevron()
                            }.padding(16).contentShape(.rect)
                        }.buttonStyle(.plain).accessibilityIdentifier("prompt-\(prompt.name)")
                    }
                }
            }
        }.navigationBarTitleDisplayMode(.inline)
    }
}

private struct VersionBadge: View {
    let text: String
    var body: some View {
        Text(text).font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Palette.fill, in: .capsule)
    }
}

struct PromptDetailView: View {
    let prompt: PromptRecord
    @State private var version: Int
    init(prompt: PromptRecord, version: Int?) {
        self.prompt = prompt
        _version = State(initialValue: version.flatMap { prompt.version($0)?.version } ?? prompt.production ?? prompt.latest)
    }
    var body: some View {
        Screen {
            ScreenTitle(title: prompt.shortName, subtitle: "\(prompt.type.capitalized) prompt · \(prompt.versionCount) versions")
            Picker("Prompt version", selection: $version) {
                ForEach(prompt.versions.map(\.version).sorted(), id: \.self) { number in
                    Text(prompt.title(for: number)).tag(number)
                }
            }.pickerStyle(.segmented).padding(.top, 18).accessibilityIdentifier("promptVersion")
            if let note = prompt.version(version)?.commitMessage {
                Text(note).font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 10)
            }
            SectionHeading(title: "Messages")
            ContentBlocks(content: prompt.version(version)?.prompt)
            if let comparison = prompt.comparison {
                SurfaceGroup {
                    NavigationLink(value: AppRoute.changes(prompt.name)) {
                        RelatedRow(title: "Compare v\(comparison.from) → v\(comparison.to)",
                                   detail: "\(prompt.addedCount + prompt.removedCount) changed lines", symbol: "arrow.left.arrow.right")
                    }.buttonStyle(.plain).accessibilityIdentifier("comparePrompt")
                }.padding(.top, 24)
            }
        }.navigationTitle(prompt.shortName).navigationBarTitleDisplayMode(.inline)
    }
}

struct PromptChangesView: View {
    let prompt: PromptRecord
    var body: some View {
        Screen {
            if let comparison = prompt.comparison {
                ScreenTitle(title: "v\(comparison.from) → v\(comparison.to)")
            }
            HStack(spacing: 6) {
                Text(prompt.shortName).foregroundStyle(Palette.muted)
                Text("· \(prompt.addedCount) added").foregroundStyle(Palette.green)
                Text("· \(prompt.removedCount) removed").foregroundStyle(Palette.red)
            }.font(.subheadline).padding(.top, 5)
            ForEach(prompt.diff) { block in
                VStack(alignment: .leading, spacing: 0) {
                    if block.unchanged {
                        Text("\(block.role.capitalized) message unchanged").font(.subheadline).foregroundStyle(Palette.muted).padding(16)
                    } else {
                        Text(block.role.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Palette.muted).padding(16)
                        ForEach(block.lines) { line in
                            HStack(alignment: .top, spacing: 10) {
                                Text(line.kind == .added ? "+" : line.kind == .removed ? "−" : " ")
                                    .font(.system(.body, design: .monospaced)).frame(width: 14)
                                Text(line.text).font(.subheadline).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .foregroundStyle(line.kind == .added ? Palette.green : line.kind == .removed ? Palette.red : Palette.ink)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(line.kind == .added ? Palette.greenFill : line.kind == .removed ? Palette.redFill : Palette.surface)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(line.kind == .added ? "Added" : line.kind == .removed ? "Removed" : "Unchanged"): \(line.text)")
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface).compositingGroup().clipShape(.rect(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.line)).padding(.top, 20)
            }
        }.navigationTitle("Changes").navigationBarTitleDisplayMode(.inline)
    }
}
