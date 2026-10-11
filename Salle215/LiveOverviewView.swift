import SwiftUI
import Charts

struct LiveOverviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(WindowState.self) private var window
    @State private var selectedMetric: MetricKind?
    @State private var selectedScoreID: String?
    private var metrics: LiveMetricsStore { store.metricsStore }
    private var state: LiveOverviewState { metrics.state(window.range) }
    private var data: LiveOverviewData? { state.data }
    private var score: LiveScoreAggregate? {
        let scores = data?.scoreAggregates ?? []
        return scores.first { $0.id == selectedScoreID } ?? scores.first { $0.name == "salle215.review" } ?? scores.first
    }

    var body: some View {
        @Bindable var window = window
        Screen {
            ScreenTitle(title: "Overview", subtitle: data.map { "Updated \($0.to.formatted(date: .omitted, time: .shortened))" })
            Picker("Time range", selection: $window.range) {
                ForEach(TimeRange.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).padding(.top, 18).accessibilityIdentifier("timeRange")
            MetricsLimitNotice(metrics: metrics, range: window.range)
            if state.isLoading {
                ProgressView(data == nil ? "Loading Overview…" : "Refreshing Overview…").padding(.top, 20)
                    .accessibilityIdentifier("overviewLoading")
            }
            if let data {
                if let count = data.observationCount, count == 0 {
                    ContentUnavailableView {
                        Label("No activity in this period", systemImage: "waveform.path.ecg")
                    } description: {
                        Text("Try a wider time range or change the environment in the project menu.")
                    } actions: {
                        if window.range != .week { Button("Show last 7 days") { window.range = .week } }
                    }.accessibilityIdentifier("overviewEmpty")
                } else if let count = data.observationCount, state.refreshFailures.isEmpty {
                    Text("\(Int(count).formatted()) steps · \(data.rootCount.map { "\(Int($0).formatted()) entry points" } ?? "entry points unavailable")")
                        .font(.footnote).foregroundStyle(Palette.muted).padding(.top, 14)
                    SectionHeading(title: "Needs attention")
                    SurfaceGroup {
                        if let errors = data.errorCount, errors > 0 {
                            Button { window.showTraces(.error) } label: {
                                RelatedRow(title: "\(Int(errors).formatted()) failed steps", detail: "Open errors among loaded traces", symbol: "exclamationmark.circle")
                            }.buttonStyle(.plain)
                        }
                        if let latency = data.latency, latency >= TraceRecord.slowSeconds {
                            if (data.errorCount ?? 0) > 0 { RowDivider() }
                            Button { window.showTraces(.slow) } label: {
                                RelatedRow(title: "P95 entry-point latency · \(formatDuration(latency))", detail: "Open slow traces among loaded steps", symbol: "clock")
                            }.buttonStyle(.plain)
                        }
                        if data.errorCount == 0 && data.failures["roots"] == nil && (data.latency ?? 0) < TraceRecord.slowSeconds {
                            Label("No failed steps recorded", systemImage: "checkmark.circle")
                                .font(.subheadline).foregroundStyle(Palette.muted).padding(16)
                        }
                    }
                }
            }
            SectionHeading(title: state.refreshFailures.isEmpty ? "Vitals" : "Last available vitals")
            SurfaceGroup {
                ForEach(MetricKind.allCases) { kind in
                    if kind != .errors { RowDivider() }
                    Button { selectedMetric = kind } label: {
                        LiveMetricRow(kind: kind, data: data, score: score, isLoading: state.isLoading)
                    }.buttonStyle(.plain).accessibilityIdentifier("metric-\(kind.rawValue)")
                }
            }
            if let scores = data?.scoreAggregates, scores.count > 1 {
                Menu {
                    ForEach(scores) { score in
                        Button("\(score.name) · \(score.dataType.lowercased())") { selectedScoreID = score.id }
                    }
                } label: { Label("Quality score: \(score?.name ?? "Choose")", systemImage: "slider.horizontal.3") }
                    .font(.subheadline).padding(.top, 16).accessibilityIdentifier("qualityScorePicker")
            }
            if metrics.retryAfter == nil, let failures = state.refreshFailures.isEmpty ? data?.failures : state.refreshFailures, !failures.isEmpty {
                ForEach(failures.keys.sorted(), id: \.self) { key in
                    Text("\(LiveMetricPresentation.section(key)): \(failures[key] ?? "")")
                        .font(.footnote).foregroundStyle(Palette.red).padding(.top, 8)
                }
            }
            Button { window.showTraces(.all) } label: {
                RelatedRow(title: "Browse loaded traces", detail: "\(store.data.traces.count) traces available", symbol: "list.bullet.indent")
            }.buttonStyle(.plain).padding(.top, 12)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh Overview", systemImage: "arrow.clockwise") {
                    Task { await metrics.load(window.range, refresh: true) }
                }
                .labelStyle(.iconOnly)
                .disabled(state.isLoading)
                .accessibilityIdentifier("refreshOverview")
            }
        }
        .task(id: window.range) { await metrics.load(window.range) }
        .refreshable { await metrics.load(window.range, refresh: true) }
        .sheet(item: $selectedMetric) { kind in
            LiveMetricDetailView(kind: kind, range: window.range, score: score)
        }
    }
}

struct MetricsLimitNotice: View {
    let metrics: LiveMetricsStore
    var range: TimeRange = .day
    var body: some View {
        if metrics.retryAfter != nil {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let state = metrics.state(range)
                let date = metrics.nextRefreshDate(range) ?? timeline.date
                let seconds = max(0, Int(ceil(date.timeIntervalSince(timeline.date))))
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Refresh paused", systemImage: "clock").font(.headline).foregroundStyle(Palette.orange)
                        Spacer(minLength: 8)
                        Button(seconds > 0 ? "Retry in \(seconds)s" : "Retry refresh") {
                            Task { await metrics.load(range, refresh: true) }
                        }.font(.footnote).buttonStyle(.bordered).disabled(seconds > 0 || state.isLoading)
                    }
                    Text("Langfuse’s request limit was reached.").font(.subheadline)
                    if let data = state.data, data.failures.isEmpty {
                        Text("Showing data from \(data.to.formatted(date: .omitted, time: .shortened)).").font(.footnote).foregroundStyle(Palette.muted)
                    } else { Text("No completed report is available yet.").font(.footnote).foregroundStyle(Palette.muted) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.orangeFill, in: .rect(cornerRadius: 18)).padding(.top, 16)
                    .accessibilityIdentifier("metricsRateLimit")
            }
        }
    }
}

enum LiveMetricPresentation {
    static func title(_ kind: MetricKind) -> String {
        switch kind { case .errors: "Step error rate"; case .latency: "P95 entry-point latency"; case .spend: "Recorded spend"; case .quality: "Quality score" }
    }
    static func section(_ key: String) -> String {
        switch key { case "activity": "Activity and spend"; case "roots": "Latency"; case "trend": "Latency trend"; default: "Scores" }
    }
    static func value(_ kind: MetricKind, data: LiveOverviewData?, score: LiveScoreAggregate?) -> String {
        switch kind {
        case .errors: data?.errorRate.map { String(format: "%.1f%%", $0) } ?? "—"
        case .latency: data?.latency.map(formatDuration) ?? "—"
        case .spend: data?.cost.map { $0.formatted(.currency(code: "USD").precision(.fractionLength(2...4))) } ?? "—"
        case .quality: score?.formatted ?? "—"
        }
    }
    static func caption(_ kind: MetricKind, data: LiveOverviewData?, score: LiveScoreAggregate?) -> String {
        guard let data else { return "Waiting for backend data" }
        switch kind {
        case .errors:
            if data.failures["activity"] != nil { return "Unavailable" }
            return data.errorRate == nil ? "No observed steps" : "\(Int(data.errorCount ?? 0).formatted()) failed of \(Int(data.observationCount ?? 0).formatted()) steps"
        case .latency:
            if data.failures["roots"] != nil { return "Unavailable" }
            return data.latency == nil ? "No completed entry-point timing" : "95% of entry points finish within this time"
        case .spend:
            if data.failures["activity"] != nil { return "Unavailable" }
            return data.cost == nil ? "No cost data recorded" : "Across all observed steps · USD"
        case .quality:
            if data.failures["scores"] != nil { return "Unavailable" }
            return score.map { "\($0.name) · \(Int($0.count).formatted()) \($0.dataType.lowercased()) scores" } ?? "No numeric or Boolean scores"
        }
    }
    static func formatted(_ value: Double, kind: MetricKind, score: LiveScoreAggregate?) -> String {
        switch kind {
        case .errors: String(format: "%.1f%%", value)
        case .latency: formatDuration(value)
        case .spend: value.formatted(.currency(code: "USD").precision(.fractionLength(2...4)))
        case .quality: score?.dataType == "BOOLEAN" ? String(format: "%.1f%%", value * 100) : value.formatted(.number.precision(.fractionLength(0...3)))
        }
    }
}

private struct LiveMetricRow: View {
    let kind: MetricKind
    let data: LiveOverviewData?
    let score: LiveScoreAggregate?
    let isLoading: Bool
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(LiveMetricPresentation.title(kind)).font(.subheadline.weight(.medium)).foregroundStyle(Palette.muted)
                Text(LiveMetricPresentation.value(kind, data: data, score: score)).font(.title.bold()).monospacedDigit()
                Text(LiveMetricPresentation.caption(kind, data: data, score: score)).font(.footnote).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if kind != .quality, let data, !data.series(kind).isEmpty {
                LiveMetricChart(points: data.series(kind), kind: kind, compact: true)
                    .frame(width: 100, height: 52).accessibilityHidden(true).allowsHitTesting(false)
            } else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted) }
        }.padding(16).contentShape(.rect)
    }
}

extension [LiveMetricPoint] {
    func nearest(to date: Date?) -> LiveMetricPoint? {
        date.flatMap { date in self.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
    }
}

struct LiveMetricChart: View {
    let points: [LiveMetricPoint]
    var kind: MetricKind = .latency
    var score: LiveScoreAggregate? = nil
    var range: TimeRange = .day
    var compact = false
    var selection: Binding<Date?> = .constant(nil)
    var body: some View {
        let selected = points.nearest(to: selection.wrappedValue)
        Chart(points) { point in
            LineMark(x: .value("Time", point.date), y: .value("Value", point.value)).foregroundStyle(Palette.chart)
            PointMark(x: .value("Time", point.date), y: .value("Value", point.value)).foregroundStyle(Palette.chart).symbolSize(compact ? 4 : 12)
            if let selected, selected.id == point.id {
                RuleMark(x: .value("Selected", point.date)).foregroundStyle(Palette.muted)
                PointMark(x: .value("Time", point.date), y: .value("Value", point.value)).symbolSize(55)
            }
        }
        .chartXAxis {
            if !compact {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(Palette.line)
                    if range == .week { AxisValueLabel(format: .dateTime.month(.abbreviated).day()) }
                    else { AxisValueLabel(format: .dateTime.hour().minute()) }
                }
            }
        }
        .chartYAxis {
            if !compact {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { axis in
                    AxisGridLine().foregroundStyle(Palette.line)
                    AxisValueLabel {
                        if let value = axis.as(Double.self) {
                            Text(LiveMetricPresentation.formatted(value, kind: kind, score: score)).font(.caption)
                        }
                    }
                }
            }
        }
        .chartXSelection(value: selection)
        .accessibilityIdentifier("metricTrend")
    }
}

struct LiveMetricDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let kind: MetricKind
    let range: TimeRange
    let score: LiveScoreAggregate?
    private var metrics: LiveMetricsStore { store.metricsStore }
    private var data: LiveOverviewData? { metrics.state(range).data }
    private var key: String { metrics.detailKey(kind, range: range, score: score) }
    private var detail: LiveBreakdownState { metrics.breakdowns[key] ?? .init() }
    private var series: [LiveMetricPoint] {
        if kind != .quality { return data?.series(kind) ?? [] }
        return (detail.rows ?? []).compactMap { row in
            guard let date = LiveOverviewData.date(row["time_dimension"]?.string), let value = row["avg_value"]?.number else { return nil }
            return LiveMetricPoint(date: date, value: value)
        }.sorted { $0.date < $1.date }
    }
    @State private var selectedDate: Date?
    var body: some View {
        let selected = series.nearest(to: selectedDate)
        NavigationStack {
            Screen {
                // While scrubbing the chart, the headline shows the selected bucket instead of the period total.
                Text(selected.map { LiveMetricPresentation.formatted($0.value, kind: kind, score: score) } ?? LiveMetricPresentation.value(kind, data: data, score: score))
                    .font(.largeTitle.bold()).monospacedDigit().padding(.top, 12)
                    .accessibilityIdentifier("metricValue")
                Group {
                    if let selected { Label(selected.date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock") }
                    else { Text(LiveMetricPresentation.caption(kind, data: data, score: score)) }
                }.font(.footnote).foregroundStyle(Palette.muted).padding(.top, 6)
                MetricsLimitNotice(metrics: metrics, range: range)
                if !series.isEmpty {
                    LiveMetricChart(points: series, kind: kind, score: score, range: range, selection: $selectedDate).frame(height: 250).padding(.top, 20)
                } else { Text("No trend data available").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 24) }
                Text(explanation).font(.footnote).foregroundStyle(Palette.muted).padding(.top, 16)
                SectionHeading(title: breakdownTitle)
                if detail.isLoading { ProgressView("Loading breakdown…") }
                if let error = detail.error {
                    Text(error).font(.footnote).foregroundStyle(Palette.red)
                    Button("Retry breakdown") { Task { await metrics.loadBreakdown(kind, range: range, score: score) } }
                }
                if kind == .quality {
                    SurfaceGroup {
                        ForEach(data?.scoreAggregates ?? []) { score in
                            if score.id != data?.scoreAggregates.first?.id { RowDivider() }
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(score.name).font(.subheadline)
                                    Text("\(Int(score.count).formatted()) \(score.dataType.lowercased()) scores").font(.caption).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Text(score.formatted).font(.subheadline.weight(.semibold)).monospacedDigit()
                            }.padding(16)
                        }
                        if data?.scoreAggregates.isEmpty != false { Text("No numeric or Boolean scores in this period").foregroundStyle(Palette.muted).padding(16) }
                    }
                } else if let rows = detail.rows {
                    SurfaceGroup {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if index > 0 { RowDivider() }
                            HStack {
                                Text(row[dimension]?.string ?? "Not recorded").font(.subheadline)
                                Spacer()
                                Text(row[measure]?.number.map { value in
                                    LiveMetricPresentation.formatted(kind == .latency ? value / 1000 : value, kind: kind == .errors ? .quality : kind, score: nil)
                                } ?? "—").font(.subheadline.weight(.semibold)).monospacedDigit()
                            }.padding(16)
                        }
                        if rows.isEmpty { Text("No breakdown data in this period").foregroundStyle(Palette.muted).padding(16) }
                    }
                }
            }
            .navigationTitle(LiveMetricPresentation.title(kind)).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close", systemImage: "xmark") { dismiss() } } }
            .task(id: key) { await metrics.loadBreakdown(kind, range: range, score: score) }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    private var dimension: String { switch kind { case .errors: "name"; case .latency: "traceName"; default: "providedModelName" } }
    private var measure: String { switch kind { case .errors: "count_count"; case .latency: "p95_latency"; default: "sum_totalCost" } }
    private var breakdownTitle: String { switch kind { case .errors: "Failed steps by name"; case .latency: "P95 entry points by trace name"; case .spend: "Recorded cost by model"; case .quality: "Averages by score" } }
    private var explanation: String {
        switch kind {
        case .errors: "ERROR-level steps divided by all steps. A trace can contain several steps."
        case .latency: "P95 is calculated by Langfuse over logical root observations. Each trend bucket has its own percentile; the headline is the percentile for the whole period."
        case .spend: "Sum of recorded observation costs in USD. Unpriced steps may have no cost recorded."
        case .quality: "Each score name and type is kept separate. Boolean scores show the true rate; numeric scores keep their original scale. The chart shows the selected score's average per time bucket."
        }
    }
}
