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
    @State private var chipPosition = ScrollPosition(idType: TraceFilter.self)
    var body: some View {
        @Bindable var window = window
        let traces = store.traces(window.filter, name: window.traceName, in: window.range)
        Screen {
            ScreenTitle(title: "Traces")
            if store.isLive { LiveLoadingStatus() }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Menu {
                        Picker("Time range", selection: $window.range) {
                            ForEach(TimeRange.allCases) { range in Text(range.label).tag(range) }
                        }
                    } label: {
                        ChipLabel(title: window.range.title, symbol: "chevron.down", selected: false)
                    }.accessibilityLabel("Time range, \(window.range.label)").accessibilityIdentifier("traceRange")
                    if let name = window.traceName {
                        FilterChip(title: name, symbol: "xmark", selected: true) { window.traceName = nil }
                            .accessibilityLabel("Showing \(name) only. Remove filter")
                            .accessibilityIdentifier("clearTraceName")
                    }
                    ForEach(TraceFilter.allCases, id: \.self) { filter in
                        FilterChip(title: chipTitle(filter), selected: window.filter == filter) { window.filter = filter }
                            .id(filter).accessibilityIdentifier("filter-\(filter.rawValue)")
                    }
                }.padding(.vertical, 4)
            }
            .scrollIndicators(.hidden).scrollPosition($chipPosition).padding(.top, 14)
            // Overview can select a chip that the name chip pushes offscreen.
            .onAppear { chipPosition.scrollTo(id: window.filter) }
            .onChange(of: window.filter) { withAnimation { chipPosition.scrollTo(id: window.filter) } }
            SectionHeading(title: window.range.label, detail: "\(traces.count)")
            if traces.isEmpty {
                ContentUnavailableView {
                    Label("No matching traces", systemImage: "list.bullet.indent")
                } description: {
                    Text("Try a wider time range or clear the filters.")
                } actions: {
                    if window.filter != .all || window.traceName != nil {
                        Button("Clear filters") { window.filter = .all; window.traceName = nil }
                    }
                    if window.range != .week { Button("Show last 7 days") { window.range = .week } }
                    if store.isLive && store.nextCursor != nil {
                        Button("Load more traces") { Task { await store.loadMoreObservations() } }.disabled(store.isLoading)
                    }
                }
            } else { TraceList(traces: traces) }
        }.navigationBarTitleDisplayMode(.inline)
            .refreshable { if store.isLive { await store.refreshObservations() } }
    }
    private func chipTitle(_ filter: TraceFilter) -> String {
        if filter == .all { return filter.title }
        return "\(filter.title) \(store.traces(filter, name: window.traceName, in: window.range).count)"
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
    let trace: TraceRecord
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: trace.status == .error ? "exclamationmark.circle" : trace.status == .slow ? "clock" : "checkmark.circle")
                .font(.title3).foregroundStyle(Palette.status(trace.status)).frame(width: 24).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(trace.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(trace.name).font(.footnote).foregroundStyle(Palette.muted)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(formatDuration(trace.duration)) · \(formatCost(trace.cost))").monospacedDigit()
                    Spacer(minLength: 4)
                    Text(trace.timestamp, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                }.font(.footnote).foregroundStyle(Palette.muted)
                if let failure = trace.failure {
                    Text(failure.failureTitle).font(.footnote.weight(.medium)).foregroundStyle(Palette.red)
                }
            }
            Chevron().padding(.top, 4)
        }.padding(.vertical, 14).padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
            .accessibilityElement(children: .combine)
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
    let trace: TraceRecord
    var body: some View {
        Screen {
            Text(trace.name).font(.title.bold()).accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack { StatusPill(status: trace.status); metadata }
                VStack(alignment: .leading, spacing: 6) { StatusPill(status: trace.status); metadata }
            }.padding(.top, 6)
            if let input = trace.input { QuestionBubble(text: input.summary) }
            if let failure = trace.failure { ErrorCard(span: failure, traceID: trace.id).padding(.top, 16) }
            else if let output = trace.output { AgentAnswer(text: output.summary) }
            if let rating = store.ratings[trace.id] {
                SectionHeading(title: "Review")
                SurfaceGroup { RatingRow(rating: rating) }
            }
            if store.isLive { LiveScoresView(traceID: trace.id) }
            SectionHeading(title: "Timeline", detail: "\(trace.spans.count) steps")
            TraceWaterfall(trace: trace)
            if !trace.session.isEmpty || trace.prompt != nil {
                SectionHeading(title: "Related")
                SurfaceGroup {
                    if !trace.session.isEmpty {
                        NavigationLink(value: AppRoute.session(trace.session)) {
                            RelatedRow(title: "Session \(trace.session)", detail: "\(sessionCount) \(store.isLive ? "loaded traces" : "traces") · user \(trace.user)", symbol: "bubble.left.and.bubble.right")
                        }.buttonStyle(.plain).accessibilityIdentifier("relatedSession")
                    }
                    if let reference = trace.prompt {
                        if let prompt = store.data.prompt(reference.name) {
                            if !trace.session.isEmpty { RowDivider() }
                            PromptLink(prompt: prompt, version: reference.version)
                        } else if store.isLive {
                            if !trace.session.isEmpty { RowDivider() }
                            NavigationLink(value: AppRoute.prompt(reference.name, version: reference.version)) {
                                RelatedRow(title: "Prompt \(reference.name)", detail: "v\(reference.version)", symbol: "doc.text")
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Trace \(trace.id)").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: "Trace \(trace.id) · \(trace.name)\n\(trace.title)\n\(trace.output?.summary ?? trace.failure?.statusMessage ?? "")") {
                Label("Share trace", systemImage: "square.and.arrow.up")
            }
        } }
    }
    private var sessionCount: Int { store.data.traces.filter { $0.session == trace.session }.count }
    private var metadata: some View {
        HStack(spacing: 0) {
            Text("\(formatDuration(trace.duration)) · \(formatCost(trace.cost)) · ")
            Text(trace.timestamp, format: .relative(presentation: .numeric))
        }.font(.subheadline).foregroundStyle(Palette.muted).monospacedDigit()
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
                .foregroundStyle(rating.score == .good ? Palette.ink : Palette.orange).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(rating.score == .good ? "Good" : "Needs work").font(.body.weight(.semibold))
                if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(Palette.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).accessibilityElement(children: .combine).accessibilityIdentifier("traceRating")
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
                .background(Palette.redFill, in: .rect(cornerRadius: 18))
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
        VStack(spacing: 0) {
            HStack {
                if !dynamicTypeSize.isAccessibilitySize { Color.clear.frame(width: 188) }
                HStack {
                    Text("0s")
                    Spacer()
                    Text(formatDuration(duration / 2))
                    Spacer()
                    Text(formatDuration(duration))
                }.font(.caption).monospacedDigit().foregroundStyle(Palette.muted)
            }.padding(.horizontal, 12).padding(.vertical, 10)
            ForEach(trace.spans) { span in
                NavigationLink(value: AppRoute.span(trace: trace.id, id: span.id)) {
                    WaterfallRow(span: span, duration: duration, stacked: dynamicTypeSize.isAccessibilitySize)
                }.buttonStyle(.plain).accessibilityIdentifier("span-\(span.id)")
            }
        }.padding(.bottom, 8).card(.rect(cornerRadius: 18))
    }
}

private struct WaterfallRow: View {
    let span: TraceSpan
    let duration: Double
    let stacked: Bool
    var body: some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            HStack(spacing: 6) {
                if span.depth > 0 {
                    Image(systemName: "arrow.turn.down.right").font(.caption2).foregroundStyle(Palette.muted)
                        .frame(width: CGFloat(min(span.depth, 3)) * 8)
                }
                SpanTile(span: span)
                VStack(alignment: .leading, spacing: 4) {
                    Text(span.name).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(span.failed ? Palette.red : Palette.ink)
                    Label(formatDuration(span.duration), systemImage: span.failed ? "exclamationmark.circle" : "clock")
                        .font(.caption).monospacedDigit().foregroundStyle(span.failed ? Palette.red : Palette.muted)
                }
            }.frame(width: stacked ? nil : 188, alignment: .leading)
            GeometryReader { geometry in
                let start = min(max(span.start / duration, 0), 1)
                let length = min(max(span.duration / duration, 0), 1 - start)
                ZStack(alignment: .leading) {
                    HStack { grid; Spacer(); grid; Spacer(); grid }
                    Capsule().fill(Palette.bar(span.type).opacity(span.depth == 0 ? 0.4 : 1))
                        .frame(width: max(geometry.size.width * length, 3), height: 7)
                        .offset(x: min(geometry.size.width * start, max(geometry.size.width - 3, 0)))
                }
            }.frame(height: stacked ? 24 : 60).accessibilityHidden(true)
        }.padding(.horizontal, 12).padding(.vertical, 4)
            .background(span.failed ? Palette.redFill.opacity(0.65) : .clear)
            .contentShape(.rect).accessibilityElement(children: .combine)
            .accessibilityValue("Starts at \(formatDuration(span.start)), duration \(formatDuration(span.duration))")
    }
    private var grid: some View { Rectangle().fill(Palette.line).frame(width: 0.5) }
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
