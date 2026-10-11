import Foundation
import Testing
@testable import Salle215

@MainActor struct RealBackendTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SALLE215_REAL_ENV"] != nil))
    func readOnlyLiveProjectSmokeTest() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["SALLE215_REAL_ENV"])
        let text = try String(contentsOfFile:path,encoding:.utf8)
        var values: [String:String] = [:]
        for raw in text.components(separatedBy:.newlines) {
            let line = raw.trimmingCharacters(in:.whitespaces).replacingOccurrences(of:"export ",with:"")
            guard !line.hasPrefix("#"), let split = line.firstIndex(of:"=") else { continue }
            values[String(line[..<split]).trimmingCharacters(in:.whitespaces)] = String(line[line.index(after:split)...]).trimmingCharacters(in:.whitespaces).trimmingCharacters(in:CharacterSet(charactersIn:"\"'"))
        }
        let credentials = try LangfuseCredentials(host: try #require(values["LANGFUSE_BASE_URL"] ?? values["LANGFUSE_HOST"]),publicKey:try #require(values["LANGFUSE_PUBLIC_KEY"]),secretKey:try #require(values["LANGFUSE_SECRET_KEY"]))
        let client = LangfuseClient(credentials:credentials), metrics = LiveMetricsStore()
        metrics.configure(client)
        for range in TimeRange.allCases {
            await metrics.load(range)
            #expect(metrics.state(range).data?.failures.isEmpty == true)
        }
        let to = Date.now, from = to.addingTimeInterval(-604800)
        let page = try await client.observations(from:from,to:to)
        if let name = page.data.first?.name {
            let matches = try await client.observations(from:from,to:to,search:.init(scope:.name,text:name))
            #expect(!matches.data.isEmpty)
        }
        if let id = page.data.compactMap(\.traceId).first {
            let trace = try #require(try await client.trace(id,from:from,to:to))
            #expect(!trace.spans.isEmpty)
            _ = try await client.scores(traceID:id)
            if !trace.session.isEmpty {
                let session = try await client.observations(from:from,to:to,sessionID:trace.session)
                #expect(!session.data.isEmpty)
            }
        }
        let prompts = try await client.prompts(page:1)
        if let first = prompts.data.first, let version = first.versions.max() {
            let prompt = try await client.prompt(first.name,version:version)
            #expect(prompt.name == first.name && prompt.version == version)
        }
        let overview = try #require(metrics.state(.week).data)
        for kind in [MetricKind.errors, .latency, .spend, .quality] {
            let score = overview.scoreAggregates.first
            await metrics.loadBreakdown(kind,range:.week,score:score)
            #expect(metrics.breakdowns[metrics.detailKey(kind,range:.week,score:score)]?.error == nil)
        }
        // Intentionally no score POST or DELETE against real project data.
    }
}
