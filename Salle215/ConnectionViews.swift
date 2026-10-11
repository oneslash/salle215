import SwiftUI

struct LangfuseConnectionView: View {
    @Environment(AppStore.self) private var store
    @State private var host = "https://cloud.langfuse.com"
    @State private var publicKey = ""
    @State private var secretKey = ""
    @State private var environment = ""
    @State private var error: String?
    @State private var connectionTask: Task<Void, Never>?
    private enum Field { case host, publicKey, secretKey, environment }
    @FocusState private var focusedField: Field?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Instance URL").font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
                    TextField("Instance URL", text: $host).keyboardType(.URL)
                    .focused($focusedField, equals: .host).accessibilityIdentifier("langfuseHost")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Public key").font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
                    TextField("Public key", text: $publicKey).privacySensitive()
                    .focused($focusedField, equals: .publicKey).accessibilityIdentifier("langfusePublicKey")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Secret key").font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
                    SecureField("Secret key", text: $secretKey)
                    .focused($focusedField, equals: .secretKey).accessibilityIdentifier("langfuseSecretKey")
                }
            } header: { Text("Langfuse project") } footer: {
                Text("Use your project's API keys from Langfuse Settings → API Keys. The instance URL must match your Cloud region or self-hosted v4 instance. Keys stay in this device's Keychain.")
            }
            Section {
                TextField("Environment (optional)", text: $environment).focused($focusedField, equals: .environment)
            } footer: { Text("Leave empty to include all environments. The connection starts with the last seven days of observations.") }
            if let error = error ?? store.connectionError {
                Section { Text(error).foregroundStyle(Palette.red).accessibilityIdentifier("connectionError") }
            }
            Section {
                Button {
                    focusedField = nil
                    do {
                        let credentials = try LangfuseCredentials(host: host, publicKey: publicKey, secretKey: secretKey, environment: environment)
                        error = nil
                        connectionTask = Task { await store.connect(credentials) }
                    } catch { self.error = error.localizedDescription }
                } label: {
                    HStack {
                        Text(store.isLoading ? "Connecting…" : "Connect")
                        Spacer()
                        if store.isLoading { ProgressView() }
                    }
                }.disabled(store.isLoading || publicKey.isEmpty || secretKey.isEmpty)
                    .accessibilityIdentifier("submitConnection")
            }
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .scrollDismissesKeyboard(.interactively)
        .submitLabel(.done).onSubmit { focusedField = nil }
        .navigationTitle("Connect to Langfuse").navigationBarTitleDisplayMode(.inline)
        .onDisappear { connectionTask?.cancel() }
    }
}

struct LiveTabs: View {
    @Environment(AppStore.self) private var store
    @State private var window = WindowState()
    var body: some View {
        TabView(selection: $window.tab) {
            Tab("Overview", systemImage: "waveform.path.ecg", value: .overview) {
                NavigationStack { OverviewView().modifier(LiveProjectToolbar()).modifier(AppDestinations()) }
            }
            Tab("Traces", systemImage: "list.bullet.indent", value: .traces) {
                NavigationStack(path: $window.tracePath) { TracesView().modifier(LiveProjectToolbar()).modifier(AppDestinations()) }
            }
            Tab("Review", systemImage: "checkmark.bubble", value: .review) {
                NavigationStack { LiveReviewView().modifier(LiveProjectToolbar()).modifier(AppDestinations()) }
            }
            Tab("Prompts", systemImage: "doc.text", value: .prompts) {
                NavigationStack { LivePromptsView().modifier(LiveProjectToolbar()).modifier(AppDestinations()) }
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                NavigationStack { LiveSearchView().modifier(LiveProjectToolbar()).modifier(AppDestinations()) }
            }
        }.environment(window)
    }
}

struct LiveProjectToolbar: ViewModifier {
    @Environment(AppStore.self) private var store
    @State private var confirmDisconnect = false
    @State private var showEnvironment = false
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Text(store.connectionHost)
                    Text(store.connectionEnvironment)
                    Button("Change environment", systemImage: "line.3.horizontal.decrease") { showEnvironment = true }
                    Button("Refresh traces", systemImage: "arrow.clockwise") { Task { await store.refreshObservations() } }
                        .disabled(store.isLoading)
                    Button("Disconnect", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmDisconnect = true }
                } label: {
                    ProjectMenuLabel(title: store.connectionHost, environment: store.connectionEnvironment)
                }.accessibilityIdentifier("projectMenu")
            }
        }
        .sheet(isPresented: $showEnvironment) { ConnectionEnvironmentView() }
        .confirmationDialog("Disconnect from Langfuse?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { store.disconnect() }
        } message: { Text("The saved API keys will be removed from this device.") }
    }
}

private struct ConnectionEnvironmentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var environment = ""
    @State private var selection = ""
    private let custom = "__custom_environment__"
    var body: some View {
        NavigationStack {
            Form {
                Section("Show activity from") {
                    Picker("Environment", selection: $selection) {
                        Text("All environments").tag("")
                        ForEach(store.knownEnvironments, id: \.self) { Text($0).tag($0) }
                        Text("Enter another environment…").tag(custom)
                    }.pickerStyle(.inline)
                    if selection == custom {
                        TextField("Environment name", text: $environment)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }
                Text("Known names come from loaded activity. Prompts are shared across environments.").font(.footnote).foregroundStyle(Palette.muted)
                if let error = store.connectionError { Text(error).foregroundStyle(Palette.red) }
                Button(store.isLoading ? "Connecting…" : "Apply environment") {
                    Task { await store.changeEnvironment(selection == custom ? environment : selection); if store.connectionError == nil { dismiss() } }
                }.disabled(store.isLoading)
            }.navigationTitle("Environment")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.isLoading) } }
        }.onAppear { selection = store.connectionEnvironment == "All environments" ? "" : store.connectionEnvironment }
            .interactiveDismissDisabled(store.isLoading)
    }
}

struct LiveLoadingStatus: View {
    @Environment(AppStore.self) private var store
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup("\(store.data.traces.count) loaded traces · Last 7 days", isExpanded: $expanded) {
                Text("Filters apply to loaded traces. Open a trace to fetch all its steps within this period.")
                    .font(.footnote).foregroundStyle(Palette.muted)
            }.font(.footnote).foregroundStyle(Palette.muted)
            if let error = store.connectionError {
                Text(error).font(.footnote).foregroundStyle(Palette.red)
                Button("Retry refresh") { Task { await store.refreshObservations() } }
            }
            if store.isLoading { ProgressView("Loading observations…") }
            if store.nextCursor != nil {
                Button("Load more steps", systemImage: "arrow.down") { Task { await store.loadMoreObservations() } }
                    .disabled(store.isLoading).accessibilityIdentifier("loadMoreObservations")
            }
        }.padding(.top, 14)
    }
}

struct LiveTraceDetailView: View {
    @Environment(AppStore.self) private var store
    let traceID: String
    @State private var isLoading = true
    @State private var error: String?
    @State private var attempt = 0
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading trace steps…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't load this trace", systemImage: "wifi.exclamationmark")
                } description: { Text(error) } actions: {
                    Button("Retry") { attempt += 1 }
                }
            } else if let trace = store.data.trace(traceID) {
                TraceDetailView(trace: trace)
                    .safeAreaInset(edge: .bottom) {
                        Text("Steps within the loaded 7-day period. Older steps may be outside this window.")
                            .font(.caption).foregroundStyle(Palette.muted).padding(10)
                            .frame(maxWidth: .infinity).background(Palette.background)
                    }
            }
        }
        .task(id: "\(attempt)-\(store.liveTo.timeIntervalSince1970)") {
            isLoading = true
            error = nil
            do { try await store.loadTrace(traceID) }
            catch is CancellationError { return }
            catch { self.error = error.localizedDescription }
            isLoading = false
        }
    }
}
