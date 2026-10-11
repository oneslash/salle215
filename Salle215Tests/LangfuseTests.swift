import Foundation
import SwiftUI
import Testing
@testable import Salle215

private actor StubAPI {
    private var replies: [(Int, Data)]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [(Int, String)]) { self.replies = replies.map { ($0.0, Data($0.1.utf8)) } }
    func respond(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw LangfuseError.invalidResponse }
        let reply = replies.removeFirst()
        return (reply.1, HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: nil,
                                       headerFields: ["Retry-After": "30"])!)
    }
}

private actor SuspendedAPI {
    private var started = false
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func respond(_ request: URLRequest) async -> (Data, HTTPURLResponse) {
        started = true
        startedWaiter?.resume()
        await withCheckedContinuation { releaseWaiter = $0 }
        return (Data(#"{"data":[],"meta":{}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func waitUntilStarted() async {
        if !started { await withCheckedContinuation { startedWaiter = $0 } }
    }
    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

private final class MemoryVault: ConnectionVault {
    var credentials: LangfuseCredentials?
    var failsSave = false
    var failsDelete = false
    func load() throws -> LangfuseCredentials? { credentials }
    func save(_ credentials: LangfuseCredentials) throws {
        if failsSave { throw LangfuseError.keychain }
        self.credentials = credentials
    }
    func delete() throws {
        if failsDelete { throw LangfuseError.keychain }
        credentials = nil
    }
}

@MainActor
struct LangfuseTests {
    private let firstPage = #"{"data":[{"id":"child","traceId":"trace-a","type":"GENERATION","startTime":"2026-10-11T10:00:01.123Z","endTime":"2026-10-11T10:00:06.123Z","parentObservationId":"root","isRootObservation":false,"name":"generate","level":"ERROR","statusMessage":"Timeout","totalCost":0.02,"usageDetails":{"input":20,"output":0}}],"meta":{"cursor":"page-2"}}"#
    private let secondPage = #"{"data":[{"id":"root","traceId":"trace-a","type":"AGENT","startTime":"2026-10-11T10:00:00Z","endTime":"2026-10-11T10:00:07Z","parentObservationId":"external","isRootObservation":true,"name":"answer","traceName":"support","sessionId":"session-a","userId":"user-a","input":"[{\"role\":\"user\",\"content\":\"Hello\"}]","output":"{\"answer\":\"World\"}"}],"meta":{"cursor":null}}"#
    private let emptyPage = #"{"data":[],"meta":{"cursor":null}}"#

    private func credentials() throws -> LangfuseCredentials {
        try .init(host: "https://cloud.langfuse.com/api/public", publicKey: "pk-test", secretKey: "sk-test", environment: "production")
    }

    @Test func credentialsNormalizeAPIURLAndRejectUnsafeHosts() throws {
        #expect(try credentials().baseURL.absoluteString == "https://cloud.langfuse.com")
        let prefixed = try LangfuseCredentials(host: "https://example.com/langfuse/api/public/", publicKey: "pk", secretKey: "sk")
        #expect(prefixed.baseURL.absoluteString == "https://example.com/langfuse")
        #expect(throws: LangfuseError.self) { try LangfuseCredentials(host: "http://example.com", publicKey: "pk", secretKey: "sk") }
        #expect(throws: LangfuseError.self) { try LangfuseCredentials(host: "https://user:pass@example.com", publicKey: "pk", secretKey: "sk") }
        #expect(throws: LangfuseError.self) { try LangfuseCredentials(host: "https://example.com?key=secret", publicKey: "pk", secretKey: "sk") }
        #expect(throws: LangfuseError.self) { try LangfuseCredentials(host: "https://example.com", publicKey: "pk:other", secretKey: "sk") }
    }

    @Test func requestsUseOnlyV2WithBoundsAndSelectiveFields() async throws {
        let api = StubAPI([(200, firstPage), (200, secondPage)])
        let client = LangfuseClient(credentials: try credentials(), transport: { try await api.respond($0) })
        let from = Date(timeIntervalSince1970: 1_791_691_200), to = from.addingTimeInterval(3600)
        let page = try await client.observations(from: from, to: to)
        _ = try await client.observations(from: from, to: to, cursor: page.meta.cursor, traceID: "trace-a", includeIO: true)
        let requests = await api.requests
        for request in requests {
            #expect(request.url?.path == "/api/public/v2/observations")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(query.contains(.init(name: "fromStartTime", value: from.ISO8601Format())))
            #expect(query.contains(.init(name: "toStartTime", value: to.ISO8601Format())))
            #expect(query.contains(.init(name: "environment", value: "production")))
            #expect(!query.contains { $0.name == "parseIoAsJson" })
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("pk-test:sk-test".utf8).base64EncodedString())
        }
        let firstFields = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "fields" }!.value!
        #expect(!firstFields.split(separator: ",").contains("io"))
        #expect(requests[1].url?.query?.contains("cursor=page-2") == true)
        #expect(requests[1].url?.query?.contains("traceId=trace-a") == true)
    }

    @Test func fullTraceJoinsPagesAndUsesLogicalRootWithPhysicalParent() async throws {
        let api = StubAPI([(200, firstPage), (200, secondPage)])
        let client = LangfuseClient(credentials: try credentials(), transport: { try await api.respond($0) })
        let trace = try #require(try await client.trace("trace-a", from: .now.addingTimeInterval(-604800), to: .now))
        #expect(trace.name == "support")
        #expect(trace.spans.map(\.id) == ["root", "child"])
        #expect(trace.spans.map(\.depth) == [0, 1])
        #expect(trace.duration == 7)
        #expect(trace.status == .error)
        #expect(trace.input?.summary == "Hello")
        #expect(trace.output?.summary == #"{"answer":"World"}"#)
        #expect(trace.cost == 0.02)
        #expect(trace.session == "session-a")
        #expect(trace.spans.last?.usage?.input == 20)
    }

    @Test func observationColoursMatchLangfuse() {
        // Langfuse renders --observation-span-line as #3363ea in light mode and #8fb0f8 in dark mode.
        for (scheme, hex) in [(ColorScheme.light, [0x33, 0x63, 0xea]), (.dark, [0x8f, 0xb0, 0xf8])] {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            let color = Palette.glyph(.span).resolve(in: environment)
            #expect([color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) } == hex)
        }
    }

    @Test func missingRootAndUnknownTypesRemainReadable() async throws {
        let page = #"{"data":[{"id":"orphan","traceId":"t","type":"PLANNER","name":"plan","parentObservationId":"missing","startTime":"2026-10-11T10:00:00Z","endTime":"2026-10-11T10:00:02Z","input":"raw text"}],"meta":{}}"#
        let api = StubAPI([(200, page)])
        let client = LangfuseClient(credentials: try credentials(), transport: { try await api.respond($0) })
        let trace = try #require(try await client.trace("t", from: .now.addingTimeInterval(-604800), to: .now))
        #expect(trace.spans.first?.type == .span)
        #expect(trace.spans.first?.depth == 1)
        #expect(trace.input == nil)
        #expect(trace.duration == 2)
        #expect(trace.spans.first?.input?.summary == "raw text")
    }

    @Test func unassociatedObservationsDoNotBreakTraceLoading() async throws {
        let page = #"{"data":[{"id":"score-event","traceId":null,"type":"EVENT","startTime":"2026-10-11T10:00:00Z"}],"meta":{}}"#
        let api = StubAPI([(200, page)]), store = AppStore(reset: true)
        await store.connect(try credentials(), transport: { try await api.respond($0) })
        #expect(store.isLive && store.data.traces.isEmpty)
        #expect(store.connectionError == nil)
    }

    @Test func fullTraceRejectsRepeatedCursor() async throws {
        let api = StubAPI([(200, firstPage), (200, firstPage)])
        let client = LangfuseClient(credentials: try credentials(), transport: { try await api.respond($0) })
        await #expect(throws: LangfuseError.self) {
            try await client.trace("trace-a", from: .now.addingTimeInterval(-604800), to: .now)
        }
        #expect(await api.requests.count == 2)
    }

    @Test func failedAuthenticationDoesNotSaveOrConnect() async throws {
        let vault = MemoryVault(), api = StubAPI([(401, "{}")])
        let store = AppStore(reset: true, vault: vault)
        await store.connect(try credentials(), transport: { try await api.respond($0) })
        #expect(!store.isConnected)
        #expect(!store.isLive)
        #expect(!store.isLoading)
        #expect(vault.credentials == nil)
        #expect(store.connectionError?.contains("rejected") == true)
    }

    @Test func rateLimitIsActionableAndDoesNotSilentlyRetry() async throws {
        let api = StubAPI([(429, "{}")]), store = AppStore(reset: true)
        await store.connect(try credentials(), transport: { try await api.respond($0) })
        #expect(store.connectionError?.contains("30 seconds") == true)
        #expect(await api.requests.count == 1)
    }

    @Test func liveDataNeverExposesSampleReviewOrPromptsAndMergesPages() async throws {
        let api = StubAPI([(200, firstPage), (200, secondPage)])
        let store = AppStore(reset: true)
        await store.connect(try credentials(), transport: { try await api.respond($0) })
        #expect(store.isConnected && store.isLive)
        #expect(store.data.traces.count == 1)
        #expect(store.data.review.isEmpty && store.data.prompts.isEmpty && store.ratings.isEmpty)
        await store.loadMoreObservations()
        #expect(store.data.traces.count == 1)
        #expect(store.data.traces.first?.spans.count == 2)
        #expect(store.nextCursor == nil)
        #expect(store.connectionError == nil)
    }

    @Test func emptyProjectConnectsAndKeychainFailureLeavesConnectionUnsaved() async throws {
        let suite = "Salle215LiveTests.\(UUID().uuidString)", vault = MemoryVault()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = StubAPI([(200, emptyPage), (200, emptyPage)])
        let store = AppStore(defaults: defaults, vault: vault)
        vault.failsSave = true
        await store.connect(try credentials(), transport: { try await api.respond($0) })
        #expect(!store.isConnected && vault.credentials == nil)
        vault.failsSave = false
        await store.connect(try credentials(), transport: { try await api.respond($0) })
        #expect(store.isLive && store.data.traces.isEmpty)
        #expect(try vault.load()?.publicKey == "pk-test")
        #expect(defaults.string(forKey: "secretKey") == nil)
        vault.failsDelete = true
        store.disconnect()
        #expect(store.isConnected && store.connectionError != nil)
        vault.failsDelete = false
        store.disconnect()
        #expect(!store.isConnected && vault.credentials == nil)
    }

    @Test func lateConnectionResponseCannotReconnectAfterDisconnect() async throws {
        let vault = MemoryVault(), api = SuspendedAPI()
        let store = AppStore(reset: true, vault: vault)
        let credentials = try credentials()
        let connection = Task { await store.connect(credentials, transport: { await api.respond($0) }) }
        await api.waitUntilStarted()
        store.disconnect()
        await api.release()
        await connection.value
        #expect(!store.isConnected && !store.isLive && !store.isLoading)
        #expect(vault.credentials == nil)
        #expect(store.data.traces.count == 7)
    }

    @Test func duplicateStepsAndParentCyclesDoNotDuplicateOrHang() async throws {
        let page = #"{"data":[{"id":"a","traceId":"t","type":"SPAN","parentObservationId":"b","startTime":"2026-10-11T10:00:00Z"},{"id":"b","traceId":"t","type":"SPAN","parentObservationId":"a","startTime":"2026-10-11T10:00:01Z"}],"meta":{}}"#
        let api = StubAPI([(200, page)])
        let client = LangfuseClient(credentials: try credentials(), transport: { try await api.respond($0) })
        let rows = try await client.observations(from: .now.addingTimeInterval(-604800), to: .now).data
        let trace = try #require(ObservationMapper.traces(rows + rows).first)
        #expect(trace.spans.count == 2)
        #expect(trace.spans.allSatisfy { $0.depth > 0 })
        #expect(trace.input == nil)
    }

    @Test func switchingToSampleRestoresItsRatings() async throws {
        let suite = "Salle215LiveTests.\(UUID().uuidString)", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults, vault: MemoryVault()), api = StubAPI([(200, emptyPage)])
        store.connectSample()
        store.rate(.good, for: "7C1D")
        await store.connect(try credentials(), transport: { try await api.respond($0) })
        #expect(store.ratings.isEmpty)
        store.connectSample()
        #expect(!store.isLive)
        #expect(store.ratings["7C1D"]?.score == .good)
        #expect(store.data.traces.count == 7)
    }
}
