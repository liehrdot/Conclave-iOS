import ConclaveCore
import SwiftUI

@main
struct ConclaveApp: App {
    @State private var model = AppModel.launch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

/// Paired or not: the one switch at the top of the app.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    /// How often an open app asks for news (the PWA's status poll is a minute too). Each ask is cheap:
    /// an unchanged read model answers 304 without a body.
    private static let checkEvery: Duration = .seconds(60)

    var body: some View {
        Group {
            if let device = model.device {
                MainView(device: device)
            } else {
                WelcomeView(entering: AppModel.startScreen == "code", scanning: AppModel.startScreen == "scan", notice: model.notice)
            }
        }
        // on opening, on every return to the app and once a minute while it is open; never in the background.
        // A 401 on the way (signed off on the PC) leads back to the welcome screen.
        .task(id: phase) {
            guard phase == .active, AppModel.startScreen == nil else { return }
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: Self.checkEvery)
            }
        }
        // a haptic for the outcome, not for the tap (the research's rule): the moment pairing worked
        .sensoryFeedback(.success, trigger: model.device?.id) { old, new in old == nil && new != nil }
    }
}
