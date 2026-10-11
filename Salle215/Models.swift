import Foundation
import Observation

enum AppTab: Hashable { case overview, traces, review, prompts, search }
enum AppRoute: Hashable {
    case trace(String)
    case span(trace: String, id: String)
    case session(String)
    case prompt(String, version: Int? = nil)
    case changes(String)
}
enum TimeRange: CaseIterable, Identifiable {
    case hour, day, week
    var id: Self { self }
    var title: String {
        switch self { case .hour: "1H"; case .day: "24H"; case .week: "7D" }
    }
    var label: String {
        switch self { case .hour: "Last hour"; case .day: "Last 24 hours"; case .week: "Last 7 days" }
    }
    var start: Date {
        let seconds: TimeInterval = switch self { case .hour: 3_600; case .day: 86_400; case .week: 604_800 }
        return .now.addingTimeInterval(-seconds)
    }
}
struct PerRange<Value: Decodable>: Decodable {
    let hour: Value
    let day: Value
    let week: Value
    subscript(range: TimeRange) -> Value {
        switch range { case .hour: hour; case .day: day; case .week: week }
    }
}
enum TraceFilter: String, CaseIterable {
    case all, error, slow
    var title: String {
        switch self { case .all: "All"; case .error: "Errors"; case .slow: "Slow ≥ 5s" }
    }
}
enum TraceStatus {
    case error, slow, ok
    var title: String {
        switch self { case .error: "Error"; case .slow: "Slow"; case .ok: "Success" }
    }
}
enum MetricKind: String, CaseIterable, Identifiable {
    case errors, latency, spend, quality
    var id: String { rawValue }
}
struct MetricValue: Decodable {
    enum Status: String, Decodable { case ok, warn, neutral }
    let value: String
    let status: Status
    let summary: String
    let detail: String
}
struct OverviewSnapshot: Decodable {
    let errors: MetricValue
    let latency: MetricValue
    let spend: MetricValue
    let quality: MetricValue
    let failedSteps: [String: Int]
    let models: [Double]
    let reviews: [Int]
    func value(for kind: MetricKind) -> MetricValue {
        switch kind { case .errors: errors; case .latency: latency; case .spend: spend; case .quality: quality }
    }
}
struct MetricBand: Decodable { let low: Double; let high: Double }
struct MetricDefinition: Decodable {
    let title: String
    let unit: String
    let cta: String?
    let series: PerRange<[Double]>
    let band: PerRange<MetricBand>
}
struct MetricDefinitions: Decodable {
    let errors: MetricDefinition
    let latency: MetricDefinition
    let spend: MetricDefinition
    let quality: MetricDefinition
    subscript(kind: MetricKind) -> MetricDefinition {
        switch kind { case .errors: errors; case .latency: latency; case .spend: spend; case .quality: quality }
    }
}
struct ChatMessage: Decodable, Hashable { let role: String; let content: String }
// Langfuse inputs and outputs are free-form; this covers plain text and chat transcripts.
enum MessageContent: Decodable, Hashable {
    case text(String)
    case messages([ChatMessage])
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) { self = .text(text) }
        else { self = .messages(try container.decode([ChatMessage].self)) }
    }
    // What a reader looks for first: the text itself, or the latest user turn of a transcript.
    var summary: String {
        switch self {
        case .text(let text): text
        case .messages(let messages): (messages.last { $0.role == "user" } ?? messages.last)?.content ?? ""
        }
    }
    var messages: [ChatMessage] {
        switch self {
        case .text(let text): [ChatMessage(role: "prompt", content: text)]
        case .messages(let messages): messages
        }
    }
}
struct PromptReference: Hashable { let name: String; let version: Int }
struct TraceSpan: Decodable, Hashable, Identifiable {
    enum Kind: String, Decodable { case span, generation, event, agent, tool, chain, retriever, evaluator, embedding, guardrail }
    struct Usage: Decodable, Hashable { let input: Int; let output: Int? }
    let id: String
    let name: String
    let type: Kind
    let depth: Int
    let start: Double
    let end: Double
    let input: MessageContent?
    let output: MessageContent?
    let level: String?
    let statusMessage: String?
    let model: String?
    let usage: Usage?
    let cost: Double?
    let promptName: String?
    let promptVersion: Int?
    var duration: Double { end - start }
    var failed: Bool { level == "ERROR" }
    var prompt: PromptReference? {
        guard let promptName, let promptVersion else { return nil }
        return PromptReference(name: promptName, version: promptVersion)
    }
    var symbol: String {
        switch type {
        case .generation: "sparkles"; case .retriever: "magnifyingglass"; case .tool: "wrench"; case .span: "cube"
        case .event: "smallcircle.filled.circle"; case .agent: "brain"; case .chain: "link"
        case .evaluator: "wand.and.sparkles"; case .embedding: "square.3.layers.3d"; case .guardrail: "checkmark.shield"
        }
    }
}
struct TraceRecord: Hashable, Identifiable {
    static let slowSeconds = 5.0
    let id: String
    let name: String
    let timestamp: Date
    let session: String
    let user: String
    let spans: [TraceSpan]

    // Langfuse v4 has no trace object; the root observation carries the trace's input, output and timing.
    private var root: TraceSpan? { spans.first { $0.depth == 0 } }
    var input: MessageContent? { root?.input }
    var output: MessageContent? { root?.output }
    var duration: Double { root?.duration ?? max(0, (spans.map(\.end).max() ?? 0) - (spans.map(\.start).min() ?? 0)) }
    var cost: Double { spans.compactMap(\.cost).reduce(0, +) }
    var failure: TraceSpan? { spans.first(where: \.failed) }
    var status: TraceStatus { failure != nil ? .error : duration >= Self.slowSeconds ? .slow : .ok }
    var prompt: PromptReference? { spans.lazy.compactMap(\.prompt).first }
    var displayName: String {
        let operation = name.hasPrefix("handle-") ? String(name.dropFirst(7)) : name
        let words = operation.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
    var title: String { input?.summary ?? displayName }
    var searchText: String {
        [id, name, session, user, input?.summary ?? "", output?.summary ?? "", failure?.statusMessage ?? ""].joined(separator: " ")
    }
}
extension TraceRecord: Decodable {
    private enum CodingKeys: String, CodingKey { case id, name, minutesAgo, session, user, spans }
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(String.self, forKey: .id),
                  name: try container.decode(String.self, forKey: .name),
                  timestamp: try container.date(minutesAgo: .minutesAgo),
                  session: try container.decode(String.self, forKey: .session),
                  user: try container.decode(String.self, forKey: .user),
                  spans: try container.decode([TraceSpan].self, forKey: .spans))
    }
}
struct SourceDocument: Decodable, Hashable { let title: String; let excerpt: String }
struct ReviewItem: Decodable, Identifiable {
    private enum CodingKeys: String, CodingKey { case traceID = "traceId", docs }
    let traceID: String
    let docs: [SourceDocument]
    var id: String { traceID }
}
struct PromptVersion: Decodable {
    let version: Int
    let commitMessage: String?
    let prompt: MessageContent
}
struct PromptRecord: Identifiable {
    let name: String
    let type: String
    let updated: Date
    let versionCount: Int
    let labels: [String: Int]
    let versions: [PromptVersion]
    var id: String { name }

    // Langfuse folders are "/"-separated prefixes of the prompt name.
    var folder: String? { name.lastIndex(of: "/").map { String(name[..<$0]) } }
    var shortName: String { name.lastIndex(of: "/").map { String(name[name.index(after: $0)...]) } ?? name }
    var production: Int? { labels["production"] }
    var latest: Int { versions.map(\.version).max() ?? 0 }
    func version(_ number: Int) -> PromptVersion? { versions.first { $0.version == number } }
    // Langfuse keeps "latest" on the newest version itself, so it adds nothing next to the version number.
    func title(for version: Int) -> String {
        let names = labels.filter { $0.value == version && $0.key != "latest" }.keys
            .sorted { $0 == "production" || ($1 != "production" && $0 < $1) }
        return (["v\(version)"] + names).joined(separator: " · ")
    }
    // What production serves against the newest version; without production, the two newest versions.
    var comparison: (from: Int, to: Int)? {
        let numbers = versions.map(\.version).sorted()
        guard let to = numbers.last, let from = production ?? numbers.dropLast().last, from != to else { return nil }
        return (from, to)
    }
}
extension PromptRecord: Decodable {
    private enum CodingKeys: String, CodingKey { case name, type, minutesAgo, versionCount, labels, versions }
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try container.decode(String.self, forKey: .name),
                  type: try container.decode(String.self, forKey: .type),
                  updated: try container.date(minutesAgo: .minutesAgo),
                  versionCount: try container.decode(Int.self, forKey: .versionCount),
                  labels: try container.decode([String: Int].self, forKey: .labels),
                  versions: try container.decode([PromptVersion].self, forKey: .versions))
    }
}
private extension KeyedDecodingContainer {
    // Sample times are stored relative to launch so the data always looks recent.
    func date(minutesAgo key: Key) throws -> Date {
        .now.addingTimeInterval(-60 * (try decode(Double.self, forKey: key)))
    }
}
struct SampleDataset: Decodable {
    let snapshots: PerRange<OverviewSnapshot>
    let metrics: MetricDefinitions
    let traces: [TraceRecord]
    let review: [ReviewItem]
    let prompts: [PromptRecord]

    func trace(_ id: String) -> TraceRecord? { traces.first { $0.id == id } }
    func prompt(_ name: String) -> PromptRecord? { prompts.first { $0.name == name } }

    static func load() -> SampleDataset {
        guard let url = Bundle.main.url(forResource: "SampleData", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let sample = try? JSONDecoder().decode(SampleDataset.self, from: data) else {
            preconditionFailure("The bundled concept sample data is missing or invalid.")
        }
        return sample
    }
}
struct ReviewRating: Codable, Equatable {
    enum Score: String, Codable { case good, needsWork }
    let score: Score
    let reasons: [String]
    let comment: String
}
// A group of failed or slow traces with the same name; opening it shows exactly these traces.
struct AttentionItem: Identifiable, Hashable {
    let filter: TraceFilter
    let name: String
    let count: Int
    let slowest: Double
    var id: String { "\(filter.rawValue)-\(name)" }
}

@MainActor @Observable
final class AppStore {
    var data: SampleDataset
    let metricsStore = LiveMetricsStore()
    let backend = LiveBackendStore()
    @ObservationIgnored private let sampleData: SampleDataset
    @ObservationIgnored private let vault: any ConnectionVault
    @ObservationIgnored private var client: LangfuseClient?
    @ObservationIgnored private var connectionGeneration = UUID()
    @ObservationIgnored private var observationRows: [LangfuseObservation] = []
    @ObservationIgnored private var seenCursors = Set<String>()
    @ObservationIgnored private var loadedDetails: [String: TraceRecord] = [:]
    @ObservationIgnored private var traceTasks: [String: Task<TraceRecord?, Error>] = [:]
    private(set) var isLive = false
    private(set) var isLoading = false
    private(set) var nextCursor: String?
    private(set) var liveFrom = Date.now
    private(set) var liveTo = Date.now
    private(set) var connectionHost = ""
    private(set) var connectionEnvironment = ""
    var knownEnvironments: [String] {
        let current = connectionEnvironment == "All environments" ? [] : [connectionEnvironment]
        return Set(observationRows.compactMap(\.environment) + current).filter { !$0.isEmpty }.sorted()
    }
    var connectionError: String?
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored private let persistsChanges: Bool
    var isConnected: Bool
    var ratings: [String: ReviewRating]

    init(data: SampleDataset = .load(), defaults: UserDefaults = .standard, reset: Bool = false, vault: any ConnectionVault = KeychainConnectionVault()) {
        self.data = data
        self.sampleData = data
        self.vault = vault
        self.defaults = defaults
        persistsChanges = !reset
        isConnected = reset ? false : defaults.bool(forKey: "sampleConnected")
        if !reset, let saved = defaults.data(forKey: "sampleRatings"),
           let decoded = try? JSONDecoder().decode([String: ReviewRating].self, from: saved) {
            ratings = decoded.filter { id, _ in data.review.contains { $0.id == id } }
        } else { ratings = [:] }
    }

    func traces(_ filter: TraceFilter, name: String? = nil, in range: TimeRange) -> [TraceRecord] {
        let start = range.start
        return data.traces.filter { trace in
            guard trace.timestamp >= start, name == nil || trace.name == name else { return false }
            switch filter {
            case .all: return true
            case .error: return trace.status == .error
            case .slow: return trace.duration >= TraceRecord.slowSeconds
            }
        }
    }
    func attention(in range: TimeRange) -> [AttentionItem] {
        [TraceFilter.error, .slow].flatMap { filter in
            Dictionary(grouping: traces(filter, in: range), by: \.name)
                .map { AttentionItem(filter: filter, name: $0.key, count: $0.value.count, slowest: $0.value.map(\.duration).max() ?? 0) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        }
    }
    func search(_ query: String) -> [TraceRecord] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return data.traces.filter { $0.searchText.localizedCaseInsensitiveContains(text) }
    }
    var pendingReviews: Int { data.review.filter { ratings[$0.id] == nil }.count }
    func connectSample() {
        traceTasks.values.forEach { $0.cancel() }; traceTasks = [:]
        connectionGeneration = UUID()
        client = nil
        metricsStore.configure(nil)
        backend.configure(nil)
        isLive = false
        isLoading = false
        connectionError = nil
        data = sampleData
        restoreSampleRatings()
        isConnected = true
        if persistsChanges { defaults.set(true, forKey: "sampleConnected") }
    }
    func disconnect() {
        if isLive && persistsChanges {
            do { try vault.delete() }
            catch { connectionError = "Could not remove the saved connection from Keychain. Try disconnecting again."; return }
        }
        traceTasks.values.forEach { $0.cancel() }; traceTasks = [:]
        connectionGeneration = UUID()
        client = nil
        metricsStore.configure(nil)
        backend.configure(nil)
        isLive = false
        isLoading = false
        nextCursor = nil
        observationRows = []
        loadedDetails = [:]
        data = sampleData
        connectionError = nil
        restoreSampleRatings()
        isConnected = false
        if persistsChanges { defaults.set(false, forKey: "sampleConnected") }
    }
    private func restoreSampleRatings() {
        if persistsChanges, let saved = defaults.data(forKey: "sampleRatings"),
           let decoded = try? JSONDecoder().decode([String: ReviewRating].self, from: saved) {
            ratings = decoded.filter { id, _ in sampleData.review.contains { $0.id == id } }
        } else { ratings = [:] }
    }

    func restoreConnection() async {
        guard persistsChanges, client == nil else { return }
        do {
            if let credentials = try vault.load() { await connect(credentials) }
        } catch { connectionError = "Could not read the saved connection from Keychain. Enter your connection again." }
    }

    func connect(_ credentials: LangfuseCredentials, transport: LangfuseClient.Transport? = nil) async {
        guard !isLoading else { return }
        traceTasks.values.forEach { $0.cancel() }; traceTasks = [:]
        connectionGeneration = UUID()
        let generation = connectionGeneration
        isLoading = true
        connectionError = nil
        let candidate = LangfuseClient(credentials: credentials, transport: transport)
        let to = Date.now, from = to.addingTimeInterval(-604_800)
        do {
            let page = try await candidate.observations(from: from, to: to)
            try Task.checkCancellation()
            guard generation == connectionGeneration else { return }
            if persistsChanges { try vault.save(credentials) }
            client = candidate
            metricsStore.configure(candidate)
            backend.configure(candidate)
            liveFrom = from
            liveTo = to
            observationRows = page.data
            seenCursors = Set(page.meta.cursor.map { [$0] } ?? [])
            nextCursor = page.meta.cursor
            loadedDetails = [:]
            connectionHost = credentials.baseURL.host ?? "Langfuse"
            connectionEnvironment = credentials.environment.isEmpty ? "All environments" : credentials.environment
            isLive = true
            ratings = [:]
            rebuildLiveData()
            isConnected = true
            if persistsChanges { defaults.set(false, forKey: "sampleConnected") }
        } catch is CancellationError {
            // A dismissed connection attempt does not become a saved connection.
        } catch { if !Task.isCancelled && generation == connectionGeneration { connectionError = error.localizedDescription } }
        if generation == connectionGeneration { isLoading = false }
    }

    func refreshObservations() async {
        guard let client, !isLoading else { return }
        let generation = connectionGeneration
        isLoading = true
        connectionError = nil
        defer { if generation == connectionGeneration { isLoading = false } }
        let to = Date.now, from = to.addingTimeInterval(-604_800)
        do {
            let page = try await client.observations(from: from, to: to)
            try Task.checkCancellation()
            guard generation == connectionGeneration else { return }
            traceTasks.values.forEach { $0.cancel() }; traceTasks = [:]
            liveFrom = from
            liveTo = to
            observationRows = page.data
            seenCursors = Set(page.meta.cursor.map { [$0] } ?? [])
            nextCursor = page.meta.cursor
            loadedDetails = [:]
            rebuildLiveData()
        } catch is CancellationError {} catch {
            if generation == connectionGeneration { connectionError = error.localizedDescription }
        }
    }

    func loadMoreObservations() async {
        guard let client, let cursor = nextCursor, !isLoading else { return }
        let generation = connectionGeneration
        isLoading = true
        connectionError = nil
        defer { if generation == connectionGeneration { isLoading = false } }
        do {
            guard seenCursors.count <= 100 else { throw LangfuseError.pagination }
            let page = try await client.observations(from: liveFrom, to: liveTo, cursor: cursor)
            try Task.checkCancellation()
            guard generation == connectionGeneration else { return }
            if let next = page.meta.cursor, !seenCursors.insert(next).inserted { throw LangfuseError.pagination }
            observationRows.append(contentsOf: page.data)
            nextCursor = page.meta.cursor
            rebuildLiveData()
        } catch is CancellationError {} catch {
            if !Task.isCancelled && generation == connectionGeneration { connectionError = error.localizedDescription }
        }
    }

    func loadTrace(_ id: String) async throws {
        guard let client else { return }
        if loadedDetails[id] != nil { return }
        let generation = connectionGeneration
        let from = liveFrom, to = liveTo
        let key = "\(id):\(to.timeIntervalSince1970)"
        let task = traceTasks[key] ?? Task { try await client.trace(id, from: from, to: to) }
        traceTasks[key] = task
        defer { if generation == connectionGeneration { traceTasks[key] = nil } }
        guard let trace = try await task.value else { throw LangfuseError.invalidResponse }
        try Task.checkCancellation()
        guard generation == connectionGeneration, from == liveFrom, to == liveTo else { throw CancellationError() }
        loadedDetails[id] = trace
        rebuildLiveData()
    }

    private func rebuildLiveData() {
        let mapped = ObservationMapper.traces(observationRows)
        let traces = (mapped.map { loadedDetails[$0.id] ?? $0 } + loadedDetails.values.filter { detail in !mapped.contains { $0.id == detail.id } }).sorted { $0.timestamp > $1.timestamp }
        // Live navigation only exposes connected features. No fixture metrics, prompts, or review queue.
        data = SampleDataset(snapshots: sampleData.snapshots, metrics: sampleData.metrics,
                             traces: traces, review: [], prompts: [])
    }

    func observationPage(cursor: String? = nil, sessionID: String? = nil, search: ObservationSearch? = nil,
                         from: Date, to: Date) async throws -> ObservationPage {
        guard let client else { throw CancellationError() }
        let generation = connectionGeneration
        let page = try await client.observations(from: from, to: to, cursor: cursor, sessionID: sessionID, search: search)
        try Task.checkCancellation()
        guard generation == connectionGeneration else { throw CancellationError() }
        return page
    }

    func changeEnvironment(_ environment: String) async {
        guard let current = client?.credentials else { return }
        do {
            let credentials = try LangfuseCredentials(host: current.baseURL.absoluteString, publicKey: current.publicKey,
                                                     secretKey: current.secretKey, environment: environment)
            await connect(credentials)
        } catch { connectionError = error.localizedDescription }
    }

    @discardableResult
    func rate(_ score: ReviewRating.Score, for reviewID: String, reasons: [String] = [], comment: String = "") -> Bool {
        guard data.review.contains(where: { $0.id == reviewID }), ratings[reviewID] == nil else { return false }
        ratings[reviewID] = ReviewRating(score: score, reasons: reasons, comment: comment.trimmingCharacters(in: .whitespacesAndNewlines))
        saveRatings()
        return true
    }
    func removeRating(for reviewID: String) {
        ratings.removeValue(forKey: reviewID)
        saveRatings()
    }
    private func saveRatings() {
        if persistsChanges && !isLive { defaults.set(try? JSONEncoder().encode(ratings), forKey: "sampleRatings") }
    }
}

struct ReviewUndo {
    let message: String
    let itemID: String
    let rated: Bool
}

// Each window owns one, so iPad windows navigate and review independently.
@MainActor @Observable
final class WindowState {
    static let undoSeconds = 5.0
    var tab: AppTab = .overview
    var tracePath: [AppRoute] = []
    var range: TimeRange = .day
    var filter: TraceFilter = .all
    var traceName: String?
    var query = ""
    var reviewPosition = 0
    private(set) var reviewUndo: ReviewUndo?
    @ObservationIgnored private var undoExpiry: Task<Void, Never>?

    func showTraces(_ filter: TraceFilter, name: String? = nil) {
        self.filter = filter
        traceName = name
        tracePath = []
        tab = .traces
    }
    func openMetric(_ metric: MetricKind) {
        switch metric {
        case .errors: showTraces(.error)
        case .latency: showTraces(.slow)
        case .quality: tab = .review
        // Langfuse can't list traces by cost, so the spend sheet's breakdown by model is where it ends.
        case .spend: break
        }
    }

    // The first unrated answer from this window's position, so answers rated elsewhere drop out.
    func currentReview(in store: AppStore) -> ReviewItem? {
        let items = store.data.review, position = reviewPosition
        return items.indices.lazy.map { items[(position + $0) % items.count] }.first { store.ratings[$0.id] == nil }
    }
    func skipReview(in store: AppStore) {
        guard let item = currentReview(in: store), let index = store.data.review.firstIndex(where: { $0.id == item.id }) else { return }
        reviewPosition = index + 1
        offerUndo(ReviewUndo(message: "Skipped · it stays in the queue", itemID: item.id, rated: false))
    }
    @discardableResult
    func rate(_ score: ReviewRating.Score, for reviewID: String, reasons: [String] = [], comment: String = "", in store: AppStore) -> Bool {
        guard store.rate(score, for: reviewID, reasons: reasons, comment: comment) else { return false }
        offerUndo(ReviewUndo(message: score == .good ? "Saved as good" : "Saved as needs work", itemID: reviewID, rated: true))
        return true
    }
    func undoReview(in store: AppStore) {
        guard let undo = reviewUndo, let index = store.data.review.firstIndex(where: { $0.id == undo.itemID }) else { return }
        if undo.rated { store.removeRating(for: undo.itemID) }
        reviewPosition = index
        dismissUndo()
    }
    private func dismissUndo() {
        undoExpiry?.cancel()
        reviewUndo = nil
    }
    // Only the latest action can be undone, and only for a few seconds.
    private func offerUndo(_ undo: ReviewUndo) {
        reviewUndo = undo
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoSeconds))
            guard !Task.isCancelled else { return }
            self?.reviewUndo = nil
        }
    }
}

func formatDuration(_ seconds: Double) -> String {
    seconds < 1 ? "\(Int((seconds * 1_000).rounded())) ms" : String(format: "%.1fs", seconds)
}
func formatCost(_ cost: Double) -> String { String(format: "$%.3f", cost) }
