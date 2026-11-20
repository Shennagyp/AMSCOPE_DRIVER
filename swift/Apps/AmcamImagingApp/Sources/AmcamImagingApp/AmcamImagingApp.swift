import AppKit

@main
@MainActor
final class AmcamImagingAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var model: CameraApplicationModel?

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
        if !hasVisibleWindows {
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
        Task { @MainActor in
            let resourcesClosed = await model.shutdown()
            if !resourcesClosed {
                // A failed camera teardown cancels termination. Restore the UI
                // so the user can see the cleanup error and retry explicitly.
                presentMainWindow()
            }
            NSApp.reply(toApplicationShouldTerminate: resourcesClosed)
        }
        return .terminateLater
    }
}
