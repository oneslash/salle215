import SwiftUI
import Observation

struct BackendErrorView: View {
    let error: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(error).font(.footnote).foregroundStyle(Palette.red)
            Button("Retry", action: retry)
        }.padding(.vertical, 14)
    }
}

@MainActor @Observable
final class ObservationResults {
    var rows: [LangfuseObservation] = []
    var cursor: String?
    var loading = false
    var error: String?
    var from = Date.now
    var to = Date.now
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var seen = Set<String>()
    var traces: [TraceRecord] { ObservationMapper.traces(rows) }
    func load(store: AppStore, range: TimeRange, session: String? = nil, search: ObservationSearch? = nil, more: Bool = false) async {
        if more && (loading || cursor == nil) { return }
        if !more {
            generation = UUID(); rows = []; cursor = nil; seen = []
            to = .now; from = to.addingTimeInterval(-range.seconds)
        }
        let generation = generation
        loading = true; error = nil
        do {
            let page = try await store.observationPage(cursor: more ? cursor : nil, sessionID: session, search: search, from: from, to: to)
            guard generation == self.generation else { return }
            if let next = page.meta.cursor, !seen.insert(next).inserted { throw LangfuseError.pagination }
            rows.append(contentsOf: page.data); cursor = page.meta.cursor
        } catch is CancellationError {} catch { if generation == self.generation { self.error = error.localizedDescription } }
        if generation == self.generation { loading = false }
    }
    func clear() { generation = UUID(); rows = []; cursor = nil; loading = false; error = nil; seen = [] }
}

struct LiveSearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(WindowState.self) private var window
    @State private var scope: SearchScope = .name
    @State private var results = ObservationResults()
    @State private var attempt = 0
    private var text: String { window.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var search: ObservationSearch { .init(scope: scope, text: text) }
    private var key: String { "\(scope.rawValue)|\(text)|\(window.range.title)|\(attempt)" }
    var body: some View {
        @Bindable var window = window
        Screen {
            HStack {
                Picker("Search in", selection: $scope) { ForEach(SearchScope.allCases) { Text($0.title).tag($0) } }
                Spacer()
                Picker("Time range", selection: $window.range) { ForEach(TimeRange.allCases) { Text($0.title).tag($0) } }
            }.padding(.top, 12)
            Text("Searches Langfuse in the selected period and environment. IDs match exactly; input and output use indexed text search.")
                .font(.caption).foregroundStyle(Palette.muted)
            if text.isEmpty { ContentUnavailableView("Search Langfuse", systemImage: "magnifyingglass", description: Text("Choose a field and enter an ID or text.")) }
            else {
                if results.loading { ProgressView("Searching…").padding(.top, 18) }
                if let error = results.error { BackendErrorView(error: error) { attempt += 1 } }
                SectionHeading(title: "Matching traces", detail: "\(results.traces.count)")
                TraceList(traces: results.traces)
                if results.traces.isEmpty && !results.loading { Button("Clear search") { window.query = "" }.padding(.top, 12) }
                if let _ = results.cursor {
                    Button("Load more matching steps") { Task { await results.load(store: store, range: window.range, search: search, more: true) } }.disabled(results.loading)
                }
                Text("Results group matching steps by trace ID. Open a trace to load all its steps.").font(.caption).foregroundStyle(Palette.muted).padding(.top, 12)
            }
        }.navigationTitle("Search")
            .searchable(text: $window.query, placement: .navigationBarDrawer(displayMode: .always), prompt: scope.title)
            .autocorrectionDisabled().textInputAutocapitalization(.never)
            .refreshable { if !text.isEmpty { await results.load(store: store, range: window.range, search: search) } }
            .task(id: key) {
                results.clear()
                guard !text.isEmpty else { return }
                do { try await Task.sleep(for: .milliseconds(500)); try Task.checkCancellation() } catch { return }
                await results.load(store: store, range: window.range, search: search)
            }
    }
}

struct LiveSessionView: View {
    @Environment(AppStore.self) private var store
    let sessionID: String
    @State private var results = ObservationResults()
    @State private var attempt = 0
    var body: some View {
        Screen {
            ScreenTitle(title: sessionID, subtitle: "Last 7 days · \(results.traces.count) loaded traces")
            if results.loading { ProgressView("Loading session…").padding(.top, 16) }
            if let error = results.error { BackendErrorView(error: error) { attempt += 1 } }
            SectionHeading(title: "Traces")
            TraceList(traces: results.traces)
            if results.cursor != nil {
                Button("Load more session steps") { Task { await results.load(store: store, range: .week, session: sessionID, more: true) } }.disabled(results.loading)
            }
            Text("Session steps are read from Langfuse and grouped by trace ID. Earlier activity may be outside this window.").font(.caption).foregroundStyle(Palette.muted).padding(.top, 16)
        }.navigationTitle("Session").navigationBarTitleDisplayMode(.inline)
            .refreshable { await results.load(store: store, range: .week, session: sessionID) }
            .task(id: attempt) { await results.load(store: store, range: .week, session: sessionID) }
    }
}

struct LivePromptsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Screen {
            ScreenTitle(title: "Prompts")
            if store.backend.promptLoading { ProgressView("Loading prompts…").padding(.top, 16) }
            if let error = store.backend.promptError { BackendErrorView(error: error) { Task { await store.backend.loadPrompts(refresh: true) } } }
            if store.backend.prompts.isEmpty && !store.backend.promptLoading && store.backend.promptError == nil {
                ContentUnavailableView("No prompts", systemImage: "doc.text", description: Text("Create a managed prompt in this Langfuse project to see it here."))
            }
            SurfaceGroup {
                ForEach(store.backend.prompts) { prompt in
                    if prompt.id != store.backend.prompts.first?.id { RowDivider() }
                    NavigationLink(value: AppRoute.prompt(prompt.name)) {
                        RelatedRow(title: prompt.name, detail: "\(prompt.type.capitalized) · \(prompt.versions.count) versions · \(prompt.labels.joined(separator: ", "))", symbol: "doc.text")
                    }.buttonStyle(.plain).accessibilityIdentifier("prompt-\(prompt.name)")
                }
            }.padding(.top, 20)
            if store.backend.promptHasMore && !store.backend.prompts.isEmpty {
                Button("Load more prompts") { Task { await store.backend.loadPrompts(more: true) } }.disabled(store.backend.promptLoading)
            }
        }.task { await store.backend.loadPrompts() }
            .refreshable { await store.backend.loadPrompts(refresh: true) }
    }
}

struct LivePromptView: View {
    @Environment(AppStore.self) private var store
    let name: String
    let initialVersion: Int?
    var changes = false
    @State private var selected: Int?
    @State private var record: PromptRecord?
    @State private var error: String?
    @State private var loading = false
    @State private var attempt = 0
    private var versionNumbers: [Int] { store.backend.prompts.first { $0.name == name }?.versions.sorted(by: >) ?? record?.versions.map(\.version).sorted(by: >) ?? [] }
    var body: some View {
        Group {
            if changes, let record { PromptChangesView(prompt: record) }
            else {
                Screen {
                    ScreenTitle(title: name, subtitle: "Managed prompt")
                    if !versionNumbers.isEmpty {
                        Picker("Prompt version", selection: $selected) {
                            ForEach(versionNumbers, id: \.self) { number in Text(record?.title(for: number) ?? "v\(number)").tag(Optional(number)) }
                        }.pickerStyle(.menu).padding(.top, 18).accessibilityIdentifier("promptVersion")
                    }
                    if loading { ProgressView("Loading version…").padding(.top, 16) }
                    if let error { BackendErrorView(error: error) { attempt += 1 } }
                    if let record, let version = selected, let content = record.version(version) {
                        if let note = content.commitMessage { Text(note).font(.footnote).foregroundStyle(Palette.muted).padding(.top, 12) }
                        SectionHeading(title: "Content")
                        ContentBlocks(content: content.prompt)
                        if let comparison = record.comparison {
                            SurfaceGroup {
                                NavigationLink(value: AppRoute.changes(name)) { RelatedRow(title: "Compare v\(comparison.from) → v\(comparison.to)", detail: "Production against latest, or the two latest versions", symbol: "arrow.left.arrow.right") }.buttonStyle(.plain)
                            }.padding(.top, 24)
                        }
                    }
                }
            }
        }.navigationTitle(changes ? "Changes" : "Prompt").navigationBarTitleDisplayMode(.inline)
            .task(id: "\(selected ?? initialVersion ?? -1):\(attempt)") {
                loading = true; error = nil
                do {
                    await store.backend.loadPrompts()
                    let loaded = try await store.backend.loadPrompt(name, version: selected ?? initialVersion)
                    try Task.checkCancellation()
                    record = loaded
                    if selected == nil { selected = initialVersion ?? loaded.production ?? loaded.latest }
                } catch is CancellationError {} catch { self.error = error.localizedDescription }
                loading = false
            }
    }
}

struct LiveScoresView: View {
    @Environment(AppStore.self) private var store
    let traceID: String
    @State private var error: String?
    @State private var loading = false
    @State private var attempt = 0
    var body: some View {
        SectionHeading(title: "Scores", detail: store.backend.traceScores[traceID].map { "\($0.count)" })
        if loading { ProgressView("Loading scores…") }
        if let error { BackendErrorView(error: error) { attempt += 1 } }
        if let scores = store.backend.traceScores[traceID] {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(scores) { score in
                    TraceScoreRow(score: score)
                }
                if scores.isEmpty { Text("No scores recorded").font(.subheadline).foregroundStyle(Palette.muted).padding(.vertical, 8) }
            }
        }
        Color.clear.frame(height: 0).task(id: "\(traceID):\(attempt)") {
            loading = true; error = nil
            do { try await store.backend.loadScores(traceID, refresh: attempt > 0) }
            catch is CancellationError {} catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

private struct TraceScoreRow: View {
    let score: RemoteScore
    private var rating: ReviewRating? { score.rating }
    private var color: Color {
        guard let rating else { return Palette.ink }
        return rating.score == .good ? Palette.green : Palette.orange
    }
    private var title: String {
        guard let rating else { return score.formatted }
        return rating.score == .good ? "Good" : "Needs work"
    }
    private var symbol: String {
        guard let rating else {
            if case .bool(let value) = score.value { return value ? "checkmark.circle" : "xmark.circle" }
            return score.dataType == "NUMERIC" ? "number" : "textformat"
        }
        return rating.score == .good ? "hand.thumbsup.fill" : "hand.thumbsdown.fill"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(score.dataType.lowercased()) · \(score.formatted)").font(.subheadline)
                    if let subject = score.subject {
                        Text("\(subject.kind.capitalized) ID: \(subject.id)")
                            .font(.caption).foregroundStyle(Palette.muted).textSelection(.enabled)
                    }
                    if let rating, !rating.reasons.isEmpty {
                        Text(rating.reasons.joined(separator: " · ")).font(.subheadline)
                    }
                }.padding(.top, 8)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(color).frame(width: 24).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.body.weight(.semibold)).foregroundStyle(color)
                        Text(score.name).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                }.frame(minHeight: 44, alignment: .leading)
            }.tint(Palette.muted).accessibilityIdentifier("score-\(score.id)")
            if let comment = score.comment, !comment.isEmpty {
                Text(comment).font(.subheadline).textSelection(.enabled).padding(.leading, 36)
            }
        }.padding(.vertical, 4)
    }
}

struct LiveReviewView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedID: String?
    @State private var loadedID: String?
    @State private var loading = false
    @State private var error: String?
    @State private var attempt = 0
    @State private var reasons = Set<String>()
    @State private var comment = ""
    @State private var feedback = false
    @State private var contextExpanded = false
    @State private var retryAction: (@MainActor () async throws -> Void)?
    private let options = ["Incorrect", "Incomplete", "Ignores context", "Tone", "Other"]
    private var trace: TraceRecord? { selectedID.flatMap { store.data.trace($0) } ?? store.data.traces.first }
    private var position: Int { store.data.traces.firstIndex { $0.id == trace?.id } ?? 0 }
    private var key: String { "\(trace?.id ?? "empty"):\(store.liveTo.timeIntervalSince1970):\(attempt)" }
    private var busy: Bool { loading || trace.map { store.backend.saving.contains($0.id) } == true }
    private var canRate: Bool {
        guard let trace, loadedID == trace.id, store.backend.rating(trace.id) == nil else { return false }
        return trace.output != nil || trace.spans.contains { $0.type == .generation && $0.output != nil }
    }
    var body: some View {
        ScrollViewReader { scroll in
            Screen(horizontalPadding: 24) {
                ReviewHeader(progress: trace == nil ? nil : "\(position + 1) of \(store.data.traces.count)", skip: trace == nil ? nil : {
                    selectedID = store.data.traces[min(position + 1, store.data.traces.count - 1)].id
                }, skipDisabled: position >= store.data.traces.count - 1 || busy)
                    .id("reviewTop")
                if loading { ProgressView("Loading answer and reviews…").padding(.top, 16) }
                if let error { BackendErrorView(error: error) {
                    if let retryAction { run(retryAction) } else { attempt += 1 }
                } }
                if let trace {
                    if loadedID == trace.id {
                        let input = trace.input ?? trace.spans.first(where: { $0.type == .generation })?.input
                        let output = trace.output ?? trace.spans.last(where: { $0.type == .generation })?.output
                        ReviewConversation(question: input?.summary, answer: output).padding(.top, 24)
                        if output == nil {
                            Text("No answer output recorded. Open the trace to inspect its steps.").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 16)
                        }
                        if let rating = store.backend.rating(trace.id) {
                            Label(rating.score == .good ? "Reviewed as good" : "Reviewed as needs work", systemImage: "checkmark.circle").padding(.top, 20)
                            if !rating.comment.isEmpty { Text(rating.comment).font(.subheadline) }
                            if store.backend.ownScores[trace.id] != nil {
                                Button("Undo saved review") { run { try await store.backend.undoReview(trace.id) } }.disabled(busy).padding(.top, 10)
                            }
                        } else if output != nil {
                            if feedback {
                                Text("What needs work?").font(.headline).padding(.top, 24)
                                ReviewReasonChoices(options: options, reasons: $reasons).padding(.top, 12)
                                TextField("Note (optional)", text: $comment, axis: .vertical).lineLimit(3...6)
                                    .textFieldStyle(.plain).padding(.top, 16)
                                Button("Save rating") { save(trace.id, good: false) }
                                    .font(.body.weight(.semibold)).foregroundStyle(Palette.green).frame(minHeight: 44)
                                    .disabled(busy).padding(.top, 14)
                                Button("Cancel feedback") { feedback = false }.padding(.top, 12)
                            } else if canRate {
                                ReviewDecisions(needsWork: { feedback = true }, good: { save(trace.id, good: true) }, needsWorkID: "Needs work", goodID: "Good")
                                    .disabled(busy).padding(.top, 24)
                            }
                        }
                        let retrievers = trace.spans.filter { $0.type == .retriever && $0.output != nil }
                        if !retrievers.isEmpty {
                            ReviewSources(title: "\(retrievers.count) retrieval \(retrievers.count == 1 ? "step" : "steps")", expanded: $contextExpanded) {
                                ForEach(retrievers) { span in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(span.name).font(.subheadline.weight(.semibold))
                                        if let output = span.output {
                                            let text = switch output {
                                            case .text(let text): text
                                            case .messages(let messages): messages.map { "\($0.role.capitalized)\n\($0.content)" }.joined(separator: "\n\n")
                                            }
                                            Text(text).font(.subheadline).foregroundStyle(Palette.muted).textSelection(.enabled)
                                        }
                                    }
                                }
                            }.padding(.top, 28)
                        }
                        ReviewTraceLink(traceID: trace.id).padding(.top, retrievers.isEmpty ? 28 : 8)
                    }
                    if position > 0 {
                        Button("Previous answer") { selectedID = store.data.traces[position - 1].id }
                            .disabled(busy).frame(minHeight: 44).padding(.top, 8)
                    }
                } else if !loading {
                    ContentUnavailableView("No traces to review", systemImage: "checkmark.circle", description: Text("Load activity or refresh the connection to find answers."))
                }
                if store.nextCursor != nil { Button("Load more traces") { Task { await store.loadMoreObservations() } }.disabled(store.isLoading || busy).padding(.top, 20) }
                if trace != nil { Text("Ratings are saved to Langfuse.").font(.caption).foregroundStyle(Palette.muted).padding(.top, 16) }
            }
            .onChange(of: trace?.id) { scroll.scrollTo("reviewTop", anchor: .top) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: key) {
            guard let id = trace?.id else { return }
            selectedID = id
            retryAction = nil
            loading = true; loadedID = nil; error = nil; feedback = false; contextExpanded = false; reasons = []; comment = ""
            do {
                try await store.loadTrace(id)
                try await store.backend.loadScores(id)
                try Task.checkCancellation()
                loadedID = id
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
            loading = false
        }
    }
    private func save(_ id: String, good: Bool) {
        let reasons = good ? [] : options.filter { self.reasons.contains($0) }
        let note = good ? "" : comment
        run { try await store.backend.saveReview(id, good: good, reasons: reasons, comment: note); feedback = false }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        error = nil
        retryAction = action
        Task { do { try await action(); retryAction = nil } catch is CancellationError {} catch { self.error = error.localizedDescription } }
    }
}
