import AppKit
import AmcamGenTL
import Foundation
import SwiftUI

@MainActor
final class CameraApplicationModel: ObservableObject {
    @Published private(set) var devices: [AmcamDevice] = []
    @Published var selectedDeviceID = ""
    @Published private(set) var latestImage: NSImage?
    @Published private(set) var isStreaming = false
    @Published private(set) var cameraCapabilities: AmcamCameraCapabilities?
    @Published private(set) var controls: AmcamControlSnapshot?
    @Published private(set) var status = "Select an AmScope camera"
    @Published var errorMessage: String?
    @Published var isSettingsPresented = false
    @Published private(set) var framesPerSecond = 0.0
    @Published private(set) var sdkPath: String?

    private var driver: AmcamCameraDriver?
    private var session: AmcamCameraSession?
    private var profileRegistry = AmcamCameraProfileRegistry()
    private var lastFrameHostTime: TimeInterval?
    private var frameIntervals: [TimeInterval] = []
    private(set) var isFullScreen = false

    var selectedDevice: AmcamDevice? {
        devices.first { $0.identifier == selectedDeviceID }
    }

    var currentResolution: AmcamResolution? {
        session?.currentResolution()
    }

    func initialize() {
        loadProfileConfiguration()
        if let url = defaultSDKURL() {
            configureSDK(at: url)
        } else {
            status = "Amcam SDK not found — choose libamcam.dylib"
        }
    }

    func chooseSDK() {
        let panel = NSOpenPanel()
        panel.title = "Select the Amcam SDK"
        panel.message = "Choose the vendor libamcam.dylib"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            configureSDK(at: url)
        }
    }

    func refreshDevices() {
        guard let driver else {
            chooseSDK()
            return
        }
        do {
            let found = try driver.discover()
            devices = found
            if !found.contains(where: { $0.identifier == selectedDeviceID }) {
                selectedDeviceID = found.first?.identifier ?? ""
                closeSession()
            }
            status = found.isEmpty ? "No AmScope cameras detected" : "\(found.count) camera(s) detected"
            errorMessage = nil
            if session == nil, selectedDevice != nil {
                prepareSelectedCamera()
            }
        } catch {
            status = "Camera discovery failed"
            errorMessage = error.localizedDescription
        }
    }

    func selectDevice(_ identifier: String) {
        guard identifier != selectedDeviceID else { return }
        closeSession()
        selectedDeviceID = identifier
        latestImage = nil
        cameraCapabilities = nil
        controls = nil
        status = selectedDevice.map { "Ready: \($0.displayName)" } ?? "No camera selected"
        prepareSelectedCamera()
    }

    func start() {
        guard let driver, let device = selectedDevice else {
            errorMessage = "Select a camera and configure the Amcam SDK first."
            return
        }
        guard cameraCapabilities?.availability(of: .liveCapture).isUsable == true else {
            errorMessage = "Live capture is disabled by this camera's capability profile or is not available."
            return
        }
        do {
            if session == nil {
                prepareSelectedCamera()
            }
            guard let session else { return }
            cameraCapabilities = try session.cameraCapabilities(using: profileRegistry)
            controls = try? session.readControls()
            latestImage = nil
            frameIntervals.removeAll(keepingCapacity: true)
            lastFrameHostTime = nil
            try session.start { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch result {
                    case .success(let frame):
                        self.accept(frame)
                    case .failure(let error):
                        self.isStreaming = false
                        self.status = "Camera stopped — session cleanup"
                        self.errorMessage = error.localizedDescription
                        self.closeSession()
                    }
                }
            }
            isStreaming = true
            status = "Live — \(device.displayName)"
            errorMessage = nil
        } catch {
            isStreaming = false
            status = "Unable to start camera"
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        guard let session, isStreaming else { return }
        do {
            try session.stop()
            isStreaming = false
            status = "Stopped — \(selectedDevice?.displayName ?? "camera")"
        } catch {
            errorMessage = error.localizedDescription
            status = "Camera stop failed"
        }
    }

    func shutdown() {
        closeSession()
    }

    func refreshControls() {
        guard let session else { return }
        controls = try? session.readControls()
        if let capabilities = try? session.cameraCapabilities(using: profileRegistry) {
            cameraCapabilities = capabilities
        }
    }

    func setAutoExposureMode(_ mode: AmcamAutoExposureMode) {
        guard let session else { return }
        do {
            controls = try session.setAutoExposureMode(mode)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func setExposureTime(_ microseconds: UInt32) {
        guard let session else { return }
        do {
            controls = try session.setExposureTime(microseconds: microseconds)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func setColorMatrixEnabled(_ enabled: Bool) {
        guard let session else { return }
        do {
            controls = try session.setColorMatrixEnabled(enabled)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func setPixelFormat(_ code: Int32) {
        guard let session, !isStreaming else { return }
        do {
            controls = try session.setPixelFormat(code: code)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func setWhiteBalanceRGBGain(_ values: [Int32]) {
        guard let session else { return }
        do {
            controls = try session.setWhiteBalanceRGBGain(values)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func setWhiteBalanceTemperatureTint(temperature: Int32, tint: Int32) {
        guard let session else { return }
        do {
            controls = try session.setWhiteBalanceTemperatureTint(temperature: temperature, tint: tint)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func setExposureGain(_ percent: UInt16) {
        guard let session else { return }
        do {
            controls = try session.setExposureGain(percent: percent)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func setFixedFrameRate(_ framesPerSecond: Double) {
        guard let session else { return }
        do {
            controls = try session.setFixedFrameRate(framesPerSecond: framesPerSecond)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func setFrameSpeedLevel(_ level: Int) {
        guard let session else { return }
        do {
            controls = try session.setFrameRateSpeedLevel(level)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func setResolution(_ index: Int) {
        guard let session, !isStreaming else { return }
        do {
            _ = try session.setResolution(index: index)
            refreshControls()
            latestImage = nil
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }


    func enterFullScreen() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
            if !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            self.isFullScreen = true
        }
    }

    func toggleFullScreen() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        window.toggleFullScreen(nil)
        isFullScreen.toggle()
    }

    private func prepareSelectedCamera() {
        guard let driver, let device = selectedDevice else { return }
        do {
            if session == nil {
                session = try driver.open(deviceIdentifier: device.identifier)
            }
            guard let session else { return }
            cameraCapabilities = try session.cameraCapabilities(using: profileRegistry)
            controls = try? session.readControls()
            status = "Ready — \(device.displayName)"
            errorMessage = nil
        } catch {
            session = nil
            cameraCapabilities = nil
            controls = nil
            status = "Unable to open camera"
            errorMessage = error.localizedDescription
        }
    }

    private func configureSDK(at url: URL) {
        do {
            let newDriver = try AmcamCameraDriver(libraryURL: url)
            driver = newDriver
            sdkPath = url.path
            refreshDevices()
            errorMessage = nil
        } catch {
            driver = nil
            sdkPath = url.path
            status = "Amcam SDK could not be loaded"
            errorMessage = error.localizedDescription
        }
    }

    private func closeSession() {
        if let session {
            if isStreaming { try? session.stop() }
            try? session.close()
        }
        session = nil
        isStreaming = false
        cameraCapabilities = nil
        controls = nil
    }

    private func accept(_ frame: AmcamFrame) {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: frame.width,
            pixelsHigh: frame.height,
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: frame.bytesPerRow,
            bitsPerPixel: 24
        ), let destination = representation.bitmapData else {
            errorMessage = "Unable to allocate the live-frame display buffer."
            return
        }

        frame.bytes.withUnsafeBytes { source in
            guard let baseAddress = source.baseAddress else { return }
            memcpy(destination, baseAddress, min(frame.bytes.count, representation.bytesPerRow * frame.height))
        }
        let image = NSImage(size: NSSize(width: frame.width, height: frame.height))
        image.addRepresentation(representation)
        latestImage = image

        let now = ProcessInfo.processInfo.systemUptime
        if let previous = lastFrameHostTime, now > previous {
            frameIntervals.append(now - previous)
            if frameIntervals.count > 30 { frameIntervals.removeFirst(frameIntervals.count - 30) }
            let mean = frameIntervals.reduce(0, +) / Double(frameIntervals.count)
            if mean > 0 { framesPerSecond = 1.0 / mean }
        }
        lastFrameHostTime = now
    }

    private func defaultSDKURL() -> URL? {
        let candidates = [
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("vendor/amcam/macos/libamcam.dylib"),
            URL(fileURLWithPath: "vendor/amcam/macos/libamcam.dylib"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/AmScopeMicroscope/SDK/libamcam.dylib"),
            URL(fileURLWithPath: "/Library/Application Support/AmScopeMicroscope/SDK/libamcam.dylib"),
            URL(fileURLWithPath: "/Library/Frameworks/libamcam.dylib"),
            URL(fileURLWithPath: "/usr/local/lib/libamcam.dylib"),
            URL(fileURLWithPath: "/opt/homebrew/lib/libamcam.dylib")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func loadProfileConfiguration() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AmcamImaging", isDirectory: true)
        let file = support.appendingPathComponent("camera-profiles.json")
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path) {
                try Data("[]".utf8).write(to: file, options: .atomic)
            }
            let profiles = try JSONDecoder().decode(
                [AmcamCameraModelProfile].self,
                from: Data(contentsOf: file)
            )
            profileRegistry = AmcamCameraProfileRegistry(profiles: profiles)
        } catch {
            errorMessage = "Camera profile configuration could not be loaded: \(error.localizedDescription)"
        }
    }
}
