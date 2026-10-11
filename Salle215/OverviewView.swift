import SwiftUI
import Charts

struct OverviewView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if store.isLive { LiveOverviewView() } else { SampleOverviewView() }
    }
}

struct SampleOverviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(WindowState.self) private var window
    @State private var selectedMetric: MetricKind?

    var body: some View {
        @Bindable var window = window
        let snapshot = store.data.snapshots[window.range]
        let attention = store.attention(in: window.range).filter { item in
            item.filter != .slow || store.traces(.slow, name: item.name, in: window.range).contains { $0.failure == nil }
        }
        Screen {
            ScreenTitle(title: "Overview", subtitle: "Illustrative sample data")
            Picker("Time range", selection: $window.range) {
                ForEach(TimeRange.allCases) { range in Text(range.title).tag(range) }
            }
            .pickerStyle(.segmented).padding(.top, 18)
            .accessibilityIdentifier("timeRange")

            SectionHeading(title: "Needs attention", detail: attention.isEmpty ? nil : "\(attention.count) issues")
            VStack(spacing: 8) {
                ForEach(attention) { item in
                    IncidentRow(item: item) { window.showTraces(item.filter, name: item.name) }
                        .accessibilityIdentifier("attention-\(item.id)")
                }
                if attention.isEmpty {
                    Label("No failed or slow traces", systemImage: "checkmark.circle")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            }
            SectionHeading(title: "Vitals")
            SurfaceGroup {
                ForEach(MetricKind.allCases) { kind in
                    if kind != .errors { RowDivider() }
                    Button { selectedMetric = kind } label: {
                        MetricRow(kind: kind, definition: store.data.metrics[kind],
                                  value: snapshot.value(for: kind), range: window.range)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("metric-\(kind.rawValue)")
                }
            }
            if store.pendingReviews > 0 {
                Button("Review \(store.pendingReviews) answers", systemImage: "chevron.right") { window.tab = .review }
                    .font(.subheadline.weight(.medium)).padding(.top, 14)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedMetric) { kind in
            MetricDetailView(kind: kind)
        }
    }
}

struct ScreenTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Palette.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IncidentRow: View {
    let item: AttentionItem
    let action: () -> Void
    private var color: Color { item.filter == .error ? Palette.red : Palette.orange }
    private var detail: String {
        item.filter == .error ? "\(item.name) · Failed traces" : "\(item.name) · Up to \(formatDuration(item.slowest))"
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.filter == .error ? "exclamationmark.circle.fill" : "clock")
                    .foregroundStyle(color).frame(width: 28, height: 28)
                    .background(color.opacity(0.1), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(item.count) \(item.filter == .error ? "failed" : "slow") \(item.count == 1 ? "trace" : "traces")").font(.subheadline.weight(.semibold))
                    Text(detail).font(.footnote).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 4)
                Text(String(item.count)).font(.headline).monospacedDigit().foregroundStyle(color)
                Chevron()
            }.padding(12).contentShape(.rect)
                .background(item.filter == .error ? Palette.redFill : Palette.orangeFill, in: .rect(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
}

private struct MetricRow: View {
    let kind: MetricKind
    let definition: MetricDefinition
    let value: MetricValue
    let range: TimeRange
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(definition.title).font(.subheadline.weight(.medium)).foregroundStyle(Palette.muted)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(kind == .spend ? "$\(value.value)" : value.value).font(.title2.bold()).monospacedDigit()
                    if kind != .spend { Text(definition.unit).font(.headline).foregroundStyle(Palette.muted) }
                }
                MetricStatus(value: value)
            }.frame(maxWidth: .infinity, alignment: .leading)
            TrendChart(definition: definition, range: range, warning: value.status == .warn, compact: true)
                .frame(width: 104, height: 52).accessibilityHidden(true).allowsHitTesting(false)
        }.padding(12).contentShape(.rect)
    }
}

struct MetricStatus: View {
    let value: MetricValue
    var expanded = false
    var body: some View {
        Label(expanded ? value.detail : value.summary, systemImage: symbol)
            .font(.footnote).foregroundStyle(value.status == .warn ? Palette.orange : Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var symbol: String {
        switch value.status {
        case .warn: "chart.line.uptrend.xyaxis"
        case .ok: "checkmark.circle"
        case .neutral: "arrow.up.right"
        }
    }
}

private struct TrendPoint: Identifiable {
    let slot: Int
    let value: Double
    var id: Int { slot }
}

extension MetricDefinition {
    func formatted(_ value: Double) -> String {
        if unit == "$" { return String(format: "$%.2f", value) }
        return String(format: unit == "%" && value >= 10 ? "%.0f%@" : "%.1f%@", value, unit)
    }
    func timeLabel(_ slot: Int, in range: TimeRange) -> String {
        let remaining = series[range].count - 1 - slot
        if remaining == 0 { return "Now" }
        switch range {
        case .hour: return "\(remaining * 5) min ago"
        case .day: return "\(remaining)h ago"
        case .week: return "\(remaining)d ago"
        }
    }
}

struct TrendChart: View {
    let definition: MetricDefinition
    let range: TimeRange
    let warning: Bool
    var compact = false
    // The sample under the finger while dragging; nil once it lifts.
    var selection: Binding<Int?> = .constant(nil)

    private var series: [Double] { definition.series[range] }
    private var points: [TrendPoint] { series.enumerated().map { TrendPoint(slot: $0.offset, value: $0.element) } }
    private var band: MetricBand { definition.band[range] }
    private var domain: ClosedRange<Double> {
        let low = min(series.min() ?? 0, band.low)
        let high = max(series.max() ?? 1, band.high)
        let padding = max((high - low) * 0.12, 0.01)
        return (compact ? low - padding : max(0, low - padding))...(high + padding)
    }
    private var selected: TrendPoint? { points.first { $0.slot == selection.wrappedValue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                RectangleMark(xStart: .value("Start", 0), xEnd: .value("End", max(series.count - 1, 1)),
                              yStart: .value("Usual low", band.low), yEnd: .value("Usual high", band.high))
                    .foregroundStyle(Palette.chart.opacity(0.08))
                    .accessibilityLabel("Usual range \(definition.formatted(band.low)) to \(definition.formatted(band.high))")
                ForEach(points) { point in
                    LineMark(x: .value("Sample", point.slot), y: .value(definition.title, point.value))
                        .foregroundStyle(warning ? Palette.orange : Palette.chart)
                        .lineStyle(StrokeStyle(lineWidth: compact ? 1.75 : 2.25, lineCap: .round, lineJoin: .round))
                        .accessibilityLabel(definition.timeLabel(point.slot, in: range)).accessibilityValue(definition.formatted(point.value))
                }
                if let selected {
                    RuleMark(x: .value("Selected sample", selected.slot)).foregroundStyle(Palette.muted)
                    PointMark(x: .value("Sample", selected.slot), y: .value(definition.title, selected.value))
                        .foregroundStyle(warning ? Palette.orange : Palette.chart).symbolSize(70)
                } else if let last = points.last {
                    PointMark(x: .value("Sample", last.slot), y: .value(definition.title, last.value))
                        .foregroundStyle(warning ? Palette.orange : Palette.chart).symbolSize(compact ? 20 : 40)
                        .annotation(position: .top, alignment: .trailing) {
                            if !compact { Text(definition.formatted(last.value)).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink) }
                        }
                }
            }
            .chartYScale(domain: domain)
            .chartXScale(domain: 0...max(series.count - 1, 1))
            .chartXAxis {
                if !compact {
                    AxisMarks(values: Array(Set([0, (series.count - 1) / 2, max(series.count - 1, 0)])).sorted()) { axis in
                        AxisGridLine().foregroundStyle(Palette.line)
                        AxisValueLabel(anchor: axis.index == 0 ? .topLeading : axis.index == axis.count - 1 ? .topTrailing : .top, collisionResolution: .disabled) {
                            if let slot = axis.as(Int.self) { Text(definition.timeLabel(slot, in: range)).font(.caption) }
                        }
                    }
                }
            }
            .chartYAxis {
                if !compact {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { axis in
                        AxisGridLine().foregroundStyle(Palette.line)
                        AxisValueLabel {
                            if let value = axis.as(Double.self) { Text(definition.formatted(value)).font(.caption) }
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartXSelection(value: selection)
            .accessibilityIdentifier("metricTrend")
            .frame(maxHeight: .infinity)
            if !compact {
                Label("Usual range · \(definition.formatted(band.low))–\(definition.formatted(band.high))", systemImage: "rectangle.fill")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
        }
    }
}

struct MetricDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    let kind: MetricKind
    @State private var selectedSlot: Int?
    private var definition: MetricDefinition { store.data.metrics[kind] }
    private var snapshot: OverviewSnapshot { store.data.snapshots[window.range] }
    private var value: MetricValue { snapshot.value(for: kind) }
    private var selectedValue: Double? {
        let series = definition.series[window.range]
        return selectedSlot.flatMap { series.indices.contains($0) ? series[$0] : nil }
    }

    var body: some View {
        NavigationStack {
            Screen {
                // While dragging, the headline shows the sample under the finger instead of the current value.
                Text(selectedValue.map(definition.formatted) ?? (kind == .spend ? "$\(value.value)" : "\(value.value)\(definition.unit)"))
                    .font(.system(.largeTitle, design: .default, weight: .bold)).monospacedDigit()
                    .padding(.top, 12).accessibilityIdentifier("metricValue")
                Group {
                    if let selectedSlot {
                        Label(definition.timeLabel(selectedSlot, in: window.range), systemImage: "clock")
                            .font(.caption).foregroundStyle(Palette.muted)
                    } else {
                        MetricStatus(value: value, expanded: true)
                    }
                }.padding(.top, 5)
                Text(window.range.label).font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 18)
                TrendChart(definition: definition, range: window.range, warning: value.status == .warn, selection: $selectedSlot)
                    .frame(height: 250).padding(.top, 12)
                SectionHeading(title: breakdownTitle)
                SurfaceGroup {
                    ForEach(breakdown) { item in
                        if item.id != breakdown.first?.id { RowDivider() }
                        HStack {
                            Circle().fill(item.color).frame(width: 9, height: 9)
                            Text(item.id).font(.subheadline)
                            Spacer()
                            Text(item.value).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }.padding(16)
                    }
                }
                if let cta = definition.cta {
                    PrimaryButton(title: cta, symbol: "arrow.right") {
                        dismiss()
                        window.openMetric(kind)
                    }.padding(.top, 22).accessibilityIdentifier("metricAction")
                }
                Text("Illustrative metrics from the design concept.")
                    .font(.caption).foregroundStyle(Palette.muted).padding(.top, 12)
            }
            .navigationTitle(definition.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close", systemImage: "xmark") { dismiss() } } }
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }

    private var breakdownTitle: String {
        switch kind { case .errors: "By failed step"; case .latency: "P95 by trace"; case .spend: "By model"; case .quality: "By score" }
    }
    private struct Breakdown: Identifiable { let id: String; let value: String; let color: Color }
    private var breakdown: [Breakdown] {
        switch kind {
        case .errors:
            return snapshot.failedSteps.sorted { $0.value > $1.value }
                .map { .init(id: $0.key, value: String($0.value), color: Palette.red) }
        case .latency:
            return [.init(id: "summarize-thread", value: "6.2s", color: Palette.orange),
                    .init(id: "answer-question", value: "2.1s", color: Palette.ink),
                    .init(id: "search-documents", value: "0.3s", color: Palette.muted)]
        case .spend:
            return [.init(id: "Primary model", value: String(format: "$%.2f", snapshot.models[0]), color: Palette.ink),
                    .init(id: "Fast model", value: String(format: "$%.2f", snapshot.models[1]), color: Palette.muted)]
        case .quality:
            return [.init(id: "Good", value: String(snapshot.reviews[0]), color: Palette.ink),
                    .init(id: "Needs work", value: String(snapshot.reviews[1]), color: Palette.orange)]
        }
    }
}
