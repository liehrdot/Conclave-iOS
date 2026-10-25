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
    /// How often an open app asks whether the PC signed it off (the PWA's status poll is a minute too).
    private static let checkEvery: Duration = .seconds(60)

    var body: some View {
        Group {
            if let device = model.device {
                PairedView(device: device)
            } else {
                WelcomeView(entering: AppModel.startScreen == "code", scanning: AppModel.startScreen == "scan", notice: model.notice)
            }
        }
        // on opening, on every return to the app and once a minute while it is open; never in the background
        .task(id: phase) {
            guard phase == .active, AppModel.startScreen == nil else { return }
            while !Task.isCancelled {
                await model.checkStillPaired()
                try? await Task.sleep(for: Self.checkEvery)
            }
        }
        // a haptic for the outcome, not for the tap (the research's rule): the moment pairing worked
        .sensoryFeedback(.success, trigger: model.device?.id) { old, new in old == nil && new != nil }
    }
}
