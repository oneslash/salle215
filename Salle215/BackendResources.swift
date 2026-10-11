import Foundation
import Observation

enum SearchScope: String, CaseIterable, Identifiable {
    case name, traceID, sessionID, userID, input, output, error
    var id: Self { self }
    var title: String {
        switch self { case .name: "Step name"; case .traceID: "Trace ID"; case .sessionID: "Session ID"; case .userID: "User ID"; case .input: "Input text"; case .output: "Output text"; case .error: "Error text" }
    }
    var column: String {
        switch self { case .name: "name"; case .traceID: "traceId"; case .sessionID: "sessionId"; case .userID: "userId"; case .input: "input"; case .output: "output"; case .error: "statusMessage" }
    }
}
struct ObservationSearch: Sendable {
    let scope: SearchScope
    let text: String
    var filter: [String: JSONValue] {
        let op = switch scope { case .traceID, .sessionID, .userID: "="; case .input, .output: "matches"; default: "contains" }
        return ["column": .string(scope.column), "type": .string("string"), "operator": .string(op), "value": .string(text)]
    }
}
struct PromptMetadata: Decodable, Identifiable, Sendable {
    let name: String
    let type: String
    let versions: [Int]
    let labels: [String]
    let lastUpdatedAt: String
    var id: String { name }
}
struct PromptPage: Decodable, Sendable {
    struct Meta: Decodable, Sendable { let page: Int; let totalPages: Int }
    let data: [PromptMetadata]
    let meta: Meta
}
struct RemotePrompt: Decodable, Sendable {
    let name: String
    let type: String
    let version: Int
    let labels: [String]
    let commitMessage: String?
    let prompt: JSONValue
    var content: MessageContent {
        if let text = prompt.string { return .text(text) }
        if case .array(let messages) = prompt {
            return .messages(messages.map { message in
                if case .object(let values) = message {
                    if let name = values["name"]?.string { return ChatMessage(role: "placeholder", content: "{{\(name)}}") }
                    return ChatMessage(role: values["role"]?.string ?? "message", content: values["content"]?.string ?? "")
                }
                return ChatMessage(role: "message", content: "")
            })
        }
        return .text("Unsupported prompt content")
    }
}
struct RemoteScore: Decodable, Identifiable, Sendable {
    struct Subject: Decodable, Sendable { let kind: String; let id: String; let traceId: String? }
    let id: String
    let name: String
    let dataType: String
    let value: JSONValue
    let comment: String?
    let metadata: [String: JSONValue]?
    let subject: Subject?
    var formatted: String {
        switch value { case .bool(let v): v ? "True" : "False"; case .number(let v): v.formatted(.number.precision(.fractionLength(0...3))); case .string(let v): v; default: "—" }
    }
    var rating: ReviewRating? {
        guard name == LiveBackendStore.reviewName, dataType == "BOOLEAN", subject?.kind == "trace", case .bool(let good) = value else { return nil }
        let reasons: [String] = if case .array(let items) = metadata?["reasons"] { items.compactMap(\.string) } else { [] }
        return .init(score: good ? .good : .needsWork, reasons: reasons, comment: comment ?? "")
    }
}
struct ScorePage: Decodable, Sendable {
    struct Meta: Decodable, Sendable { let cursor: String? }
    let data: [RemoteScore]
    let meta: Meta
}
struct ScoreWrite: Encodable, Sendable {
    let id: String
    let traceId: String
    let name = LiveBackendStore.reviewName
    let value: Int
    let dataType = "BOOLEAN"
    let source = "API"
    let comment: String
    let environment: String?
    let metadata: [String: JSONValue]
}
extension LangfuseClient {
    func prompts(page: Int, name: String? = nil) async throws -> PromptPage {
        var query = [URLQueryItem(name: "page", value: String(page)), .init(name: "limit", value: "50")]
        if let name { query.append(.init(name: "name", value: name)) }
        return try JSONDecoder().decode(PromptPage.self, from: await request(path: ["api", "public", "v2", "prompts"], query: query))
    }
    func prompt(_ name: String, version: Int? = nil, label: String? = nil) async throws -> RemotePrompt {
        var query = [URLQueryItem(name: "resolve", value: "false")]
        if let version { query.append(.init(name: "version", value: String(version))) }
        else if let label { query.append(.init(name: "label", value: label)) }
        return try JSONDecoder().decode(RemotePrompt.self, from: await request(path: ["api", "public", "v2", "prompts", name], query: query))
    }
    func scores(traceID: String) async throws -> [RemoteScore] {
        var rows: [String: RemoteScore] = [:], cursor: String?, seen = Set<String>()
        for _ in 0..<100 {
            try Task.checkCancellation()
            var query: [URLQueryItem] = [.init(name: "traceId", value: traceID), .init(name: "fields", value: "details,subject"), .init(name: "limit", value: "100")]
            if let cursor { query.append(.init(name: "cursor", value: cursor)) }
            if !credentials.environment.isEmpty { query.append(.init(name: "environment", value: credentials.environment)) }
            let page = try JSONDecoder().decode(ScorePage.self, from: await request(path: ["api", "public", "v3", "scores"], query: query))
            page.data.forEach { rows[$0.id] = $0 }
            guard let next = page.meta.cursor else { return rows.values.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name } }
            guard seen.insert(next).inserted else { throw LangfuseError.pagination }
            cursor = next
        }
        throw LangfuseError.pagination
    }
    func writeScore(_ score: ScoreWrite) async throws {
        struct Receipt: Decodable { let id: String }
        let data = try await request(path: ["api", "public", "scores"], method: "POST", body: JSONEncoder().encode(score))
        guard try JSONDecoder().decode(Receipt.self, from: data).id == score.id else { throw LangfuseError.invalidResponse }
    }
    func deleteScore(_ id: String) async throws { _ = try await request(path: ["api", "public", "scores", id], method: "DELETE") }
}

@MainActor @Observable
final class LiveBackendStore {
    nonisolated static let reviewName = "salle215-review-thumbs"
    private(set) var prompts: [PromptMetadata] = []
    private(set) var promptPage = 0
    private(set) var promptHasMore = true
    private(set) var promptLoading = false
    private(set) var promptError: String?
    private(set) var promptRecords: [String: PromptRecord] = [:]
    private(set) var traceScores: [String: [RemoteScore]] = [:]
    private(set) var saving = Set<String>()
    private(set) var ownScores: [String: String] = [:]
    @ObservationIgnored private var client: LangfuseClient?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var scoreTasks: [String: Task<[RemoteScore], Error>] = [:]
    @ObservationIgnored private var scoreDates: [String: Date] = [:]
    @ObservationIgnored private var writeIDs: [String: String] = [:]
    @ObservationIgnored private var promptDate: Date?
    @ObservationIgnored private var deletedScores = Set<String>()
    @ObservationIgnored private var promptListTask: Task<Void, Never>?
    @ObservationIgnored private var promptTasks: [String: Task<PromptRecord, Error>] = [:]
    @ObservationIgnored private var promptGeneration = UUID()
    func configure(_ client: LangfuseClient?) {
        promptListTask?.cancel(); promptListTask = nil
        promptTasks.values.forEach { $0.cancel() }; promptTasks = [:]; promptGeneration = UUID()
        scoreTasks.values.forEach { $0.cancel() }
        scoreTasks = [:]; generation = UUID(); self.client = client
        prompts = []; promptPage = 0; promptHasMore = true; promptLoading = false; promptError = nil
        promptRecords = [:]; traceScores = [:]; scoreDates = [:]; writeIDs = [:]; ownScores = [:]; saving = []; promptDate = nil
        deletedScores = []
    }
    func loadPrompts(refresh: Bool = false, more: Bool = false) async {
        if let promptListTask { await promptListTask.value; return }
        let generation = generation
        let task = Task { await self.fetchPrompts(refresh: refresh, more: more) }
        promptListTask = task
        await task.value
        if generation == self.generation { promptListTask = nil }
    }
    private func fetchPrompts(refresh: Bool, more: Bool) async {
        guard let client, !promptLoading else { return }
        if !refresh && !more && promptDate != nil { return }
        if more && !promptHasMore { return }
        let generation = generation
        promptLoading = true; promptError = nil
        let pageNumber = refresh ? 1 : promptPage + 1
        do {
            let page = try await client.prompts(page: pageNumber)
            try Task.checkCancellation()
            guard generation == self.generation else { return }
            var byName = Dictionary(uniqueKeysWithValues: (refresh ? [] : prompts).map { ($0.name, $0) })
            page.data.forEach { byName[$0.name] = $0 }
            prompts = byName.values.sorted { $0.name < $1.name }
            promptPage = page.meta.page; promptHasMore = page.meta.page < page.meta.totalPages; promptDate = .now
            if refresh {
                promptTasks.values.forEach { $0.cancel() }; promptTasks = [:]
                promptGeneration = UUID(); promptRecords = [:]
            }
        } catch is CancellationError {} catch { if generation == self.generation { promptError = error.localizedDescription } }
        if generation == self.generation { promptLoading = false }
    }
    func loadPrompt(_ name: String, version: Int? = nil) async throws -> PromptRecord {
        let key = "\(name):\(version ?? -1)"
        let revision = promptGeneration
        let task = promptTasks[key] ?? Task { try await self.fetchPrompt(name, version: version) }
        promptTasks[key] = task
        defer { if revision == promptGeneration { promptTasks[key] = nil } }
        let record = try await task.value
        try Task.checkCancellation()
        return record
    }
    private func fetchPrompt(_ name: String, version: Int?) async throws -> PromptRecord {
        guard let client else { throw CancellationError() }
        let generation = generation
        let revision = promptGeneration
        var cached = promptRecords[name]
        if let cached, version == nil || cached.version(version!) != nil { return cached }
        var meta = prompts.first { $0.name == name }
        if meta == nil { meta = try await client.prompts(page: 1, name: name).data.first { $0.name == name } }
        var fetched: [RemotePrompt] = []
        if cached == nil {
            fetched.append(try await client.prompt(name, label: "latest"))
            if meta?.labels.contains("production") == true {
                fetched.append(try await client.prompt(name, label: "production"))
            } else if let previous = meta?.versions.sorted().dropLast().last {
                fetched.append(try await client.prompt(name, version: previous))
            }
        }
        if let version, cached?.version(version) == nil, !fetched.contains(where: { $0.version == version }) {
            fetched.append(try await client.prompt(name, version: version))
        }
        try Task.checkCancellation()
        guard generation == self.generation, revision == promptGeneration else { throw CancellationError() }
        if let meta, !prompts.contains(where: { $0.name == name }) { prompts.append(meta); prompts.sort { $0.name < $1.name } }
        // Merge any version loaded by another window while these requests were in flight.
        cached = promptRecords[name] ?? cached
        var versions = Dictionary(uniqueKeysWithValues: (cached?.versions ?? []).map { ($0.version, $0) })
        var labels = cached?.labels ?? [:]
        for prompt in fetched {
            versions[prompt.version] = .init(version: prompt.version, commitMessage: prompt.commitMessage, prompt: prompt.content)
            prompt.labels.forEach { labels[$0] = prompt.version }
        }
        let record = PromptRecord(name: name, type: meta?.type ?? fetched.first?.type ?? cached?.type ?? "text",
                                  updated: LiveOverviewData.date(meta?.lastUpdatedAt) ?? .now,
                                  versionCount: meta?.versions.count ?? versions.count, labels: labels, versions: versions.values.sorted { $0.version < $1.version })
        promptRecords[name] = record
        return record
    }
    func loadScores(_ traceID: String, refresh: Bool = false) async throws {
        if !refresh, let date = scoreDates[traceID], Date.now.timeIntervalSince(date) < 600 { return }
        guard let client else { throw CancellationError() }
        let generation = generation
        let task = scoreTasks[traceID] ?? Task { try await client.scores(traceID: traceID) }
        scoreTasks[traceID] = task
        defer { if generation == self.generation { scoreTasks[traceID] = nil } }
        let scores = try await task.value
        try Task.checkCancellation()
        guard generation == self.generation else { throw CancellationError() }
        // Score reads can lag ingestion. Keep server-acknowledged local writes until the read catches up.
        let local = (traceScores[traceID] ?? []).filter { ownScores[traceID] == $0.id }
        var byID = Dictionary(uniqueKeysWithValues: scores.filter { !deletedScores.contains($0.id) }.map { ($0.id, $0) })
        local.forEach { if byID[$0.id] == nil { byID[$0.id] = $0 } }
        traceScores[traceID] = byID.values.sorted { $0.id < $1.id }; scoreDates[traceID] = .now
    }
    func rating(_ traceID: String) -> ReviewRating? { traceScores[traceID]?.compactMap(\.rating).first }
    func saveReview(_ traceID: String, good: Bool, reasons: [String] = [], comment: String = "") async throws {
        guard let client else { throw CancellationError() }
        guard !saving.contains(traceID) else { throw ReviewError.busy }
        guard rating(traceID) == nil else { throw ReviewError.alreadyReviewed }
        let generation = generation
        saving.insert(traceID)
        defer { if generation == self.generation { saving.remove(traceID) } }
        // Retain the ID across failed/ambiguous requests, so Retry upserts a single score.
        let id = writeIDs[traceID] ?? UUID().uuidString
        writeIDs[traceID] = id
        let metadata: [String: JSONValue] = ["app": .string("Salle 215"), "reasons": .array(reasons.map(JSONValue.string))]
        let score = ScoreWrite(id: id, traceId: traceID, value: good ? 1 : 0, comment: comment.trimmingCharacters(in: .whitespacesAndNewlines), environment: client.credentials.environment.isEmpty ? nil : client.credentials.environment, metadata: metadata)
        try await client.writeScore(score)
        guard generation == self.generation else { throw CancellationError() }
        ownScores[traceID] = id
        let remote = RemoteScore(id: id, name: Self.reviewName, dataType: "BOOLEAN", value: .bool(good), comment: score.comment, metadata: metadata, subject: .init(kind: "trace", id: traceID, traceId: nil))
        traceScores[traceID, default: []].removeAll { $0.id == id }
        traceScores[traceID, default: []].append(remote)
    }
    func undoReview(_ traceID: String) async throws {
        guard let client else { throw CancellationError() }
        guard let id = ownScores[traceID], !saving.contains(traceID) else { throw ReviewError.busy }
        let generation = generation
        saving.insert(traceID)
        defer { if generation == self.generation { saving.remove(traceID) } }
        try await client.deleteScore(id)
        guard generation == self.generation else { throw CancellationError() }
        traceScores[traceID]?.removeAll { $0.id == id }
        deletedScores.insert(id)
        ownScores[traceID] = nil; writeIDs[traceID] = nil
        // Cache avoids briefly resurrecting a just-deleted score from the delayed read API.
        scoreDates[traceID] = .now
    }
}
enum ReviewError: LocalizedError {
    case busy, alreadyReviewed
    var errorDescription: String? { switch self { case .busy: "This review is already being saved. Try again when it finishes."; case .alreadyReviewed: "This trace already has a Salle 215 review. Your draft was not saved." } }
}
