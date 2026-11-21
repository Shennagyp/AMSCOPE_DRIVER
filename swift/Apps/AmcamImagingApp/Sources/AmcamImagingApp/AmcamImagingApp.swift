import AppKit

@main
@MainActor
final class AmcamImagingAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var model: CameraApplicationModel?
    private var terminationTimeoutTask: Task<Void, Never>?
    private var hasRepliedToTermination = false

    static func main() {
        let application = NSApplication.shared
        let delegate = AmcamImagingAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = CameraApplicationModel()
        self.model = model
        installMainMenu()
        presentMainWindow()
        model.initialize()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        // A Settings window can remain open after the main camera window closes.
        // Reopen based on the camera window itself, not any visible app window.
        if window == nil || window?.isVisible != true || window?.isMiniaturized == true {
            presentMainWindow()
        }
        return true
    }

    private func presentMainWindow() {
        if let window, window.isVisible {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let model else { return }
        let controller = CameraMainViewController(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Amcam Imaging"
        window.minSize = NSSize(width: 980, height: 680)
        window.center()
        window.contentViewController = controller
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        menu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let quit = appMenu.addItem(
            withTitle: "Quit Amcam Imaging",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        appMenuItem.submenu = appMenu

        let cameraItem = NSMenuItem()
        menu.addItem(cameraItem)
        let cameraMenu = NSMenu(title: "Camera")
        let refresh = cameraMenu.addItem(
            withTitle: "Refresh Cameras",
            action: #selector(refreshCameras),
            keyEquivalent: "r"
        )
        refresh.target = self
        let fullscreen = cameraMenu.addItem(
            withTitle: "Toggle Full Screen",
            action: #selector(toggleFullScreen),
            keyEquivalent: "f"
        )
        fullscreen.target = self
        cameraItem.submenu = cameraMenu
        NSApp.mainMenu = menu
    }

    @objc private func refreshCameras() { model?.refreshDevices() }
    @objc private func toggleFullScreen() { window?.toggleFullScreen(nil) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }

        hasRepliedToTermination = false
        Task { @MainActor [weak self, model] in
            guard let self else { return }

            // Camera SDK calls are native code and may fail or block indefinitely.
            // Give orderly cleanup a bounded opportunity, but never let a vendor
            // driver veto an explicit application termination.
            let shutdownTask = Task { @MainActor in
                await model.shutdown()
            }
            self.terminationTimeoutTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    return
                }
                self?.completeTermination(cleanupSucceeded: false, timedOut: true)
            }

            let cleanupSucceeded = await shutdownTask.value
            self.completeTermination(cleanupSucceeded: cleanupSucceeded, timedOut: false)
        }
        return .terminateLater
    }

    private func completeTermination(cleanupSucceeded: Bool, timedOut: Bool) {
        guard !hasRepliedToTermination else { return }
        hasRepliedToTermination = true
        terminationTimeoutTask?.cancel()
        terminationTimeoutTask = nil

        if timedOut {
            NSLog("Amcam Imaging: camera cleanup exceeded the 10-second shutdown deadline; terminating process.")
        } else if !cleanupSucceeded {
            NSLog("Amcam Imaging: camera cleanup failed; terminating process anyway.")
        }

        // Termination is the user's command. A failed native teardown must not
        // leave an invisible process resident in the Dock; the OS reclaims any
        // resources still owned by this process.
        NSApp.reply(toApplicationShouldTerminate: true)
    }
}
