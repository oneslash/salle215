import Foundation
import Testing
@testable import Salle215

private actor BackendStub {
    var requests: [URLRequest] = []
    var replies: [(Int, String)]
    init(_ replies: [(Int, String)]) { self.replies = replies }
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw LangfuseError.invalidResponse }
        let (status, text) = replies.removeFirst()
        return (Data(text.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "30"])!)
    }
}
@MainActor struct BackendTests {
    private func client(_ stub: BackendStub, environment: String = "production") throws -> LangfuseClient {
        LangfuseClient(credentials: try .init(host: "https://example.com", publicKey: "pk-test", secretKey: "sk-test", environment: environment), transport: { try await stub.send($0) })
    }
    private let activity = #"{"data":[{"time_dimension":"2026-10-10","level":"ERROR","count_count":"2","sum_totalCost":"0.10"},{"time_dimension":"2026-10-10","level":"DEFAULT","count_count":8,"sum_totalCost":0.20}]}"#
    private let roots = #"{"data":[{"count_count":3,"p95_latency":2500}]}"#
    private let trend = #"{"data":[{"time_dimension":"2026-10-10","count_count":3,"p95_latency":1900}]}"#
    private let scores = #"{"data":[{"name":"accuracy","dataType":"NUMERIC","avg_value":4.5,"count_count":10},{"name":"human-thumbs","dataType":"BOOLEAN","avg_value":0.7,"count_count":5}]}"#
    @Test func metricsUseV2BoundedQueryAndCorrectAggregates() async throws {
        let stub = BackendStub([(200, activity),(200, roots),(200, trend),(200, scores)])
        let metrics = LiveMetricsStore(now: { Date(timeIntervalSince1970: 1_791_691_200) })
        metrics.configure(try client(stub))
        await metrics.load(.week)
        let data = try #require(metrics.state(.week).data)
        #expect(data.failures.isEmpty)
        #expect(data.observationCount == 10 && data.errorRate == 20)
        #expect(abs((data.cost ?? 0) - 0.3) < 0.000001)
        #expect(data.latency == 2.5) // Whole-window P95, never average the trend's percentiles.
        #expect(data.series(.latency).first?.value == 1.9)
        #expect(data.series(.errors).first?.value == 20)
        #expect(data.scoreAggregates.count == 2)
        #expect(data.scoreAggregates.first { $0.dataType == "NUMERIC" }?.formatted == 4.5.formatted(.number.precision(.fractionLength(0...3))))
        #expect(data.scoreAggregates.first { $0.dataType == "BOOLEAN" }?.formatted == "70.0%")
        for request in await stub.requests {
            #expect(request.url?.path == "/api/public/v2/metrics")
            let json = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "query" }!.value!
            let query = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            #expect(query["fromTimestamp"] != nil && query["toTimestamp"] != nil)
            let filters = try #require(query["filters"] as? [[String: Any]])
            #expect(filters.contains { $0["column"] as? String == "environment" && $0["value"] as? String == "production" })
        }
        await metrics.load(.week); await metrics.load(.week, refresh: true)
        #expect(await stub.requests.count == 4) // Cached reads and premature manual refresh spend no quota.
    }
    @Test func emptyMetricsDoNotInventLatencyCostOrQuality() async throws {
        let stub = BackendStub(Array(repeating: (200, #"{"data":[]}"#), count: 4)), metrics = LiveMetricsStore()
        metrics.configure(try client(stub)); await metrics.load(.hour)
        let data = try #require(metrics.state(.hour).data)
        #expect(data.observationCount == 0)
        #expect(data.errorRate == nil && data.latency == nil && data.cost == nil && data.scoreAggregates.isEmpty)
    }
    @Test func partialMetricFailureKeepsIndependentSections() async throws {
        let stub = BackendStub([(200,activity),(403,"{}"),(200,trend),(200,scores)]), metrics = LiveMetricsStore()
        metrics.configure(try client(stub)); await metrics.load(.day)
        let data = try #require(metrics.state(.day).data)
        #expect(data.errorRate == 20 && data.latency == nil && data.scoreAggregates.count == 2)
        #expect(data.failures["roots"] != nil && data.failures.count == 1)
    }
    @Test func rateLimitStopsRemainingQueriesAndPersistsAcrossRanges() async throws {
        let stub = BackendStub([(429,"{}")]), metrics = LiveMetricsStore()
        metrics.configure(try client(stub)); await metrics.load(.week); await metrics.load(.day)
        #expect(metrics.retryAfter != nil)
        #expect(metrics.state(.week).data?.failures.count == 4)
        #expect(await stub.requests.count == 1)
    }
    @Test func failedRefreshRetainsTheCompletedReportAndItsTimestamp() async throws {
        var clock = Date(timeIntervalSince1970: 1_791_691_200)
        let stub = BackendStub([(200, activity), (200, roots), (200, trend), (200, scores), (429, "{}")])
        let metrics = LiveMetricsStore(now: { clock })
        metrics.configure(try client(stub))
        await metrics.load(.day)
        let original = try #require(metrics.state(.day).data)
        clock = clock.addingTimeInterval(61)
        await metrics.load(.day, refresh: true)
        let retained = try #require(metrics.state(.day).data)
        #expect(retained.to == original.to)
        #expect(retained.errorRate == original.errorRate && retained.latency == original.latency)
        #expect(retained.cost == original.cost && retained.scoreAggregates.count == original.scoreAggregates.count)
        #expect(retained.failures.isEmpty && metrics.state(.day).refreshFailures.count == 4)
        #expect(metrics.nextRefreshDate(.day) == clock.addingTimeInterval(60))
        await metrics.load(.day, refresh: true)
        #expect(await stub.requests.count == 5)
    }
    @Test func reachedRowLimitAndMalformedBucketsNeverBecomeTotals() async throws {
        let capped = try JSONSerialization.data(withJSONObject: ["data": Array(repeating: ["count_count": 1], count: 1000)])
        let stub = BackendStub([(200,String(decoding:capped,as:UTF8.self))])
        await #expect(throws: MetricsError.self) { try await client(stub).metrics(.init(measures: [("count","count")],from:.now.addingTimeInterval(-3600),to:.now)) }
        #expect(LiveOverviewData.date("2026-10-10") != nil)
        #expect(LiveOverviewData.date("2026-10-10T10:00:00Z") != nil)
        #expect(LiveOverviewData.date("invalid") == nil)
    }
    @Test func searchRepeatsTimeAndEnvironmentInStructuredFilter() async throws {
        let stub = BackendStub([(200,#"{"data":[],"meta":{}}"#)])
        _ = try await client(stub).observations(from:.now.addingTimeInterval(-3600),to:.now,search:.init(scope:.input,text:"100%_literal"))
        let request = try #require(await stub.requests.first)
        let value = try #require(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!.first { $0.name == "filter" }?.value)
        let filters = try #require(JSONSerialization.jsonObject(with:Data(value.utf8)) as? [[String:Any]])
        #expect(filters.count == 4)
        #expect(filters[0]["operator"] as? String == "matches")
        #expect(filters[0]["value"] as? String == "100%_literal")
        #expect(filters.filter { $0["column"] as? String == "startTime" }.count == 2)
        #expect(filters.contains { $0["column"] as? String == "environment" })
    }
    @Test func promptFoldersEncodedAndPlaceholdersPreserved() async throws {
        let stub = BackendStub([(200,#"{"name":"folder/prompt","type":"chat","version":2,"labels":["latest"],"commitMessage":null,"prompt":[{"role":"system","content":"Hello"},{"type":"placeholder","name":"history"}]}"#)])
        let prompt = try await client(stub).prompt("folder/prompt",version:2)
        #expect(prompt.content.messages.last?.content == "{{history}}")
        let url = try #require(await stub.requests.first?.url)
        #expect(url.absoluteString.contains("folder%2Fprompt"))
        #expect(url.query?.contains("resolve=false") == true && url.query?.contains("version=2") == true)
    }
    @Test func scoresReadPolymorphicValuesAndFollowV3Cursors() async throws {
        let stub = BackendStub([(200,#"{"data":[{"id":"one","name":"numeric","dataType":"NUMERIC","value":4.5}],"meta":{"cursor":"next"}}"#),(200,#"{"data":[{"id":"two","name":"salle215-review-thumbs","dataType":"BOOLEAN","value":false,"comment":"why","subject":{"kind":"trace","id":"t"},"metadata":{"reasons":["Incorrect"]}},{"id":"three","name":"category","dataType":"CATEGORICAL","value":"great"}],"meta":{}}"#)])
        let result = try await client(stub).scores(traceID:"t")
        #expect(result.count == 3)
        #expect(result.first { $0.id == "two" }?.rating?.score == .needsWork)
        #expect(result.first { $0.id == "two" }?.rating?.reasons == ["Incorrect"])
        #expect(result.first { $0.id == "one" }?.formatted == 4.5.formatted(.number.precision(.fractionLength(0...3))))
        for request in await stub.requests { #expect(request.url?.path == "/api/public/v3/scores") }
        #expect(await stub.requests.last?.url?.query?.contains("cursor=next") == true)
    }
    @Test func reviewRetriesAreIdempotentAndUndoUsesOnlyOwnScore() async throws {
        actor ReviewAPI {
            var requests: [URLRequest] = []; var first = true
            func send(_ r: URLRequest) throws -> (Data, HTTPURLResponse) {
                requests.append(r)
                if first { first = false; throw URLError(.timedOut) }
                let body = r.httpBody.flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] }
                let data = try JSONSerialization.data(withJSONObject:["id":body?["id"] as? String ?? ""])
                return (data,HTTPURLResponse(url:r.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
            }
        }
        let api = ReviewAPI(), backend = LiveBackendStore()
        backend.configure(LangfuseClient(credentials:try .init(host:"https://example.com",publicKey:"pk",secretKey:"sk"),transport:{ try await api.send($0) }))
        await #expect(throws: URLError.self) { try await backend.saveReview("t",good:false,reasons:["Incorrect"],comment:" bad ") }
        #expect(backend.rating("t") == nil && backend.saving.isEmpty)
        try await backend.saveReview("t",good:false,reasons:["Incorrect"],comment:" bad ")
        #expect(backend.rating("t")?.comment == "bad")
        let requests = await api.requests
        let first = try #require(JSONSerialization.jsonObject(with:requests[0].httpBody!) as? [String:Any])
        let second = try #require(JSONSerialization.jsonObject(with:requests[1].httpBody!) as? [String:Any])
        #expect(first["id"] as? String == second["id"] as? String)
        #expect(second["value"] as? Int == 0 && second["dataType"] as? String == "BOOLEAN")
        #expect(requests[1].url?.path == "/api/public/scores" && requests[1].httpMethod == "POST")
        await #expect(throws: ReviewError.self) { try await backend.saveReview("t",good:true) }
        try await backend.undoReview("t")
        #expect(backend.rating("t") == nil && backend.ownScores.isEmpty)
        #expect(await api.requests.last?.httpMethod == "DELETE")
    }
    @Test func failedReviewAndDeleteDoNotChangeSavedState() async throws {
        let stub = BackendStub([(403,"{}")]), backend = LiveBackendStore()
        backend.configure(try client(stub))
        await #expect(throws: LangfuseError.self) { try await backend.saveReview("t",good:true) }
        #expect(backend.rating("t") == nil && backend.ownScores.isEmpty && backend.saving.isEmpty)
    }
    @Test func disconnectClearsEveryBackendCache() async throws {
        let stub = BackendStub([(200,#"{"data":[],"meta":{"page":1,"totalPages":1}}"#),(200,#"{"data":[],"meta":{}}"#)]), backend = LiveBackendStore()
        backend.configure(try client(stub)); await backend.loadPrompts(); try await backend.loadScores("t")
        #expect(backend.promptPage == 1 && backend.traceScores["t"] != nil)
        backend.configure(nil)
        #expect(backend.promptPage == 0 && backend.traceScores.isEmpty && backend.promptRecords.isEmpty)
    }

    @Test func comparisonIncludesRepeatedChatRolesAndLongPrompts() {
        let before = MessageContent.messages([.init(role:"user",content:"First."),.init(role:"user",content:"Second old.")])
        let after = MessageContent.messages([.init(role:"user",content:"First."),.init(role:"user",content:"Second new.")])
        let prompt = PromptRecord(name:"p",type:"chat",updated:.now,versionCount:2,labels:["production":1],versions:[.init(version:1,commitMessage:nil,prompt:before),.init(version:2,commitMessage:nil,prompt:after)])
        #expect(prompt.diff.count == 2 && prompt.diff.first?.unchanged == true)
        #expect(prompt.diff.last?.lines.contains { $0.kind == .added && $0.text == "Second new." } == true)
        let a = (0..<1500).map { "Old \($0)." }.joined(separator:"\n")
        let b = (0..<1500).map { "New \($0)." }.joined(separator:"\n")
        let large = PromptRecord(name:"large",type:"text",updated:.now,versionCount:2,labels:["production":1],versions:[.init(version:1,commitMessage:nil,prompt:.text(a)),.init(version:2,commitMessage:nil,prompt:.text(b))])
        #expect(large.addedCount == 1500 && large.removedCount == 1500)
    }

    @Test func concurrentOverviewWindowsShareRequests() async throws {
        let stub = BackendStub([(200,activity),(200,roots),(200,trend),(200,scores)]), metrics = LiveMetricsStore()
        metrics.configure(try client(stub))
        async let a: Void = metrics.load(.day)
        async let b: Void = metrics.load(.day)
        _ = await (a,b)
        #expect(await stub.requests.count == 4)
    }

    @Test func promptProductionAndRequestedVersionAreLoadedWithoutFetchingAllVersions() async throws {
        let stub = BackendStub([(200,#"{"data":[{"name":"p","type":"text","versions":[1,2,3,4],"labels":["production","latest"],"lastUpdatedAt":"2026-10-10T10:00:00Z"}],"meta":{"page":1,"totalPages":1}}"#),(200,#"{"name":"p","type":"text","version":4,"labels":["latest"],"prompt":"Latest"}"#),(200,#"{"name":"p","type":"text","version":2,"labels":["production"],"prompt":"Production"}"#),(200,#"{"name":"p","type":"text","version":1,"labels":[],"prompt":"Old"}"#)])
        let backend = LiveBackendStore(); backend.configure(try client(stub))
        await backend.loadPrompts()
        let record = try await backend.loadPrompt("p")
        #expect(record.production == 2 && record.latest == 4 && record.versionCount == 4)
        #expect(record.comparison?.from == 2 && record.comparison?.to == 4)
        let old = try await backend.loadPrompt("p",version:1)
        #expect(old.versions.map(\.version) == [1,2,4])
        _ = try await backend.loadPrompt("p",version:1)
        #expect(await stub.requests.count == 4)
    }

    @Test func observationsRateLimitSuppressesRetriesButNotMetricBucket() async throws {
        let stub = BackendStub([(429,"{}"),(200,roots)]), client = try client(stub)
        await #expect(throws:LangfuseError.self) { try await client.observations(from:.now.addingTimeInterval(-3600),to:.now) }
        await #expect(throws:LangfuseError.self) { try await client.observations(from:.now.addingTimeInterval(-3600),to:.now) }
        _ = try await client.metrics(.init(measures:[("count","count")],from:.now.addingTimeInterval(-3600),to:.now))
        #expect(await stub.requests.count == 2)
    }
}
