import Foundation
import Observation

enum JSONValue: Codable, Hashable, Sendable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    var number: Double? {
        let value: Double? = switch self { case .number(let v): v; case .string(let v): Double(v); default: nil }
        return value.flatMap { $0.isFinite ? $0 : nil }
    }
    var string: String? { if case .string(let v) = self { return v }; return nil }
}

typealias MetricsRow = [String: JSONValue]
struct MetricsResponse: Decodable, Sendable { let data: [MetricsRow] }

struct MetricsQuery: Encodable, Sendable {
    let view: String
    let dimensions: [[String: String]]
    let metrics: [[String: String]]
    var filters: [[String: JSONValue]]
    let fromTimestamp: String
    let toTimestamp: String
    let timeDimension: [String: String]?
    let orderBy: [[String: String]]
    let config: [String: Int] = ["row_limit": 1000]

    init(view: String = "observations", dimensions: [String] = [], measures: [(String, String)],
         filters: [[String: JSONValue]] = [], from: Date, to: Date, granularity: String? = nil, order: String? = nil) {
        self.view = view
        self.dimensions = dimensions.map { ["field": $0] }
        self.metrics = measures.map { ["measure": $0.0, "aggregation": $0.1] }
        self.filters = filters
        fromTimestamp = from.ISO8601Format()
        toTimestamp = to.ISO8601Format()
        timeDimension = granularity.map { ["granularity": $0] }
        orderBy = order.map { [["field": $0, "direction": "desc"]] } ?? (granularity == nil ? [] : [["field": "time_dimension", "direction": "asc"]])
    }
    static func filter(_ column: String, _ value: JSONValue, type: String = "string") -> [String: JSONValue] {
        ["column": .string(column), "operator": .string("="), "value": value, "type": .string(type)]
    }
}

extension LangfuseClient {
    func metrics(_ query: MetricsQuery) async throws -> [MetricsRow] {
        var query = query
        if !credentials.environment.isEmpty { query.filters.append(MetricsQuery.filter("environment", .string(credentials.environment))) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(query), as: UTF8.self)
        let data = try await request(path: ["api", "public", "v2", "metrics"], query: [.init(name: "query", value: json)])
        let rows = try JSONDecoder().decode(MetricsResponse.self, from: data).data
        // There is no pagination or truncation flag. At the cap, do not present incomplete aggregates as totals.
        guard rows.count < 1000 else { throw MetricsError.rowLimit }
        return rows
    }
}

enum MetricsError: LocalizedError {
    case rowLimit, malformed
    var errorDescription: String? {
        switch self {
        case .rowLimit: "This report reached Langfuse's row limit. Choose a shorter time range."
        case .malformed: "Langfuse returned metric values that could not be read."
        }
    }
}

extension TimeRange {
    var seconds: TimeInterval { switch self { case .hour: 3600; case .day: 86400; case .week: 604800 } }
    var granularity: String { switch self { case .hour: "minute"; case .day: "hour"; case .week: "day" } }
}

struct LiveMetricPoint: Identifiable, Sendable {
    let date: Date
    let value: Double
    var id: Date { date }
}
struct LiveScoreAggregate: Identifiable, Sendable {
    let name: String
    let dataType: String
    let average: Double
    let count: Double
    var id: String { name + ":" + dataType }
    var formatted: String { dataType == "BOOLEAN" ? String(format: "%.1f%%", average * 100) : average.formatted(.number.precision(.fractionLength(0...3))) }
}
struct LiveOverviewData: Sendable {
    let from: Date
    let to: Date
    var activity: [MetricsRow]?
    var roots: [MetricsRow]?
    var rootTrend: [MetricsRow]?
    var scores: [MetricsRow]?
    var failures: [String: String] = [:]
    var observationCount: Double? { activity.map { $0.reduce(0) { $0 + ($1["count_count"]?.number ?? 0) } } }
    var errorCount: Double? { activity.map { $0.filter { $0["level"]?.string == "ERROR" }.reduce(0) { $0 + ($1["count_count"]?.number ?? 0) } } }
    var errorRate: Double? {
        guard let total = observationCount, total > 0, let errors = errorCount else { return nil }
        return 100 * errors / total
    }
    var cost: Double? {
        guard let activity else { return nil }
        let costs = activity.compactMap { $0["sum_totalCost"]?.number }
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }
    var rootCount: Double? { roots?.first?["count_count"]?.number }
    // Metrics API latency is milliseconds; the UI consistently displays seconds.
    var latency: Double? {
        guard let count = rootCount, count > 0 else { return nil }
        return roots?.first?["p95_latency"]?.number.map { $0 / 1000 }
    }
    var scoreAggregates: [LiveScoreAggregate] {
        (scores ?? []).compactMap { row in
            guard let name = row["name"]?.string, let type = row["dataType"]?.string,
                  let average = row["avg_value"]?.number, let count = row["count_count"]?.number, count > 0 else { return nil }
            return .init(name: name, dataType: type, average: average, count: count)
        }.sorted { $0.id < $1.id }
    }
    func series(_ kind: MetricKind) -> [LiveMetricPoint] {
        if kind == .latency {
            return (rootTrend ?? []).compactMap { row in
                guard let date = Self.date(row["time_dimension"]?.string), let count = row["count_count"]?.number, count > 0,
                      let value = row["p95_latency"]?.number else { return nil }
                return LiveMetricPoint(date: date, value: value / 1000)
            }.sorted { $0.date < $1.date }
        }
        let rows = (activity ?? []).compactMap { row -> (Date, MetricsRow)? in
            Self.date(row["time_dimension"]?.string).map { ($0, row) }
        }
        return Dictionary(grouping: rows, by: { $0.0 }).compactMap { date, rows in
            let count = rows.reduce(0) { $0 + ($1.1["count_count"]?.number ?? 0) }
            if kind == .errors {
                guard count > 0 else { return nil }
                let errors = rows.filter { $0.1["level"]?.string == "ERROR" }.reduce(0) { $0 + ($1.1["count_count"]?.number ?? 0) }
                return LiveMetricPoint(date: date, value: 100 * errors / count)
            }
            let costs = rows.compactMap { $0.1["sum_totalCost"]?.number }
            guard !costs.isEmpty else { return nil }
            return LiveMetricPoint(date: date, value: costs.reduce(0, +))
        }.sorted { $0.date < $1.date }
    }
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) { return date }
        // Langfuse day buckets are YYYY-MM-DD; hour/minute buckets can omit a timezone.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}

struct LiveOverviewState {
    var data: LiveOverviewData?
    var isLoading = false
    var lastAttempt: Date?
    var refreshFailures: [String: String] = [:]
}
struct LiveBreakdownState {
    var rows: [MetricsRow]?
    var error: String?
    var isLoading = false
}

@MainActor @Observable
final class LiveMetricsStore {
    private(set) var states: [TimeRange: LiveOverviewState] = [:]
    private(set) var breakdowns: [String: LiveBreakdownState] = [:]
    private(set) var retryAfter: Date?
    @ObservationIgnored private var client: LangfuseClient?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var tasks: [TimeRange: Task<Void, Never>] = [:]
    @ObservationIgnored private var detailTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let now: () -> Date
    init(now: @escaping () -> Date = { .now }) { self.now = now }

    func configure(_ client: LangfuseClient?) {
        tasks.values.forEach { $0.cancel() }
        detailTasks.values.forEach { $0.cancel() }
        tasks = [:]; detailTasks = [:]
        generation = UUID()
        self.client = client
        states = [:]; breakdowns = [:]; retryAfter = nil
    }
    func state(_ range: TimeRange) -> LiveOverviewState { states[range] ?? .init() }
    func load(_ range: TimeRange, refresh: Bool = false) async {
        if let task = tasks[range] { await task.value; return }
        guard let client else { return }
        let current = now(), state = state(range)
        let failed = !(state.data?.failures.isEmpty ?? true) || !state.refreshFailures.isEmpty
        if let attempt = state.lastAttempt, current.timeIntervalSince(attempt) < (refresh || failed ? 60 : 600) { return }
        if let retryAfter, retryAfter > current { return }
        let generation = generation
        let task = Task { await self.fetch(range, client: client, generation: generation) }
        tasks[range] = task
        await task.value
        if generation == self.generation { tasks[range] = nil }
    }
    private func fetch(_ range: TimeRange, client: LangfuseClient, generation: UUID) async {
        let to = now(), from = to.addingTimeInterval(-range.seconds)
        var data = LiveOverviewData(from: from, to: to)
        let root = MetricsQuery.filter("isRootObservation", .bool(true), type: "boolean")
        let queries: [(String, MetricsQuery)] = [
            ("activity", .init(dimensions: ["level"], measures: [("count", "count"), ("totalCost", "sum")], from: from, to: to, granularity: range.granularity)),
            ("roots", .init(measures: [("count", "count"), ("latency", "p95")], filters: [root], from: from, to: to)),
            ("trend", .init(measures: [("count", "count"), ("latency", "p95")], filters: [root], from: from, to: to, granularity: range.granularity)),
            ("scores", .init(view: "scores-numeric", dimensions: ["name", "dataType"], measures: [("value", "avg"), ("count", "count")], from: from, to: to))
        ]
        var state = state(range)
        state.isLoading = true
        state.lastAttempt = to
        states[range] = state // Keep the last completed report visible while refreshing.
        for (key, query) in queries {
            if Task.isCancelled || generation != self.generation { return }
            if let retryAfter, retryAfter > now() {
                data.failures[key] = "Metrics are rate limited. Retry after the time shown above."
                continue
            }
            do {
                let rows = try await client.metrics(query)
                guard !Task.isCancelled, generation == self.generation else { return }
                try Self.validate(rows, for: key)
                switch key {
                case "activity": data.activity = rows
                case "roots": data.roots = rows
                case "trend": data.rootTrend = rows
                default: data.scores = rows
                }
            } catch {
                guard !Task.isCancelled, generation == self.generation else { return }
                applyLimit(error)
                data.failures[key] = error.localizedDescription
            }
        }
        guard generation == self.generation else { return }
        if !data.failures.isEmpty, let previous = state.data, previous.failures.isEmpty {
            states[range] = .init(data: previous, isLoading: false, lastAttempt: to, refreshFailures: data.failures)
            return // Keep one coherent completed report, never mix buckets from different requests.
        }
        states[range] = .init(data: data, isLoading: false, lastAttempt: to)
        if data.failures.isEmpty { retryAfter = nil }
        let prefix = range.title + ":"
        for key in detailTasks.keys.filter({ $0.hasPrefix(prefix) }) { detailTasks.removeValue(forKey: key)?.cancel() }
        breakdowns = breakdowns.filter { !$0.key.hasPrefix(prefix) }
    }
    private static func validate(_ rows: [MetricsRow], for key: String) throws {
        for row in rows {
            guard row["count_count"]?.number != nil else { throw MetricsError.malformed }
            if key == "activity" || key == "trend" {
                guard LiveOverviewData.date(row["time_dimension"]?.string) != nil else { throw MetricsError.malformed }
            }
            if key == "scores" {
                guard row["name"]?.string != nil, row["dataType"]?.string != nil, row["avg_value"]?.number != nil else { throw MetricsError.malformed }
            }
        }
    }
    private func applyLimit(_ error: Error) {
        guard case LangfuseError.rateLimited(let value) = error else { return }
        retryAfter = now().addingTimeInterval(retryDelay(value))
    }
    func nextRefreshDate(_ range: TimeRange) -> Date? {
        [retryAfter, state(range).lastAttempt?.addingTimeInterval(60)].compactMap { $0 }.max()
    }
    func detailKey(_ kind: MetricKind, range: TimeRange, score: LiveScoreAggregate? = nil) -> String {
        "\(range.title):\(kind.rawValue):\(score?.id ?? ""):\(states[range]?.data?.to.timeIntervalSince1970 ?? 0)"
    }
    func loadBreakdown(_ kind: MetricKind, range: TimeRange, score: LiveScoreAggregate? = nil) async {
        let key = detailKey(kind, range: range, score: score)
        if let task = detailTasks[key] { await task.value; return }
        guard let client, let overview = states[range]?.data, breakdowns[key]?.rows == nil else { return }
        if let retryAfter, retryAfter > now() { return }
        let generation = generation
        let task = Task { await self.fetchBreakdown(kind, range: range, score: score, key: key, overview: overview, client: client, generation: generation) }
        detailTasks[key] = task
        await task.value
        if generation == self.generation { detailTasks[key] = nil }
    }
    private func fetchBreakdown(_ kind: MetricKind, range: TimeRange, score: LiveScoreAggregate?, key: String,
                                overview: LiveOverviewData, client: LangfuseClient, generation: UUID) async {
        breakdowns[key] = .init(isLoading: true)
        let query: MetricsQuery
        switch kind {
        case .errors:
            query = .init(dimensions: ["name"], measures: [("count", "count")], filters: [MetricsQuery.filter("level", .string("ERROR"))], from: overview.from, to: overview.to, order: "count_count")
        case .latency:
            query = .init(dimensions: ["traceName"], measures: [("latency", "p95"), ("count", "count")], filters: [MetricsQuery.filter("isRootObservation", .bool(true), type: "boolean")], from: overview.from, to: overview.to, order: "p95_latency")
        case .spend:
            query = .init(dimensions: ["providedModelName"], measures: [("totalCost", "sum")], from: overview.from, to: overview.to, order: "sum_totalCost")
        case .quality:
            guard let score else { breakdowns[key] = .init(rows: []); return }
            query = .init(view: "scores-numeric", measures: [("value", "avg"), ("count", "count")], filters: [MetricsQuery.filter("name", .string(score.name)), MetricsQuery.filter("dataType", .string(score.dataType))], from: overview.from, to: overview.to, granularity: range.granularity)
        }
        do {
            let rows = try await client.metrics(query)
            guard !Task.isCancelled, generation == self.generation, states[range]?.data?.to == overview.to else { return }
            breakdowns[key] = .init(rows: rows)
        } catch {
            guard !Task.isCancelled, generation == self.generation else { return }
            applyLimit(error)
            breakdowns[key] = .init(error: error.localizedDescription)
        }
    }
}
