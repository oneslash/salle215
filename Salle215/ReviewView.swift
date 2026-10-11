import SwiftUI

struct ReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(WindowState.self) private var window
    @State private var feedbackItem: ReviewItem?
    @State private var contextExpanded = false

    var body: some View {
        let current = window.currentReview(in: store)
        let total = store.data.review.count
        ScrollViewReader { scroll in
            Screen(horizontalPadding: 24) {
                ReviewHeader(progress: current == nil ? nil : "\(total - store.pendingReviews + 1) of \(total)",
                             skip: current == nil ? nil : { window.skipReview(in: store) })
                    .id("reviewTop")
                if let item = current, let trace = store.data.trace(item.traceID) {
                    ReviewConversation(question: trace.input?.summary, answer: trace.output)
                        .padding(.top, 24)
                    ReviewDecisions(needsWork: { feedbackItem = item }, good: { window.rate(.good, for: item.id, in: store) })
                        .padding(.top, 24)
                    ReviewSources(title: "\(item.docs.count) sources", expanded: $contextExpanded) {
                        ForEach(item.docs, id: \.self) { doc in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(doc.title).font(.subheadline.weight(.semibold))
                                Text(doc.excerpt).font(.subheadline).foregroundStyle(Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.top, 28)
                    ReviewTraceLink(traceID: trace.id).padding(.top, 8)
                    Text("Reviews stay on this device").font(.caption).foregroundStyle(Palette.muted).padding(.top, 16)
                } else {
                    ContentUnavailableView {
                        Label("All caught up", systemImage: "checkmark.circle")
                    } description: {
                        Text("You’ve reviewed all \(total) sample answers.")
                    }.padding(.top, 40)
                }
            }
            .onChange(of: current?.id) {
                contextExpanded = false
                scroll.scrollTo("reviewTop", anchor: .top)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let undo = window.reviewUndo {
                HStack(spacing: 16) {
                    Text(undo.message).font(.subheadline)
                    Spacer(minLength: 0)
                    Button("Undo") { window.undoReview(in: store) }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        .accessibilityIdentifier("undoReview")
                }
                .padding(.horizontal, 24).padding(.vertical, 8).frame(maxWidth: 640)
                .frame(maxWidth: .infinity).background(Palette.background)
            }
        }
        .animation(.default, value: window.reviewUndo == nil)
        .sheet(item: $feedbackItem) { item in ReviewFeedbackView(item: item) }
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
            Screen(horizontalPadding: 24) {
                Text("Trace \(item.traceID)").font(.caption).foregroundStyle(Palette.muted).padding(.top, 16)
                    .accessibilityIdentifier("feedbackTrace")
                if let input = store.data.trace(item.traceID)?.input { Text(input.summary).font(.headline).padding(.top, 6) }
                Text("Choose any reasons that apply.").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 16)
                ReviewReasonChoices(options: options, reasons: $reasons).padding(.top, 18)
                TextField("Add a note (optional)", text: $comment, axis: .vertical)
                    .lineLimit(3...6).textFieldStyle(.plain)
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
                    }.fontWeight(.semibold).accessibilityIdentifier("submitReview")
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

struct ReviewHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let progress: String?
    var skip: (() -> Void)? = nil
    var skipDisabled = false

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16))
        layout {
            Text("Review").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            HStack(spacing: 24) {
                Spacer(minLength: 0)
                if let progress {
                    Text(progress).font(.subheadline).foregroundStyle(Palette.muted)
                        .accessibilityIdentifier("reviewProgress")
                }
                if let skip {
                    Button("Skip", action: skip).font(.body.weight(.medium)).foregroundStyle(Palette.green)
                        .buttonStyle(.plain).frame(minHeight: 44).disabled(skipDisabled)
                        .accessibilityIdentifier("skipReview")
                }
            }
        }
    }
}

struct ReviewConversation: View {
    let question: String?
    let answer: MessageContent?
    private var answerText: String? {
        switch answer {
        case .messages(let messages): (messages.last { $0.role == "assistant" } ?? messages.last)?.content
        default: answer?.summary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let question {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Customer").font(.footnote).foregroundStyle(Palette.muted)
                    Text(question).font(.title3).textSelection(.enabled)
                }
            }
            if let answerText {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Agent").font(.footnote).foregroundStyle(Palette.muted)
                    Text(answerText).font(.body).textSelection(.enabled)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReviewSources<Content: View>: View {
    let title: String
    @Binding var expanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "book").font(.system(size: 20)).frame(width: 22).accessibilityHidden(true)
                    Text(title).font(.body)
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted).accessibilityHidden(true)
                }.frame(minHeight: 44).contentShape(.rect)
            }.buttonStyle(.plain).accessibilityValue(expanded ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("reviewSources")
            if expanded {
                VStack(alignment: .leading, spacing: 20) { content }.padding(.leading, 34)
            }
        }
    }
}

struct ReviewTraceLink: View {
    let traceID: String
    var body: some View {
        NavigationLink(value: AppRoute.trace(traceID)) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text").font(.system(size: 20)).frame(width: 22).accessibilityHidden(true)
                Text("Trace details").font(.body)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.muted).accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(.rect)
        }.buttonStyle(.plain).accessibilityValue(traceID).accessibilityIdentifier("reviewTrace")
    }
}

struct ReviewReasonChoices: View {
    let options: [String]
    @Binding var reasons: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(options, id: \.self) { reason in
                Button {
                    if reasons.contains(reason) { reasons.remove(reason) } else { reasons.insert(reason) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: reasons.contains(reason) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(reasons.contains(reason) ? Palette.green : Palette.muted)
                            .accessibilityHidden(true)
                        Text(reason).font(.body)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 44).contentShape(.rect)
                }.buttonStyle(.plain).accessibilityValue(reasons.contains(reason) ? "Selected" : "Not selected")
                    .accessibilityIdentifier("reason-\(reason)")
            }
        }
    }
}
