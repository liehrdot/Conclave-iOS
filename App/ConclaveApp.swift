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

    var body: some View {
        Group {
            if let device = model.device {
                PairedView(device: device)
            } else {
                WelcomeView(entering: AppModel.startScreen == "code")
            }
        }
        // a haptic for the outcome, not for the tap (the research's rule): the moment pairing worked
        .sensoryFeedback(.success, trigger: model.device?.id) { old, new in old == nil && new != nil }
    }
}
