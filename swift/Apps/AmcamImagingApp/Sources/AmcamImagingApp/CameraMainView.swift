import AppKit
import Darwin
import AmcamCameraModel
import AmcamImagingCore
import Combine

private extension NSView {
    func pinEdges(to view: NSView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            topAnchor.constraint(equalTo: view.topAnchor, constant: inset),
            bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -inset)
        ])
    }
}

private func makeLabel(_ value: String, size: CGFloat = 13, color: NSColor = .labelColor) -> NSTextField {
    let label = NSTextField(labelWithString: value)
    label.font = .systemFont(ofSize: size)
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    return label
}

private func makeButton(_ title: String, target: AnyObject, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .rounded
    return button
}

final class CameraMainViewController: NSViewController {
    private let model: CameraApplicationModel
    private var observation: AnyCancellable?
    private let preview = NSImageView()
    private let titleLabel = makeLabel("No camera selected", size: 14)
    private let detailLabel = makeLabel("Select an AmScope camera", size: 11, color: .secondaryLabelColor)
    private let statusLabel = makeLabel("Select an AmScope camera", size: 12, color: .secondaryLabelColor)
    private let errorLabel = makeLabel("", size: 11, color: .systemRed)
    private let liveLabel = makeLabel("", size: 11, color: .systemRed)
    private let cameraPicker = NSPopUpButton()
    private let startButton = NSButton(title: "Start", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private var settingsWindow: NSWindow?
    private var displayedFrameSequence: UInt64?

    init(model: CameraApplicationModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        view = root

        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.backgroundColor = NSColor.black.cgColor
        preview.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(preview)

        let header = NSStackView(views: [titleLabel, detailLabel, NSView(), liveLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        footer.translatesAutoresizingMaskIntoConstraints = false
        cameraPicker.widthAnchor.constraint(equalToConstant: 240).isActive = true
        cameraPicker.target = self
        cameraPicker.action = #selector(cameraChanged)
        footer.addArrangedSubview(cameraPicker)
        footer.addArrangedSubview(makeButton("Refresh", target: self, action: #selector(refreshCameras)))
        startButton.target = self
        startButton.action = #selector(startCapture)
        footer.addArrangedSubview(startButton)
        stopButton.target = self
        stopButton.action = #selector(stopCapture)
        footer.addArrangedSubview(stopButton)
        footer.addArrangedSubview(makeButton("Settings…", target: self, action: #selector(showSettings)))
        footer.addArrangedSubview(makeButton("Full Screen", target: self, action: #selector(toggleFullScreen)))
        root.addSubview(footer)

        let statusStack = NSStackView(views: [statusLabel, errorLabel])
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 3
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusStack)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            preview.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            preview.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            preview.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            preview.bottomAnchor.constraint(equalTo: statusStack.topAnchor, constant: -12),
            statusStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            statusStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            statusStack.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            footer.heightAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }
        render()
    }

    private func render() {
        titleLabel.stringValue = model.selectedDevice?.displayName ?? "No camera selected"
        detailLabel.stringValue = model.selectedDevice?.modelCode ?? model.status
        statusLabel.stringValue = model.status
        errorLabel.stringValue = model.errorMessage ?? ""
        liveLabel.stringValue = model.isStreaming
            ? String(format: "● LIVE   %.1f FPS", model.framesPerSecond)
            : ""
        if let frame = model.latestFrame {
            if frame.sequence != displayedFrameSequence {
                preview.image = makePreviewImage(from: frame)
                displayedFrameSequence = frame.sequence
            }
        } else {
            preview.image = nil
            displayedFrameSequence = nil
        }

        let selectedID = model.selectedDeviceID
        cameraPicker.removeAllItems()
        if model.devices.isEmpty {
            cameraPicker.addItem(withTitle: "No cameras detected")
            cameraPicker.item(at: 0)?.isEnabled = false
        } else {
            for device in model.devices {
                cameraPicker.addItem(withTitle: device.displayName)
                cameraPicker.lastItem?.representedObject = device.identifier
            }
            if let index = model.devices.firstIndex(where: { $0.identifier == selectedID }) {
                cameraPicker.selectItem(at: index)
            }
        }
        cameraPicker.isEnabled = !model.isStreaming
        startButton.isEnabled = !model.isStreaming
            && model.selectedDevice != nil
            && model.cameraCapabilities?.availability(of: .liveCapture).isUsable == true
        stopButton.isEnabled = model.isStreaming
    }

    private func makePreviewImage(from frame: RGB8Frame) -> NSImage? {
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
            return nil
        }

        frame.data.withUnsafeBytes { source in
            guard let baseAddress = source.baseAddress else { return }
            memcpy(destination, baseAddress, frame.data.count)
        }

        let image = NSImage(size: NSSize(width: frame.width, height: frame.height))
        image.addRepresentation(representation)
        return image
    }

    @objc private func cameraChanged() {
        guard let identifier = cameraPicker.selectedItem?.representedObject as? String else { return }
        model.selectDevice(identifier)
    }
    @objc private func refreshCameras() {
        model.refreshDevices()
    }
    @objc private func startCapture() { model.start() }
    @objc private func stopCapture() { model.stop() }
    @objc private func toggleFullScreen() { view.window?.toggleFullScreen(nil) }

    @objc private func showSettings() {
        model.refreshControls()
        let controller = CameraSettingsViewController(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Camera Settings"
        window.contentViewController = controller
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }
}

final class CameraSettingsViewController: NSViewController {
    private let model: CameraApplicationModel
    private var observation: AnyCancellable?
    private let content = NSStackView()
    private var exposureSlider: NSSlider?
    private var gainSlider: NSSlider?
    private var temperatureSlider: NSSlider?
    private var tintSlider: NSSlider?
    private var frameRateSlider: NSSlider?
    private var exposureValue = NSTextField(labelWithString: "")
    private var gainValue = NSTextField(labelWithString: "")
    private var temperatureValue = NSTextField(labelWithString: "")
    private var tintValue = NSTextField(labelWithString: "")
    private var redField = NSTextField(string: "100")
    private var greenField = NSTextField(string: "100")
    private var blueField = NSTextField(string: "100")
    private var resolutionPicker = NSPopUpButton()
    private var pixelFormatPicker = NSPopUpButton()
    private var exposureModePicker = NSPopUpButton()
    private var colorMatrixButton = NSButton(checkboxWithTitle: "Color matrix", target: nil, action: nil)

    init(model: CameraApplicationModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let root = NSView()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        content.translatesAutoresizingMaskIntoConstraints = false
        let document = NSView()
        document.addSubview(content)
        content.pinEdges(to: document)
        scroll.documentView = document
        root.addSubview(scroll)
        scroll.pinEdges(to: root)
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildControls()
        observation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshValues() }
        }
        refreshValues()
    }

    private func addSection(_ title: String) {
        let label = makeLabel(title.uppercased(), size: 10, color: .secondaryLabelColor)
        content.addArrangedSubview(label)
    }

    private func addRow(_ title: String, control: NSView) {
        let row = NSStackView(views: [makeLabel(title), NSView(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: 500).isActive = true
        content.addArrangedSubview(row)
    }

    private func addSlider(_ title: String, minimum: Double, maximum: Double, selector: Selector) -> NSSlider {
        let slider = NSSlider(value: minimum, minValue: minimum, maxValue: max(minimum + 1, maximum), target: self, action: selector)
        slider.isContinuous = false
        slider.widthAnchor.constraint(equalToConstant: 250).isActive = true
        let row = NSStackView(views: [makeLabel(title), slider])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        content.addArrangedSubview(row)
        return slider
    }

    private func buildControls() {
        content.addArrangedSubview(makeLabel(model.selectedDevice?.modelCode ?? "Camera Settings", size: 18))
        content.addArrangedSubview(makeButton("Refresh values from camera", target: self, action: #selector(refreshCamera)))
        addSection("Capture")
        resolutionPicker.target = self
        resolutionPicker.action = #selector(resolutionChanged)
        addRow("Resolution", control: resolutionPicker)
        addSection("Exposure and gain")
        exposureModePicker.addItems(withTitles: ["Fixed / Manual", "Auto once", "Auto continuous"])
        exposureModePicker.target = self
        exposureModePicker.action = #selector(exposureModeChanged)
        addRow("Exposure mode", control: exposureModePicker)
        exposureSlider = addSlider("Exposure time (µs)", minimum: 1, maximum: 1_000_000, selector: #selector(exposureChanged))
        content.addArrangedSubview(exposureValue)
        gainSlider = addSlider("Analog gain (%)", minimum: 0, maximum: 100, selector: #selector(gainChanged))
        content.addArrangedSubview(gainValue)
        addSection("White balance")
        temperatureSlider = addSlider("Temperature (K)", minimum: 2000, maximum: 15000, selector: #selector(temperatureChanged))
        content.addArrangedSubview(temperatureValue)
        tintSlider = addSlider("Tint", minimum: 200, maximum: 2500, selector: #selector(tintChanged))
        content.addArrangedSubview(tintValue)
        redField.widthAnchor.constraint(equalToConstant: 55).isActive = true
        greenField.widthAnchor.constraint(equalToConstant: 55).isActive = true
        blueField.widthAnchor.constraint(equalToConstant: 55).isActive = true
        addRow("RGB gain", control: NSStackView(views: [
            redField, greenField, blueField,
            makeButton("Apply", target: self, action: #selector(applyRGB))
        ]))
        addSection("Image")
        colorMatrixButton.target = self
        colorMatrixButton.action = #selector(colorMatrixChanged)
        content.addArrangedSubview(colorMatrixButton)
        pixelFormatPicker.target = self
        pixelFormatPicker.action = #selector(pixelFormatChanged)
        addRow("Pixel format", control: pixelFormatPicker)
        addSection("Frame rate")
        frameRateSlider = addSlider("Fixed FPS", minimum: 1, maximum: 120, selector: #selector(frameRateChanged))
    }

    private func refreshValues() {
        guard let capabilities = model.cameraCapabilities, let controls = model.controls else { return }
        let available = capabilities.availability(of: .resolution).isUsable
        resolutionPicker.isHidden = !available
        resolutionPicker.removeAllItems()
        for resolution in model.selectedDevice?.previewResolutions ?? [] {
            resolutionPicker.addItem(withTitle: "\(resolution.width) × \(resolution.height)")
            resolutionPicker.lastItem?.representedObject = resolution.index
        }
        if let current = model.currentResolution,
           let index = model.selectedDevice?.previewResolutions.firstIndex(where: { $0.index == current.index }) {
            resolutionPicker.selectItem(at: index)
        }

        if let exposure = controls.exposure {
            exposureSlider?.minValue = Double(exposure.minimumMicroseconds ?? 1)
            exposureSlider?.maxValue = Double(max(exposure.minimumMicroseconds ?? 1, exposure.maximumMicroseconds ?? 1_000_000))
            exposureSlider?.doubleValue = Double(exposure.readbackMicroseconds ?? 10_000)
            exposureSlider?.isHidden = !capabilities.availability(of: .exposureManual).isUsable
            exposureValue.stringValue = "Current: \(exposure.readbackMicroseconds ?? 0) µs"
            if let mode = exposure.autoMode {
                exposureModePicker.selectItem(at: mode == .manual ? 0 : (mode == .once ? 1 : 2))
            }
        } else {
            exposureSlider?.isHidden = true
        }
        if let gain = controls.gain {
            gainSlider?.minValue = Double(gain.minimumPercent)
            gainSlider?.maxValue = Double(max(gain.minimumPercent, gain.maximumPercent))
            gainSlider?.doubleValue = Double(gain.readbackPercent)
            gainValue.stringValue = "Current: \(gain.readbackPercent)%"
            gainSlider?.isHidden = !capabilities.availability(of: .analogGain).isUsable
        } else { gainSlider?.isHidden = true }

        if let white = controls.whiteBalance {
            if let temperature = white.temperature {
                temperatureSlider?.doubleValue = Double(temperature)
                temperatureSlider?.isHidden = false
                temperatureValue.stringValue = "Current: \(temperature) K"
            } else { temperatureSlider?.isHidden = true }
            if let tint = white.tint {
                tintSlider?.doubleValue = Double(tint)
                tintSlider?.isHidden = false
                tintValue.stringValue = "Current: \(tint)"
            } else { tintSlider?.isHidden = true }
            if let rgb = white.rgbGain, rgb.count == 3 {
                redField.stringValue = String(rgb[0]); greenField.stringValue = String(rgb[1]); blueField.stringValue = String(rgb[2])
            }
        } else {
            temperatureSlider?.isHidden = true; tintSlider?.isHidden = true
        }

        if let image = controls.image {
            if let enabled = image.colorMatrixEnabled { colorMatrixButton.state = enabled ? .on : .off }
            pixelFormatPicker.removeAllItems()
            for code in image.supportedPixelFormats {
                pixelFormatPicker.addItem(withTitle: AmcamPixelFormatCode(rawValue: code)?.title ?? "Format \(code)")
                pixelFormatPicker.lastItem?.representedObject = code
            }
            if let code = image.pixelFormatCode,
               let index = image.supportedPixelFormats.firstIndex(of: code) {
                pixelFormatPicker.selectItem(at: index)
            }
            pixelFormatPicker.isHidden = !capabilities.availability(of: .pixelFormatSelection).isUsable
            colorMatrixButton.isHidden = image.colorMatrixEnabled == nil
        } else {
            pixelFormatPicker.isHidden = true; colorMatrixButton.isHidden = true
        }

        if let rate = controls.frameRate.readbackFramesPerSecond {
            frameRateSlider?.doubleValue = rate
        }
        frameRateSlider?.isHidden = !capabilities.availability(of: .preciseFrameRate).isUsable
        if let range = controls.frameRate.minimumFramesPerSecond,
           let maximum = controls.frameRate.maximumFramesPerSecond {
            frameRateSlider?.minValue = range
            frameRateSlider?.maxValue = Swift.max(range + 0.1, maximum)
        }
    }

    @objc private func refreshCamera() { model.refreshControls(); refreshValues() }
    @objc private func resolutionChanged() {
        if let index = resolutionPicker.selectedItem?.representedObject as? Int { model.setResolution(index) }
    }
    @objc private func exposureModeChanged() {
        let modes: [AmcamAutoExposureMode] = [.manual, .once, .continuous]
        let index = exposureModePicker.indexOfSelectedItem
        if modes.indices.contains(index) { model.setAutoExposureMode(modes[index]) }
    }
    @objc private func exposureChanged() { model.setExposureTime(UInt32(exposureSlider?.doubleValue ?? 1)) }
    @objc private func gainChanged() { model.setExposureGain(UInt16(gainSlider?.doubleValue ?? 0)) }
    @objc private func temperatureChanged() {
        model.setWhiteBalanceTemperatureTint(temperature: Int32(temperatureSlider?.doubleValue ?? 6503), tint: Int32(tintSlider?.doubleValue ?? 1000))
    }
    @objc private func tintChanged() {
        model.setWhiteBalanceTemperatureTint(temperature: Int32(temperatureSlider?.doubleValue ?? 6503), tint: Int32(tintSlider?.doubleValue ?? 1000))
    }
    @objc private func applyRGB() {
        guard let r = Int32(redField.stringValue), let g = Int32(greenField.stringValue), let b = Int32(blueField.stringValue) else { return }
        model.setWhiteBalanceRGBGain([r, g, b])
    }
    @objc private func colorMatrixChanged() { model.setColorMatrixEnabled(colorMatrixButton.state == .on) }
    @objc private func pixelFormatChanged() {
        if let code = pixelFormatPicker.selectedItem?.representedObject as? Int32 { model.setPixelFormat(code) }
    }
    @objc private func frameRateChanged() { model.setFixedFrameRate(frameRateSlider?.doubleValue ?? 15) }
}
