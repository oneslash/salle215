import SwiftUI

@main
struct Salle215App: App {
    @State private var store = AppStore(reset: ProcessInfo.processInfo.arguments.contains("--uitesting"))
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(Palette.primary).foregroundStyle(Palette.ink)
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--uitesting"),
                       let mode = ProcessInfo.processInfo.environment["SALLE215_LIVE_FIXTURE"] {
                        let api = LiveUITestAPI(mode: mode)
                        if let credentials = try? LangfuseCredentials(host: "https://example.com", publicKey: "pk-test", secretKey: "sk-test") {
                            await store.connect(credentials, transport: { try await api.send($0) })
                        }
                        return
                    }
                    #endif
                    if !ProcessInfo.processInfo.arguments.contains("--demo") { await store.restoreConnection() }
                }
                .onAppear {
                    if ProcessInfo.processInfo.arguments.contains("--demo") { store.connectSample() }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if store.isConnected {
            if store.isLive { LiveTabs() } else { MainTabs() }
        } else { WelcomeView() }
    }
}
struct WelcomeView: View {
    @Environment(AppStore.self) private var store
    @State private var showConnection = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(.rect(cornerRadius: 24))
                    .padding(.bottom, 24).accessibilityHidden(true)
                Text("Salle 215").font(.largeTitle.bold())
                Text("Production health, traces and reviews for your LLM apps.")
                    .font(.body).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    .padding(.horizontal, 32).padding(.top, 8)
                Spacer()
                if store.isLoading { ProgressView("Connecting to Langfuse…").padding(.bottom, 16) }
                if let error = store.connectionError {
                    Text(error).font(.footnote).foregroundStyle(Palette.red).padding(.bottom, 12)
                }
                PrimaryButton(title: "Connect to Langfuse") { showConnection = true }
                    .disabled(store.isLoading).accessibilityIdentifier("connectLangfuse")
                Button("Explore a sample project") { store.connectSample() }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    .background(Palette.fill, in: .capsule)
                    .accessibilityIdentifier("exploreSample")
                    .disabled(store.isLoading).padding(.top, 10)
                Text("Built for Langfuse Cloud and self-hosted Langfuse v4.")
                    .font(.footnote).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    .padding(.top, 14).padding(.bottom, 24)
            }.padding(.horizontal, 16).background(Palette.background)
                .navigationDestination(isPresented: $showConnection) { LangfuseConnectionView() }
        }
    }
}
struct MainTabs: View {
    @Environment(AppStore.self) private var store
    @State private var window = WindowState()
    var body: some View {
        TabView(selection: $window.tab) {
            Tab("Overview", systemImage: "waveform.path.ecg", value: .overview) {
                NavigationStack { OverviewView().modifier(ProjectToolbar()).modifier(AppDestinations()) }
            }
            Tab("Traces", systemImage: "list.bullet.indent", value: .traces) {
                NavigationStack(path: $window.tracePath) { TracesView().modifier(ProjectToolbar()).modifier(AppDestinations()) }
            }
            Tab("Review", systemImage: "checkmark.bubble", value: .review) {
                NavigationStack { ReviewView().modifier(ProjectToolbar()).modifier(AppDestinations()) }.badge(store.pendingReviews)
            }
            Tab("Prompts", systemImage: "doc.text", value: .prompts) {
                NavigationStack { PromptsView().modifier(ProjectToolbar()).modifier(AppDestinations()) }
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                NavigationStack { SearchView().modifier(AppDestinations()) }
            }
        }
        .environment(window)
    }
}
struct ProjectToolbar: ViewModifier {
    @Environment(AppStore.self) private var store
    @State private var confirmDisconnect = false
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Section("Sample workspace") {
                        Label("Support agent · Acme", systemImage: "checkmark")
                        Text("This workspace uses sample data.")
                    }
                    Section {
                        Button("Leave sample project", systemImage: "rectangle.portrait.and.arrow.right") { confirmDisconnect = true }
                    }
                } label: {
                    ProjectMenuLabel(title: "Support agent", environment: "Sample · production")
                }.accessibilityIdentifier("projectMenu")
            }
        }
        .confirmationDialog("Leave the sample project?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Leave sample project", role: .destructive) { store.disconnect() }
        } message: { Text("Your sample reviews stay on this device. You can return at any time.") }
    }
}
