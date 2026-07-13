import SwiftUI

@main
struct LGRemoteApp: App {
    @StateObject private var viewModel = RemoteViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.connectIfNeeded()
                viewModel.refreshStatuses()
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var viewModel: RemoteViewModel

    /// The app's display name, so alerts match the home-screen name in every build.
    static let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? "TV Remote"

    var body: some View {
        Group {
            if viewModel.showPicker {
                TVPickerView()
            } else {
                RemoteView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showPicker)
        .onAppear { viewModel.connectIfNeeded() }
            .sheet(isPresented: $viewModel.showSetup) {
                SetupView()
            }
            .alert(Self.appName, isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
    }
}

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func heavy() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
