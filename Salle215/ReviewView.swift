import SwiftUI

struct ReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(WindowState.self) private var window
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var feedbackItem: ReviewItem?
    @State private var contextExpanded = true

    var body: some View {
        let current = window.currentReview(in: store)
        let total = store.data.review.count
        Screen {
            ScreenTitle(title: "Review")
            if let item = current, let trace = store.data.trace(item.traceID) {
                HStack {
                    Text("Answer quality").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(total - store.pendingReviews + 1) of \(total)")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }.padding(.top, 18)
                ProgressView(value: Double(total - store.pendingReviews), total: Double(total))
                    .tint(Palette.primary).padding(.top, 8).accessibilityLabel("Review queue progress")
                if let input = trace.input { QuestionBubble(text: input.summary) }
                AgentAnswer(label: "Agent answer", text: trace.output?.summary ?? "")
                DisclosureGroup(isExpanded: $contextExpanded) {
                    ForEach(item.docs, id: \.self) { doc in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(doc.title).font(.subheadline.weight(.semibold))
                            Text(doc.excerpt).font(.subheadline).foregroundStyle(Palette.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                    }
                } label: {
                    Label("Context used · \(item.docs.count) documents", systemImage: "book")
                        .font(.subheadline.weight(.medium))
                }.padding(14).card(.rect(cornerRadius: 18)).padding(.top, 18)
                VStack(spacing: 0) {
                    RowDivider()
                    NavigationLink(value: AppRoute.trace(trace.id)) {
                        RelatedRow(title: "Trace \(trace.id)", detail: "\(formatDuration(trace.duration)) · \(formatCost(trace.cost))",
                                   symbol: "list.bullet.indent")
                    }.buttonStyle(.plain).accessibilityIdentifier("reviewTrace")
                }.padding(.top, 14)
                Text("Reviews are saved on this device.").font(.caption).foregroundStyle(Palette.muted).padding(.top, 10)
            } else {
                ContentUnavailableView {
                    Label("All caught up", systemImage: "checkmark.circle")
                } description: {
                    Text("You’ve reviewed all \(total) sample answers.")
                }.padding(.top, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if current != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { window.skipReview(in: store) }.accessibilityIdentifier("skipReview")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if current != nil || window.reviewUndo != nil {
                VStack(spacing: 10) {
                    if let undo = window.reviewUndo {
                        HStack {
                            Text(undo.message).font(.subheadline)
                            Spacer()
                            Button("Undo") { window.undoReview(in: store) }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("undoReview")
                        }.padding(14).card(.rect(cornerRadius: 16))
                    }
                    if let item = current {
                        ReviewDecisions(needsWork: { feedbackItem = item }, good: { window.rate(.good, for: item.id, in: store) })
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: 640)
                .frame(maxWidth: .infinity).background(Palette.background)
            }
        }
        .animation(.default, value: window.reviewUndo == nil)
        .sheet(item: $feedbackItem) { item in ReviewFeedbackView(item: item) }
        .onChange(of: current?.id) { contextExpanded = true }
    }
}

private struct ReviewFeedbackView: View {
    @Environment(AppStore.self) private var store
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    let item: ReviewItem
    @State private var reasons: Set<String> = []
    @State private var comment = ""
    @State private var alreadyReviewed = false
    private let options = ["Incorrect", "Incomplete", "Ignores context", "Tone", "Other"]

    var body: some View {
        NavigationStack {
            Screen {
                Text("Trace \(item.traceID)").font(.caption).foregroundStyle(Palette.muted).padding(.top, 16)
                    .accessibilityIdentifier("feedbackTrace")
                if let input = store.data.trace(item.traceID)?.input { Text(input.summary).font(.headline).padding(.top, 6) }
                Text("Choose any reasons that apply.").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 16)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(options, id: \.self) { reason in
                        FilterChip(title: reason, selected: reasons.contains(reason)) {
                            if reasons.contains(reason) { reasons.remove(reason) } else { reasons.insert(reason) }
                        }.accessibilityIdentifier("reason-\(reason)")
                    }
                }.padding(.top, 18)
                TextField("Add a note (optional)", text: $comment, axis: .vertical)
                    .lineLimit(3...6).padding(16).card(.rect(cornerRadius: 18))
                    .padding(.top, 18).accessibilityIdentifier("reviewComment")
            }
            .navigationTitle("Feedback").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save rating") {
                        if window.rate(.needsWork, for: item.id, reasons: options.filter { reasons.contains($0) }, comment: comment, in: store) {
                            dismiss()
                        } else {
                            alreadyReviewed = true
                        }
                    }.fontWeight(.semibold).buttonStyle(.borderedProminent).accessibilityIdentifier("submitReview")
                }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .alert("Answer already reviewed", isPresented: $alreadyReviewed) {
            Button("Keep draft", role: .cancel) { }
            Button("Close feedback") { dismiss() }
        } message: {
            Text("This answer already has a saved rating. Your draft has not been saved.")
        }
    }
}
