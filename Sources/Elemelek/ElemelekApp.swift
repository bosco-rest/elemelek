import SwiftUI

@main
struct ElemelekApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup("Elemelek") {
            RootView().environment(model).task { await model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 760)
        Settings { SettingsView().environment(model) }
    }
}

struct RootView: View {
    @Environment(AppModel.self) var model
    var body: some View {
        switch model.state {
        case .starting: ProgressView().frame(minWidth: 400, minHeight: 300).background(Theme.background)
        case .loggedOut: LoginView()
        case .syncing: MainView()
        }
    }
}

