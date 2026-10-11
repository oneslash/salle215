import Foundation
import Testing
@testable import Salle215

@MainActor
struct AppStoreTests {
    @Test func sampleDatasetSupportsRouting() {
        let data = SampleDataset.load()
        #expect(data.traces.count == 7)
        #expect(data.review.count == 3)
        // Routes identify traces by ID and steps by ID within their trace.
        #expect(Set(data.traces.map(\.id)).count == data.traces.count)
        for trace in data.traces {
            #expect(Set(trace.spans.map(\.id)).count == trace.spans.count)
            if let reference = trace.prompt { #expect(data.prompt(reference.name)?.version(reference.version) != nil) }
        }
        for item in data.review { #expect(data.trace(item.traceID) != nil) }
    }

    @Test func attentionCountsMatchTheTracesTheyOpen() {
        let store = AppStore(reset: true)
        for range in TimeRange.allCases {
            for item in store.attention(in: range) {
                let window = WindowState()
                window.range = range
                window.showTraces(item.filter, name: item.name)
                #expect(store.traces(window.filter, name: window.traceName, in: window.range).count == item.count)
            }
        }
        #expect(store.attention(in: .hour).map(\.id) == ["error-answer-question", "slow-answer-question", "slow-summarize-thread"])
        #expect(store.attention(in: .day).first == AttentionItem(filter: .error, name: "answer-question", count: 2, slowest: 10))
    }

    @Test func overviewActionsFilterTracesWithinTheTimeRange() {
        let store = AppStore(reset: true)
        let window = WindowState()
        func visible() -> [String] {
            store.traces(window.filter, name: window.traceName, in: window.range).map(\.id)
        }
        window.showTraces(.slow, name: "summarize-thread")
        #expect(visible() == ["2E91"])
        window.tracePath = [.trace("2E91")]
        window.openMetric(.errors)
        #expect(window.tracePath.isEmpty)
        #expect(window.tab == .traces)
        #expect(visible() == ["7F3A", "B41C"])
        window.range = .hour
        #expect(visible() == ["7F3A"])
        window.range = .week
        window.filter = .all
        #expect(visible().last == "5A08")
        window.range = .day
        window.openMetric(.latency)
        #expect(visible() == ["7F3A", "2E91"])
        window.openMetric(.quality)
        #expect(window.tab == .review)
    }

    @Test func searchCoversIDsSessionsUsersOutputAndErrors() {
        let store = AppStore(reset: true)
        for (query, expected) in [("  7f3a  ", ["7F3A"]), ("a8f2", ["7F3A", "9C2B"]),
                                  ("u_4821", ["7F3A", "9C2B"]), ("REFUNDED", ["D0E4"]), ("TimeoutError", ["7F3A"]),
                                  ("not in this dataset", []), ("  ", [])] {
            #expect(store.search(query).map(\.id) == expected)
        }
    }

    @Test func statusComesFromFailedStepsAndLatency() {
        let sample = SampleDataset.load()
        func step(_ id: String, depth: Int, end: Double, level: String? = nil) -> TraceSpan {
            TraceSpan(id: id, name: id, type: .span, depth: depth, start: 0, end: end, input: nil, output: nil,
                      level: level, statusMessage: nil, model: nil, usage: nil, cost: nil, promptName: nil, promptVersion: nil)
        }
        func trace(_ id: String, duration: Double, failing: Bool = false) -> TraceRecord {
            TraceRecord(id: id, name: "threshold-test", timestamp: .now, session: "test", user: "test",
                        spans: [step("\(id).1", depth: 0, end: duration),
                                step("\(id).2", depth: 1, end: duration, level: failing ? "ERROR" : nil)])
        }
        let traces = [trace("at-threshold", duration: 5), trace("below-threshold", duration: 4.999),
                      trace("timeout", duration: 10, failing: true)]
        #expect(traces.map(\.status) == [.slow, .ok, .error])
        let data = SampleDataset(snapshots: sample.snapshots, metrics: sample.metrics, traces: traces,
                                 review: sample.review, prompts: sample.prompts)
        let store = AppStore(data: data, reset: true)
        #expect(store.traces(.slow, in: .hour).map(\.id) == ["at-threshold", "timeout"])
        #expect(store.traces(.error, in: .hour).map(\.id) == ["timeout"])
    }

    @Test func transcriptsSummarizeToTheLatestUserTurn() {
        let transcript = MessageContent.messages([.init(role: "system", content: "Rules"), .init(role: "user", content: "First"),
                                                  .init(role: "assistant", content: "Reply"), .init(role: "user", content: "Second")])
        #expect(transcript.summary == "Second")
        #expect(MessageContent.messages([.init(role: "assistant", content: "Only reply")]).summary == "Only reply")
    }

    @Test func windowsReviewIndependently() {
        let store = AppStore(reset: true)
        let first = WindowState(), second = WindowState()
        first.skipReview(in: store)
        #expect(first.currentReview(in: store)?.id == "9C2B")
        #expect(second.currentReview(in: store)?.id == "7C1D")

        #expect(second.rate(.good, for: "7C1D", in: store))
        first.undoReview(in: store)
        // Undo in one window never reverts another window's rating, and answers rated elsewhere drop out.
        #expect(store.ratings["7C1D"]?.score == .good)
        #expect(first.currentReview(in: store)?.id == "9C2B")
        #expect(second.reviewUndo?.rated == true)
    }

    @Test func feedbackCannotOverwriteAnAnswerRatedInAnotherWindow() {
        let suite = "Salle215Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults)
        let window = WindowState(), other = WindowState()
        let feedbackID = window.currentReview(in: store)!.id

        #expect(other.rate(.good, for: feedbackID, in: store))
        #expect(!window.rate(.needsWork, for: feedbackID, reasons: ["Incomplete"], comment: "Draft for the previous answer", in: store))
        #expect(!window.rate(.good, for: "missing-review", in: store))

        #expect(store.ratings[feedbackID]?.score == .good)
        #expect(window.currentReview(in: store)?.id == "9C2B")
        #expect(window.reviewUndo == nil)
        #expect(store.pendingReviews == 2)
        #expect(AppStore(defaults: defaults).ratings == store.ratings)
    }

    @Test func feedbackForASkippedAnswerDoesNotAdvanceTheCurrentAnswer() {
        let store = AppStore(reset: true)
        let window = WindowState()
        let feedbackID = window.currentReview(in: store)!.id
        window.skipReview(in: store)
        let nextID = window.currentReview(in: store)!.id

        #expect(window.rate(.needsWork, for: feedbackID, reasons: ["Incomplete"], comment: "  Original answer feedback  ", in: store))
        #expect(store.ratings[feedbackID]?.comment == "Original answer feedback")
        #expect(store.ratings[nextID] == nil)
        #expect(window.currentReview(in: store)?.id == nextID)
        #expect(store.pendingReviews == 2)

        window.undoReview(in: store)
        #expect(window.currentReview(in: store)?.id == feedbackID)
        #expect(store.ratings[feedbackID] == nil)
        #expect(store.pendingReviews == 3)
    }

    @Test func skipKeepsAnAnswerInTheQueueAndRatingAdvances() {
        let store = AppStore(reset: true)
        let window = WindowState()
        let firstID = window.currentReview(in: store)!.id
        window.skipReview(in: store)
        #expect(window.currentReview(in: store)?.id != firstID)
        #expect(store.pendingReviews == 3)
        window.rate(.good, for: window.currentReview(in: store)!.id, in: store)
        #expect(store.pendingReviews == 2)
        window.rate(.needsWork, for: window.currentReview(in: store)!.id, reasons: ["Incorrect"], comment: "  Refund window is 30 days.  ", in: store)
        #expect(store.ratings["D0E4"]?.comment == "Refund window is 30 days.")
        #expect(window.currentReview(in: store)?.id == firstID)
        window.rate(.good, for: firstID, in: store)
        #expect(window.currentReview(in: store) == nil)
        #expect(store.pendingReviews == 0)
        window.undoReview(in: store)
        #expect(window.currentReview(in: store)?.id == firstID)
        #expect(store.pendingReviews == 1)
    }

    @Test func onlyTheLatestActionCanBeUndone() {
        let store = AppStore(reset: true)
        let window = WindowState()
        window.rate(.good, for: "7C1D", in: store)
        window.skipReview(in: store)
        window.undoReview(in: store)
        #expect(window.currentReview(in: store)?.id == "9C2B")
        #expect(window.reviewUndo == nil)
        window.undoReview(in: store)
        #expect(store.ratings["7C1D"]?.score == .good)
        #expect(window.currentReview(in: store)?.id == "9C2B")
    }

    @Test func ratingsPersistAndCanBeUndone() {
        let suite = "Salle215Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults)
        let window = WindowState()
        store.connectSample()
        window.rate(.needsWork, for: "7C1D", reasons: ["Incomplete"], comment: "Include expiry.", in: store)
        let restored = AppStore(defaults: defaults)
        #expect(restored.isConnected)
        #expect(restored.pendingReviews == 2)
        #expect(restored.ratings["7C1D"]?.reasons == ["Incomplete"])
        #expect(WindowState().currentReview(in: restored)?.id == "9C2B")
        window.undoReview(in: store)
        #expect(AppStore(defaults: defaults).pendingReviews == 3)
        restored.disconnect()
        #expect(!AppStore(defaults: defaults).isConnected)
    }

    @Test func uiTestingDoesNotOverwriteSavedReviews() {
        let suite = "Salle215Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let normal = AppStore(defaults: defaults)
        normal.connectSample()
        normal.rate(.good, for: "7C1D")
        let testing = AppStore(defaults: defaults, reset: true)
        testing.connectSample()
        testing.rate(.needsWork, for: "7C1D")
        testing.disconnect()
        #expect(AppStore(defaults: defaults).isConnected)
        #expect(AppStore(defaults: defaults).ratings["7C1D"]?.score == .good)
    }

    @Test func promptComparisonPreservesSharedContent() {
        let prompt = SampleDataset.load().prompt("support/answer")!
        #expect(prompt.addedCount == 3)
        #expect(prompt.removedCount == 3)
        #expect(prompt.diff.first { $0.role == "user" }?.unchanged == true)
        #expect(prompt.diff.first { $0.role == "system" }?.lines.first?.kind == .same)
        #expect(prompt.diff.flatMap(\.lines).contains { $0.kind == .added && $0.text.contains("link expiry") })
    }

    @Test func promptComparisonFollowsLabels() {
        let data = SampleDataset.load()
        let answer = data.prompt("support/answer")!, classify = data.prompt("support/classify")!
        #expect(answer.comparison.map { [$0.from, $0.to] } == [12, 13])
        #expect(answer.title(for: 13) == "v13 · staging")
        // Without a staging label, production is compared with the newest version, which "latest" already implies.
        #expect(classify.comparison.map { [$0.from, $0.to] } == [4, 5])
        #expect(classify.title(for: 5) == "v5")
        #expect(classify.folder == "support")
        #expect(classify.shortName == "classify")

        func prompt(labels: [String: Int]) -> PromptRecord {
            PromptRecord(name: "draft", type: "text", updated: .now, versionCount: 3, labels: labels,
                         versions: (1...3).map { PromptVersion(version: $0, commitMessage: nil, prompt: .text("Version \($0)")) })
        }
        #expect(prompt(labels: [:]).comparison.map { [$0.from, $0.to] } == [2, 3])
        #expect(prompt(labels: ["production": 3]).comparison == nil)
        #expect(prompt(labels: [:]).folder == nil)
    }
}
