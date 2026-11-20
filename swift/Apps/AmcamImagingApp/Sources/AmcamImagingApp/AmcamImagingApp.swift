import AppKit

@main
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
        window.makeKeyAndOrderFront(nil)
        self.window = window

        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        menu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let quit = appMenu.addItem(withTitle: "Quit Amcam Imaging", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenuItem.submenu = appMenu

        let cameraItem = NSMenuItem()
        menu.addItem(cameraItem)
        let cameraMenu = NSMenu(title: "Camera")
        let refresh = cameraMenu.addItem(withTitle: "Refresh Cameras", action: #selector(refreshCameras), keyEquivalent: "r")
        refresh.target = self
        let fullscreen = cameraMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(toggleFullScreen), keyEquivalent: "f")
        fullscreen.target = self
        cameraItem.submenu = cameraMenu
        NSApp.mainMenu = menu

        model.initialize()
        model.enterFullScreen()
    }

    @objc private func refreshCameras() { model?.refreshDevices() }
    @objc private func toggleFullScreen() { model?.toggleFullScreen() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}
