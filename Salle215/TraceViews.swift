import SwiftUI

struct AppDestinations: ViewModifier {
    @Environment(AppStore.self) private var store
    func body(content: Content) -> some View {
        content.navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .trace(let id):
                if store.isLive { LiveTraceDetailView(traceID: id) }
                else if let trace = store.data.trace(id) { TraceDetailView(trace: trace) }
            case .span(let traceID, let id):
                if let trace = store.data.trace(traceID),
                   let span = trace.spans.first(where: { $0.id == id }) { SpanDetailView(trace: trace, span: span) }
            case .session(let id):
                if store.isLive { LiveSessionView(sessionID: id) } else { SessionView(sessionID: id) }
            case .prompt(let name, let version):
                if store.isLive { LivePromptView(name: name, initialVersion: version) }
                else if let prompt = store.data.prompt(name) { PromptDetailView(prompt: prompt, version: version) }
            case .changes(let name):
                if store.isLive { LivePromptView(name: name, initialVersion: nil, changes: true) }
                else if let prompt = store.data.prompt(name) { PromptChangesView(prompt: prompt) }
            }
        }
    }
}

struct TracesView: View {
    @Environment(AppStore.self) private var store
    @Environment(WindowState.self) private var window
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var nearBottom = false
    @State private var paginationTask: Task<Void, Never>?

    private var canLoadMore: Bool {
        let needsRows = nearBottom || store.traces(window.filter, name: window.traceName, in: window.range).isEmpty
        return store.isLive && needsRows && window.tab == .traces && window.tracePath.isEmpty
            && store.nextCursor != nil && !store.isLoading && store.connectionError == nil
    }

    var body: some View {
        let traces = store.traces(window.filter, name: window.traceName, in: window.range)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if traces.isEmpty && !store.isLoading {
                    ContentUnavailableView {
                        Label("No matching traces", systemImage: "list.bullet.indent")
                    } description: {
                        Text(store.isLive && store.nextCursor != nil
                             ? "Checking more traces in this window…"
                             : "Try a wider time range or clear the filters.")
                    } actions: {
                        if window.filter != .all || window.traceName != nil {
                            Button("Clear filters") { window.filter = .all; window.traceName = nil }
                        }
                        if window.range != .week { Button("Show last 7 days") { window.range = .week } }
                    }
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(traces) { trace in
                        NavigationLink(value: AppRoute.trace(trace.id)) { TraceRow(trace: trace) }
                            .buttonStyle(.plain).accessibilityIdentifier("trace-\(trace.id)")
                    }
                }
                if store.isLive {
                    paginationFooter
                        .onScrollVisibilityChange(threshold: 0.1) { nearBottom = $0 }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 28)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .accessibilityIdentifier("traceScroll")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: canLoadMore, initial: true) { _, ready in
            if ready { loadNextPage() }
        }
        .onDisappear { paginationTask?.cancel(); paginationTask = nil }
        .refreshable { if store.isLive { await store.refreshObservations() } }
    }

    private var header: some View {
        return VStack(alignment: .leading, spacing: 0) {
            ScreenTitle(title: "Traces")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { rangeMenu; Spacer(minLength: 12); loadedCount }
                VStack(alignment: .leading, spacing: 4) { rangeMenu; loadedCount }
            }.padding(.top, 16)
            if let name = window.traceName {
                Button { window.traceName = nil } label: {
                    HStack(spacing: 8) {
                        Text(name).lineLimit(2)
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    }.frame(minHeight: 44)
                }
                .buttonStyle(.plain).font(.subheadline)
                .accessibilityLabel("Showing \(name) only. Remove filter")
                .accessibilityIdentifier("clearTraceName")
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) { filterButtons }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { filterButtons }
                    VStack(alignment: .leading, spacing: 0) { filterButtons }
                }
            }
        }.padding(.bottom, 18)
    }

    private var rangeMenu: some View {
        @Bindable var window = window
        return Menu {
            Picker("Time range", selection: $window.range) {
                ForEach(TimeRange.allCases) { range in Text(range.label).tag(range) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(window.range.label)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
            }.font(.subheadline).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Time range, \(window.range.label)").accessibilityIdentifier("traceRange")
    }

    private var loadedCount: some View {
        Text("\(store.traces(.all, name: window.traceName, in: window.range).count) loaded")
            .font(.footnote).foregroundStyle(Palette.muted)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("traceLoadedCount")
            .accessibilityHint(store.isLive ? "Filters apply to loaded traces. More traces load as you scroll." : "")
    }

    private var filterButtons: some View {
        ForEach(TraceFilter.allCases, id: \.self) { filter in
            Button { window.filter = filter } label: {
                Text(filterTitle(filter))
                    .font(.subheadline.weight(window.filter == filter ? .semibold : .regular))
                    .foregroundStyle(window.filter == filter ? Palette.ink : Palette.muted)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(window.filter == filter ? [.isSelected] : [])
            .accessibilityIdentifier("filter-\(filter.rawValue)")
        }
    }

    private func filterTitle(_ filter: TraceFilter) -> String {
        if filter == .all { return filter.title }
        return "\(filter.title) \(store.traces(filter, name: window.traceName, in: window.range).count)"
    }

    private var paginationFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = store.connectionError {
                Text(error).font(.footnote).foregroundStyle(Palette.red)
                    .accessibilityIdentifier("tracePaginationError")
                Button(store.nextCursor != nil ? "Retry loading traces" : "Retry refresh") {
                    guard paginationTask == nil else { return }
                    paginationTask = Task {
                        if store.nextCursor != nil { await store.loadMoreObservations() }
                        else { await store.refreshObservations() }
                        paginationTask = nil
                    }
                }
                .buttonStyle(.plain).font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                .disabled(store.isLoading).accessibilityIdentifier("retryTracePagination")
            } else if store.isLoading || store.nextCursor != nil {
                ProgressView("Loading more traces…")
                    .font(.footnote).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity).accessibilityIdentifier("tracePaginationLoading")
            }
        }.frame(minHeight: store.nextCursor != nil || store.isLoading ? 44 : 0)
            .padding(.top, 16)
    }

    private func loadNextPage() {
        guard canLoadMore, paginationTask == nil else { return }
        paginationTask = Task {
            defer { paginationTask = nil }
            // Let lazy row measurements settle before checking the bottom again.
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard canLoadMore, !Task.isCancelled else { return }
            await store.loadMoreObservations()
        }
    }
}

struct ChipLabel: View {
    let title: String
    var symbol: String? = nil
    let selected: Bool
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)) }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 16).frame(minHeight: 44)
        .foregroundStyle(selected ? Palette.inverse : Palette.ink)
        .background(selected ? Palette.primary : Palette.fill, in: .capsule)
    }
}

struct FilterChip: View {
    let title: String
    var symbol: String? = nil
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) { ChipLabel(title: title, symbol: symbol, selected: selected) }
            .buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct TraceList: View {
    let traces: [TraceRecord]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(traces) { trace in
                if trace.id != traces.first?.id { RowDivider() }
                NavigationLink(value: AppRoute.trace(trace.id)) { TraceRow(trace: trace) }
                    .buttonStyle(.plain).accessibilityIdentifier("trace-\(trace.id)")
            }
            if traces.isEmpty {
                ContentUnavailableView("No matching traces", systemImage: "magnifyingglass", description: Text("Try another ID or search term."))
            }
        }
    }
}

struct TraceRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let trace: TraceRecord
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: trace.status == .error ? "exclamationmark.circle" : trace.status == .slow ? "clock" : "checkmark.circle")
                .font(.system(size: 20)).foregroundStyle(Palette.status(trace.status)).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(trace.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(trace.name).font(.footnote).foregroundStyle(Palette.muted)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) { timing; timestamp }
                        .font(.footnote).foregroundStyle(Palette.muted)
                } else {
                    HStack(alignment: .firstTextBaseline) { timing; Spacer(minLength: 4); timestamp }
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                if let failure = trace.failure {
                    Text(failure.failureTitle).font(.footnote.weight(.medium)).foregroundStyle(Palette.red)
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.muted.opacity(0.6)).padding(.top, 4)
        }.padding(.vertical, 14).padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
            .accessibilityElement(children: .combine)
    }
    private var timing: some View {
        Text("\(formatDuration(trace.duration)) · \(formatCost(trace.cost))").monospacedDigit()
    }
    private var timestamp: some View {
        Text(trace.timestamp, format: .relative(presentation: .numeric, unitsStyle: .narrow))
    }
}

extension TraceSpan {
    private var isModelRequest: Bool { model != nil || type == .generation || type == .embedding }
    var failureTitle: String {
        let message = statusMessage ?? ""
        if message.localizedCaseInsensitiveContains("timeout") || message.localizedCaseInsensitiveContains("timed out") { return isModelRequest ? "Provider timeout" : "Step timeout" }
        if message.contains("429") || message.localizedCaseInsensitiveContains("rate limit") { return isModelRequest ? "Provider rate limit" : "Request rate limit" }
        return "Failed in \(name)"
    }
    var failureSummary: String {
        if failureTitle == "Provider timeout" { return "The model provider did not respond in time." }
        if failureTitle == "Provider rate limit" { return "The model provider rejected the request because of its rate limit." }
        if failureTitle == "Step timeout" { return "This step did not finish in time." }
        if failureTitle == "Request rate limit" { return "The request was rejected because of a rate limit." }
        return statusMessage ?? "No error message recorded."
    }
}

struct TraceDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let trace: TraceRecord
    @State private var showDetails = false
    private var displayName: String { trace.displayName }
    var body: some View {
        Screen {
            Text(displayName).font(.title.bold()).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("traceTitle")
            if displayName != trace.name {
                Text(trace.name).font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 4)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) { status; metadata }.padding(.top, 12)
            } else { ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { status; metadata }
                VStack(alignment: .leading, spacing: 6) { status; metadata }
            }.padding(.top, 12) }
            SectionHeading(title: "Conversation")
            TraceConversation(trace: trace)
            if let rating = store.ratings[trace.id] {
                SectionHeading(title: "Scores", detail: "1")
                RatingRow(rating: rating)
            }
            if store.isLive { LiveScoresView(traceID: trace.id) }
            SectionHeading(title: "Execution", detail: "\(trace.spans.count) steps")
            TraceWaterfall(trace: trace)
            if !trace.session.isEmpty || trace.prompt != nil {
                SectionHeading(title: "Related")
                VStack(spacing: 4) {
                    if !trace.session.isEmpty {
                        NavigationLink(value: AppRoute.session(trace.session)) {
                            RelatedRow(title: "Session \(trace.session)", detail: "\(sessionCount) \(store.isLive ? "loaded traces" : "traces") · user \(trace.user)", symbol: "bubble.left.and.bubble.right")
                        }.buttonStyle(.plain).accessibilityIdentifier("relatedSession")
                    }
                    if let reference = trace.prompt {
                        if let prompt = store.data.prompt(reference.name) {
                            PromptLink(prompt: prompt, version: reference.version)
                        } else if store.isLive {
                            NavigationLink(value: AppRoute.prompt(reference.name, version: reference.version)) {
                                RelatedRow(title: "Prompt \(reference.name)", detail: "v\(reference.version)", symbol: "doc.text")
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            let footer = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            footer {
                if store.isLive {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "info.circle").font(.system(size: 17))
                        Text("Loaded window · 7 days").font(.footnote)
                    }.foregroundStyle(Palette.muted)
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Button { showDetails = true } label: {
                    HStack(spacing: 6) {
                        Text("Details")
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                        .font(.subheadline).foregroundStyle(Palette.muted).frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityIdentifier("traceDetails")
            }.padding(.top, 20)
        }
        .navigationTitle("Trace").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDetails) { TraceDetails(trace: trace, isLive: store.isLive) }
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: "Trace \(trace.id) · \(trace.name)\n\(trace.title)\n\(trace.output?.summary ?? trace.failure?.statusMessage ?? "")") {
                Label("Share trace", systemImage: "square.and.arrow.up")
            }
        } }
    }
    private var sessionCount: Int { store.data.traces.filter { $0.session == trace.session }.count }
    private var status: some View {
        Text(trace.status.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.status(trace.status))
    }
    private var metadata: some View {
        Text("\(formatDuration(trace.duration)) · \(formatCost(trace.cost)) · \(trace.timestamp.formatted(.relative(presentation: .numeric)))")
            .font(.subheadline).foregroundStyle(Palette.muted).monospacedDigit()
    }
}

private struct TraceConversation: View {
    let trace: TraceRecord
    @State private var expanded = false
    @State private var copied = false
    private var answer: String {
        switch trace.output {
        case .messages(let messages): (messages.last { $0.role == "assistant" } ?? messages.last)?.content ?? ""
        default: trace.output?.summary ?? ""
        }
    }
    private var preview: String { answer.components(separatedBy: "\n\n").first ?? answer }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let input = trace.input {
                VStack(alignment: .trailing, spacing: 8) {
                    Text("User").font(.footnote).foregroundStyle(Palette.muted)
                    Text(input.summary).font(.body).textSelection(.enabled)
                        .multilineTextAlignment(.trailing).accessibilityIdentifier("traceInput")
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }
            if trace.output != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Assistant").font(.footnote).foregroundStyle(Palette.muted)
                    if expanded, let output = trace.output {
                        switch output {
                        case .text(let text): Text(text).font(.body).textSelection(.enabled)
                        case .messages(let messages):
                            Text(messages.map { "\($0.role.capitalized)\n\($0.content)" }.joined(separator: "\n\n"))
                                .font(.body).textSelection(.enabled)
                        }
                    } else {
                        Text(preview).font(.body).lineLimit(6).textSelection(.enabled)
                            .accessibilityIdentifier("traceOutput")
                    }
                    HStack {
                        Button { expanded.toggle() } label: {
                            Label(expanded ? "Show less" : "Show full output", systemImage: expanded ? "chevron.up" : "chevron.down")
                                .font(.subheadline).frame(minHeight: 44)
                        }.accessibilityIdentifier("traceFullOutput")
                        Spacer(minLength: 8)
                        Button(copied ? "Copied" : "Copy output", systemImage: copied ? "checkmark" : "document.on.document") {
                            UIPasteboard.general.string = trace.output?.messages.map(\.content).joined(separator: "\n\n")
                            copied = true
                        }.labelStyle(.iconOnly).font(.system(size: 17)).frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("copyTraceOutput")
                    }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let failure = trace.failure { ErrorCard(span: failure, traceID: trace.id) }
            if trace.input == nil && trace.output == nil && trace.failure == nil {
                Text("No conversation recorded. Open a step to inspect its content.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
            }
        }.padding(.top, 8)
    }
}

private struct TraceDetails: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let trace: TraceRecord
    let isLive: Bool
    @State private var copied = false
    var body: some View {
        NavigationStack {
            Screen {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Trace ID").font(.subheadline).foregroundStyle(Palette.muted)
                            Spacer()
                            Button(copied ? "Copied" : "Copy trace ID", systemImage: copied ? "checkmark" : "document.on.document") {
                                UIPasteboard.general.string = trace.id
                                copied = true
                            }.labelStyle(.iconOnly).font(.system(size: 17)).buttonStyle(.plain).frame(minWidth: 44, minHeight: 44)
                                .accessibilityIdentifier("copyTraceID")
                        }
                        Text(trace.id).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled)
                            .accessibilityIdentifier("traceID")
                    }
                    detail("Name", value: trace.name)
                    detail("Recorded", value: trace.timestamp.formatted(date: .abbreviated, time: .standard))
                    if !trace.user.isEmpty { detail("User", value: trace.user) }
                    if isLive {
                        detail("Time window", value: "Steps within the loaded 7-day period. Older steps may be outside this window.")
                    }
                }
            }.navigationTitle("Trace details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }.presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }
    private func detail(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(Palette.muted)
            Text(value).font(.body).textSelection(.enabled)
        }
    }
}

private struct RatingRow: View {
    let rating: ReviewRating
    private var detail: String {
        (rating.reasons + [rating.comment]).filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rating.score == .good ? "hand.thumbsup" : "hand.thumbsdown")
                .font(.system(size: 19)).foregroundStyle(rating.score == .good ? Palette.green : Palette.orange).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(rating.score == .good ? "Good" : "Needs work").font(.body.weight(.semibold))
                    .foregroundStyle(rating.score == .good ? Palette.green : Palette.orange)
                if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(Palette.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 8).accessibilityElement(children: .combine).accessibilityIdentifier("traceRating")
    }
}

struct PromptLink: View {
    let prompt: PromptRecord
    let version: Int
    var body: some View {
        NavigationLink(value: AppRoute.prompt(prompt.name, version: version)) {
            RelatedRow(title: "Prompt \(prompt.name)", detail: prompt.title(for: version), symbol: "doc.text")
        }.buttonStyle(.plain).accessibilityIdentifier("relatedPrompt")
    }
}

struct RelatedRow: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Palette.muted).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Chevron()
        }.padding(16).contentShape(.rect)
    }
}

struct ErrorCard: View {
    let span: TraceSpan
    var traceID: String? = nil
    @State private var copied = false
    @State private var expanded = false
    private var message: String { span.statusMessage ?? "No error message recorded." }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label(traceID == nil ? "Failed in \(span.name)" : span.failureTitle, systemImage: "exclamationmark.octagon")
                    .font(.headline).foregroundStyle(Palette.red)
                if let traceID {
                    Text(span.failureSummary).font(.subheadline)
                    NavigationLink(value: AppRoute.span(trace: traceID, id: span.id)) {
                        Label("Open \(span.name)", systemImage: "chevron.right").font(.subheadline.weight(.medium))
                    }.accessibilityIdentifier("openFailedStep")
                } else { technicalDetails }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(traceID == nil ? Palette.redFill : .clear, in: .rect(cornerRadius: 18))
            if traceID != nil {
                DisclosureGroup("Technical details", isExpanded: $expanded) { technicalDetails }
                    .font(.subheadline).padding(.horizontal, 4)
            }
        }
    }
    private var technicalDetails: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(message).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
            Button(copied ? "Copied" : "Copy error", systemImage: copied ? "checkmark" : "document.on.document") {
                UIPasteboard.general.string = message
                copied = true
            }.labelStyle(.iconOnly).foregroundStyle(Palette.muted).frame(minWidth: 44, minHeight: 44)
        }
    }
}

/// Type colours follow Langfuse; a failure turns the tile red instead.
private struct SpanTile: View {
    let span: TraceSpan
    var body: some View {
        let color = span.failed ? Palette.red : Palette.glyph(span.type)
        Image(systemName: span.symbol).font(.subheadline).frame(width: 28, height: 28)
            .foregroundStyle(color)
            .background(span.failed ? Palette.redFill : color.opacity(0.14), in: .rect(cornerRadius: 8))
    }
}

private struct TraceWaterfall: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let trace: TraceRecord
    private var duration: Double { max(trace.duration, trace.spans.map(\.end).max() ?? 0, 0.001) }
    var body: some View {
        VStack(spacing: 16) {
            if !dynamicTypeSize.isAccessibilitySize { HStack {
                Text("0 ms")
                Spacer()
                Text(formatDuration(duration / 2))
                Spacer()
                Text(formatDuration(duration))
            }.font(.caption).monospacedDigit().foregroundStyle(Palette.muted).accessibilityHidden(true) }
            ForEach(trace.spans) { span in
                NavigationLink(value: AppRoute.span(trace: trace.id, id: span.id)) {
                    WaterfallRow(span: span, duration: duration)
                }.buttonStyle(.plain).accessibilityIdentifier("span-\(span.id)")
            }
            if trace.spans.isEmpty {
                Text("No steps recorded").font(.subheadline).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.top, 4)
    }
}

private struct WaterfallRow: View {
    let span: TraceSpan
    let duration: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if span.depth > 0 {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .frame(width: CGFloat(min(span.depth, 3)) * 10)
                }
                Image(systemName: span.symbol).font(.system(size: 19))
                    .foregroundStyle(span.failed ? Palette.red : Palette.glyph(span.type)).frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(span.name).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(span.failed ? Palette.red : Palette.ink)
                    Label(formatDuration(span.duration), systemImage: span.failed ? "exclamationmark.circle" : "clock")
                        .font(.caption).monospacedDigit().foregroundStyle(span.failed ? Palette.red : Palette.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geometry in
                let start = min(max(span.start / duration, 0), 1)
                let length = min(max(span.duration / duration, 0), 1 - start)
                Capsule().fill(span.failed ? Palette.red : Palette.bar(span.type).opacity(span.depth == 0 ? 0.4 : 1))
                        .frame(width: max(geometry.size.width * length, 3), height: 8)
                        .offset(x: min(geometry.size.width * start, max(geometry.size.width - 3, 0)))
            }.frame(height: 8).accessibilityHidden(true)
        }.padding(.vertical, 4)
            .contentShape(.rect).accessibilityElement(children: .combine)
            .accessibilityValue("Starts at \(formatDuration(span.start)), duration \(formatDuration(span.duration))")
    }
}

struct SpanDetailView: View {
    @Environment(AppStore.self) private var store
    let trace: TraceRecord
    let span: TraceSpan
    var body: some View {
        Screen {
            Text(span.name).font(.title.bold())
            HStack(spacing: 8) {
                SpanTile(span: span)
                Text("\(span.type.rawValue.capitalized) · trace \(trace.id)").font(.subheadline).foregroundStyle(Palette.muted)
            }.padding(.top, 5)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                SpanStat(title: "Duration", value: formatDuration(span.duration))
                SpanStat(title: "Starts at", value: "+\(formatDuration(span.start))")
                if let model = span.model { SpanStat(title: "Model", value: model) }
                if let usage = span.usage { SpanStat(title: "Tokens", value: tokens(usage)) }
                if let cost = span.cost { SpanStat(title: "Cost", value: formatCost(cost)) }
            }.padding(.top, 20)
            if let reference = span.prompt, let prompt = store.data.prompt(reference.name) {
                SurfaceGroup { PromptLink(prompt: prompt, version: reference.version) }.padding(.top, 14)
            } else if store.isLive, let reference = span.prompt {
                SurfaceGroup {
                    NavigationLink(value: AppRoute.prompt(reference.name, version: reference.version)) {
                        RelatedRow(title: "Prompt \(reference.name)", detail: "v\(reference.version)", symbol: "doc.text")
                    }.buttonStyle(.plain)
                }.padding(.top, 14)
            }
            SectionHeading(title: "Input")
            ContentBlocks(content: span.input)
            SectionHeading(title: "Output")
            if span.failed { ErrorCard(span: span) } else { ContentBlocks(content: span.output) }
        }.navigationTitle("Step").navigationBarTitleDisplayMode(.inline)
    }
    private func tokens(_ usage: TraceSpan.Usage) -> String {
        let input = "\(usage.input.formatted()) in"
        return usage.output.map { "\(input) · \($0.formatted()) out" } ?? input
    }
}

private struct SpanStat: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(Palette.muted)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .card(.rect(cornerRadius: 18))
    }
}

struct SessionView: View {
    @Environment(AppStore.self) private var store
    let sessionID: String
    private var traces: [TraceRecord] { store.data.traces.filter { $0.session == sessionID } }
    var body: some View {
        Screen {
            ScreenTitle(title: sessionID, subtitle: "\(traces.count) \(store.isLive ? "loaded traces" : "traces") · user \(traces.first?.user ?? "—")")
            SectionHeading(title: "Traces")
            TraceList(traces: traces)
        }.navigationTitle("Session").navigationBarTitleDisplayMode(.inline)
    }
}

struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(WindowState.self) private var window
    var body: some View {
        @Bindable var window = window
        let results = store.search(window.query)
        Screen {
            if store.isLive { LiveLoadingStatus() }
            if window.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("Search traces", systemImage: "magnifyingglass",
                                       description: Text("Find a trace by its ID, session, user, or words from its input, output or error."))
                    .padding(.top, 40)
            } else {
                SectionHeading(title: "Traces", detail: "\(results.count)")
                TraceList(traces: results)
                if results.isEmpty { Button("Clear search") { window.query = "" }.padding(.top, 12) }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $window.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Trace ID, session, user or text")
        .autocorrectionDisabled().textInputAutocapitalization(.never)
    }
}
