import SwiftUI

@main
struct AmcamImagingApp: App {
    @StateObject private var model = CameraApplicationModel()

    var body: some Scene {
        WindowGroup {
            CameraMainView(model: model)
                .frame(minWidth: 980, minHeight: 680)
                .preferredColorScheme(.dark)
                .onAppear {
                    model.initialize()
                    model.enterFullScreen()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Camera") {
                Button(model.isFullScreen ? "Exit Full Screen" : "Enter Full Screen") {
                    model.toggleFullScreen()
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
                Button("Refresh Cameras") { model.refreshDevices() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
