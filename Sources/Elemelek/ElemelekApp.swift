import SwiftUI
import ElemelekCore

@main
struct ElemelekApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup("Elemelek") {
            RootView().environment(model).task { await model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 760)
        Settings { SettingsView().environment(model).environment(\.zoomFactor, CGFloat(model.zoom)) }
        .commands {
            CommandMenu("View") {
                Button("Zoom In") { model.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(model.zoom >= TextZoom.max)
                Button("Zoom Out") { model.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(model.zoom <= TextZoom.min)
                Button("Actual Size") { model.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(model.zoom == TextZoom.default)
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) var model
    var body: some View {
        Group {
            switch model.state {
            case .starting: ProgressView().frame(minWidth: 400, minHeight: 300).background(Theme.background)
            case .loggedOut: LoginView()
            case .syncing: MainView()
            }
        }
        .environment(\.zoomFactor, CGFloat(model.zoom))
    }
}

