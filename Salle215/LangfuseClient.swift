import Foundation
import Security

struct LangfuseCredentials: Codable, Sendable {
    let baseURL: URL
    let publicKey: String
    let secretKey: String
    let environment: String

    init(host: String, publicKey: String, secretKey: String, environment: String = "") throws {
        guard let url = URL(string: host.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw LangfuseError.invalidHost }
        let publicKey = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !publicKey.isEmpty, !secretKey.isEmpty, !publicKey.contains(":"),
              !publicKey.contains(where: \.isNewline), !secretKey.contains(where: \.isNewline) else {
            throw LangfuseError.invalidKeys
        }
        // Accept either the instance URL or the public API URL pasted from the docs.
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        while components.path.hasSuffix("/") { components.path.removeLast() }
        if components.path.hasSuffix("/api/public") { components.path.removeLast("/api/public".count) }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !components.path.isEmpty { components.path = "/" + components.path }
        self.baseURL = components.url!
        self.publicKey = publicKey
        self.secretKey = secretKey
        self.environment = environment.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LangfuseError: LocalizedError {
    case invalidHost, invalidKeys, authentication, forbidden, rateLimited(String?), http(Int), invalidResponse, pagination, keychain
    var errorDescription: String? {
        switch self {
        case .invalidHost: "Enter an HTTPS Langfuse instance URL without credentials, query parameters or fragments."
        case .invalidKeys: "Enter the project's public and secret API keys."
        case .authentication: "The API keys were rejected. Check the keys and the Langfuse region."
        case .forbidden: "These API keys do not have access to this resource."
        case .rateLimited(let retry): "Langfuse's API limit was reached. " + (retry.map { "Retry after \($0) seconds." } ?? "Try again shortly.")
        case .http(let status): "Langfuse returned HTTP \(status). Check the connection or try again."
        case .invalidResponse: "Langfuse returned an unexpected response."
        case .pagination: "Langfuse returned a repeated cursor or too many pages. Narrow the time range and retry."
        case .keychain: "The connection could not be read or saved securely in Keychain."
        }
    }
}

protocol ConnectionVault {
    func load() throws -> LangfuseCredentials?
    func save(_ credentials: LangfuseCredentials) throws
    func delete() throws
}

struct KeychainConnectionVault: ConnectionVault {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "room215.salle215.langfuse",
         kSecAttrAccount as String: "connection"]
    }
    func load() throws -> LangfuseCredentials? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw LangfuseError.keychain }
        return try JSONDecoder().decode(LangfuseCredentials.self, from: data)
    }
    func save(_ credentials: LangfuseCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LangfuseError.keychain }
        } else if status != errSecSuccess { throw LangfuseError.keychain }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw LangfuseError.keychain }
    }
}

// Never follow a redirect carrying project credentials to another instance.
private final class LangfuseSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct LangfuseClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    let credentials: LangfuseCredentials
    private let transport: Transport
    private let limits = APILimits()

    init(credentials: LangfuseCredentials, transport: Transport? = nil) {
        self.credentials = credentials
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: LangfuseSessionDelegate(), delegateQueue: nil)
        self.transport = transport ?? { request in
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw LangfuseError.invalidResponse }
            return (data, response)
        }
    }

    func observations(from: Date, to: Date, cursor: String? = nil, traceID: String? = nil, includeIO: Bool = false,
                      sessionID: String? = nil, search: ObservationSearch? = nil) async throws -> ObservationPage {
        var components = URLComponents(url: credentials.baseURL.appending(path: "api/public/v2/observations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "fromStartTime", value: from.ISO8601Format()), .init(name: "toStartTime", value: to.ISO8601Format()),
            .init(name: "limit", value: "200"),
            .init(name: "fields", value: "core,basic,model,usage,prompt,trace_context" + (includeIO ? ",io" : ""))
        ]
        if let cursor { components.queryItems?.append(.init(name: "cursor", value: cursor)) }
        if let traceID { components.queryItems?.append(.init(name: "traceId", value: traceID)) }
        if let sessionID { components.queryItems?.append(.init(name: "sessionId", value: sessionID)) }
        if !credentials.environment.isEmpty { components.queryItems?.append(.init(name: "environment", value: credentials.environment)) }
        if let search {
            // Structured filters replace individual parameters, so repeat the bounds and environment here.
            var filters = [search.filter,
                           ["type": JSONValue.string("datetime"), "column": .string("startTime"), "operator": .string(">="), "value": .string(from.ISO8601Format())],
                           ["type": .string("datetime"), "column": .string("startTime"), "operator": .string("<"), "value": .string(to.ISO8601Format())]]
            if !credentials.environment.isEmpty { filters.append(MetricsQuery.filter("environment", .string(credentials.environment))) }
            components.queryItems?.append(.init(name: "filter", value: String(decoding: try JSONEncoder().encode(filters), as: UTF8.self)))
        }
        let data = try await request(url: components.url!)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid observation timestamp"))
            }
            return date
        }
        return try decoder.decode(ObservationPage.self, from: data)
    }

    func request(path: [String], query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) async throws -> Data {
        var components = URLComponents(url: credentials.baseURL, resolvingAgainstBaseURL: false)!
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_~"))
        let suffix = path.map { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "/")
        components.percentEncodedPath += "/" + suffix
        if !query.isEmpty { components.queryItems = query }
        return try await request(url: components.url!, method: method, body: body)
    }

    private func request(url: URL, method: String = "GET", body: Data? = nil) async throws -> Data {
        let bucket = url.path.hasSuffix("/v2/metrics") ? "metrics" : "public"
        try await limits.check(bucket)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        let auth = Data("\(credentials.publicKey):\(credentials.secretKey)".utf8).base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await transport(request)
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw LangfuseError.authentication
        case 403: throw LangfuseError.forbidden
        case 429:
            let retry = response.value(forHTTPHeaderField: "Retry-After")
            await limits.record(bucket, retry: retry)
            throw LangfuseError.rateLimited(retry)
        default: throw LangfuseError.http(response.statusCode)
        }
    }

    func trace(_ id: String, from: Date, to: Date) async throws -> TraceRecord? {
        var rows: [LangfuseObservation] = [], cursor: String?, seen = Set<String>()
        repeat {
            try Task.checkCancellation()
            let page = try await observations(from: from, to: to, cursor: cursor, traceID: id, includeIO: true)
            rows.append(contentsOf: page.data)
            cursor = page.meta.cursor
            if let cursor, !seen.insert(cursor).inserted || seen.count > 100 { throw LangfuseError.pagination }
        } while cursor != nil
        return ObservationMapper.traces(rows).first { $0.id == id }
    }
}

private actor APILimits {
    private var deadlines: [String: Date] = [:]
    func check(_ bucket: String) throws {
        if let deadline = deadlines[bucket], deadline > .now {
            throw LangfuseError.rateLimited(String(Int(ceil(deadline.timeIntervalSinceNow))))
        }
    }
    func record(_ bucket: String, retry: String?) {
        deadlines[bucket] = .now.addingTimeInterval(retryDelay(retry))
    }
}

func retryDelay(_ raw: String?) -> TimeInterval {
    guard let value = raw.flatMap(Double.init), value.isFinite else { return 60 }
    return max(1, min(value, 604800))
}

struct ObservationPage: Decodable, Sendable {
    struct Meta: Decodable, Sendable { let cursor: String? }
    let data: [LangfuseObservation]
    let meta: Meta
}

struct LangfuseObservation: Decodable, Sendable {
    let id: String
    let traceId: String?
    let type: String
    let startTime: Date
    let endTime: Date?
    let parentObservationId: String?
    let isRootObservation: Bool?
    let name: String?
    let traceName: String?
    let userId: String?
    let sessionId: String?
    let environment: String?
    let level: String?
    let statusMessage: String?
    let model: String?
    let input: String?
    let output: String?
    let usageDetails: [String: Int]?
    let inputUsage: Double?
    let outputUsage: Double?
    let totalCost: Double?
    let promptName: String?
    let promptVersion: Int?
}

enum ObservationMapper {
    static func content(_ raw: String?) -> MessageContent? {
        guard let raw else { return nil }
        // v2 returns JSON as a string. Preserve arbitrary JSON and multimodal payloads as readable text.
        let data = Data(raw.utf8)
        if let text = try? JSONDecoder().decode(String.self, from: data) { return .text(text) }
        if let messages = try? JSONDecoder().decode([ChatMessage].self, from: data) { return .messages(messages) }
        return .text(raw)
    }

    static func traces(_ rows: [LangfuseObservation]) -> [TraceRecord] {
        var groups: [String: [LangfuseObservation]] = [:]
        for row in rows {
            guard let id = row.traceId, !id.isEmpty else { continue }
            groups[id, default: []].append(row)
        }
        let traces = groups.map { trace(id: $0.key, duplicates: $0.value) }
        return traces.sorted { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp > $1.timestamp }
    }

    private static func trace(id: String, duplicates: [LangfuseObservation]) -> TraceRecord {
        var byID: [String: LangfuseObservation] = [:]
        for row in duplicates { byID[row.id] = row }
        let rows: [LangfuseObservation] = byID.values.sorted { left, right in
            if left.startTime == right.startTime { return left.id < right.id }
            return left.startTime < right.startTime
        }
        let root = rows.first { $0.isRootObservation == true } ?? rows.first { $0.parentObservationId == nil && $0.isRootObservation != false }
        let origin = rows.map(\.startTime).min()!
        func depth(_ row: LangfuseObservation) -> Int {
            if row.id == root?.id { return 0 }
            var current = row, visited: Set<String> = [row.id], depth = 1
            while let parent = current.parentObservationId, let next = byID[parent], visited.insert(parent).inserted {
                if next.id == root?.id { return depth }
                depth += 1
                current = next
            }
            return depth // Missing parents and cycles never masquerade as the root.
        }
        let spans: [TraceSpan] = rows.map { row -> TraceSpan in
            let kind = TraceSpan.Kind(rawValue: row.type.lowercased()) ?? .span
            let start = row.startTime.timeIntervalSince(origin)
            return TraceSpan(id: row.id, name: row.name ?? row.type, type: kind, depth: depth(row), start: start,
                             end: max(start, (row.endTime ?? row.startTime).timeIntervalSince(origin)),
                             input: content(row.input), output: content(row.output), level: row.level,
                             statusMessage: row.statusMessage, model: row.model,
                             usage: usage(row),
                             cost: row.totalCost, promptName: row.promptName, promptVersion: row.promptVersion)
        }.sorted { $0.start == $1.start ? ($0.depth == $1.depth ? $0.id < $1.id : $0.depth < $1.depth) : $0.start < $1.start }
        return TraceRecord(id: id, name: root?.traceName ?? root?.name ?? rows.compactMap(\.traceName).first ?? rows.first?.name ?? id,
                           timestamp: root?.startTime ?? origin, session: root?.sessionId ?? rows.compactMap(\.sessionId).first ?? "",
                           user: root?.userId ?? rows.compactMap(\.userId).first ?? "", spans: spans)
    }

    private static func usage(_ row: LangfuseObservation) -> TraceSpan.Usage? {
        let input = row.usageDetails?["input"] ?? row.inputUsage.flatMap { Int(exactly: $0) }
        let output = row.usageDetails?["output"] ?? row.outputUsage.flatMap { Int(exactly: $0) }
        guard input != nil || output != nil else { return nil }
        return .init(input: input ?? 0, output: output)
    }
}
