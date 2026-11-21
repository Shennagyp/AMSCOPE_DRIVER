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
    private var frameObservation: AnyCancellable?
    private var pendingFrameUpdate: FramePresentationUpdate?
    private var frameRenderScheduled = false
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
        frameObservation = model.framePresentationPublisher.sink { [weak self] update in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingFrameUpdate = update
                guard !self.frameRenderScheduled else { return }
                self.frameRenderScheduled = true
                DispatchQueue.main.async { [weak self] in
                    self?.renderPendingFrame()
                }
            }
        }
        render()
    }

    private func renderPendingFrame() {
        frameRenderScheduled = false
        guard let update = pendingFrameUpdate else { return }
        pendingFrameUpdate = nil

        preview.image = update.frame.flatMap { makePreviewImage(from: $0) }
        liveLabel.stringValue = model.isStreaming
            ? String(format: "● LIVE   %.1f FPS", update.framesPerSecond)
            : ""
    }

    private func render() {
        titleLabel.stringValue = model.selectedDevice?.displayName ?? "No camera selected"
        detailLabel.stringValue = model.selectedDevice?.modelCode ?? model.status
        statusLabel.stringValue = model.status
        errorLabel.stringValue = model.errorMessage ?? ""
        liveLabel.stringValue = model.isStreaming
            ? String(format: "● LIVE   %.1f FPS", model.framesPerSecond)
            : ""
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
    private var speedLevelSlider: NSSlider?
    private var exposureValue = NSTextField(labelWithString: "")
    private var gainValue = NSTextField(labelWithString: "")
    private var speedLevelValue = NSTextField(labelWithString: "")
    private var temperatureValue = NSTextField(labelWithString: "")
    private var tintValue = NSTextField(labelWithString: "")
    private var redField = NSTextField(string: "100")
    private var greenField = NSTextField(string: "100")
    private var blueField = NSTextField(string: "100")
    private var resolutionPicker = NSPopUpButton()
    private var rgbGainRow: NSView?
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

    @discardableResult
    private func addRow(_ title: String, control: NSView) -> NSView {
        let row = NSStackView(views: [makeLabel(title), NSView(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: 500).isActive = true
        content.addArrangedSubview(row)
        return row
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
        rgbGainRow = addRow("RGB gain", control: NSStackView(views: [
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
        speedLevelSlider = addSlider("Frame speed level", minimum: 0, maximum: 1, selector: #selector(speedLevelChanged))
        content.addArrangedSubview(speedLevelValue)
    }

    private func refreshValues() {
        // A settings window may outlive camera selection. Hide every editable
        // control first so nil/new-device state can never retain stale controls.
        resolutionPicker.isHidden = true
        exposureModePicker.isHidden = true
        exposureSlider?.isHidden = true
        exposureValue.isHidden = true
        gainSlider?.isHidden = true
        gainValue.isHidden = true
        temperatureSlider?.isHidden = true
        temperatureValue.isHidden = true
        tintSlider?.isHidden = true
        tintValue.isHidden = true
        rgbGainRow?.isHidden = true
        colorMatrixButton.isHidden = true
        pixelFormatPicker.isHidden = true
        frameRateSlider?.isHidden = true
        speedLevelSlider?.isHidden = true
        speedLevelValue.isHidden = true

        guard let capabilities = model.cameraCapabilities,
              let controls = model.controls else { return }

        let resolutionIsWritable = capabilities.availability(of: .resolution).isUsable
            && model.isFeatureWritable("AmcamResolutionIndex")
        let resolutions = model.selectedDevice?.previewResolutions ?? []
        resolutionPicker.removeAllItems()
        for resolution in resolutions {
            resolutionPicker.addItem(withTitle: "\(resolution.width) × \(resolution.height)")
            resolutionPicker.lastItem?.representedObject = resolution.index
        }
        if let current = model.currentResolution,
           let index = resolutions.firstIndex(where: { $0.index == current.index }) {
            resolutionPicker.selectItem(at: index)
        }
        resolutionPicker.isHidden = !resolutionIsWritable || resolutions.isEmpty

        if let exposure = controls.exposure {
            if let readback = exposure.readbackMicroseconds {
                exposureValue.stringValue = "Current: \(readback) µs"
                exposureValue.isHidden = false
            }
            let exposureRange = model.numericRange(for: "ExposureTime")
            let canWriteExposure = capabilities.availability(of: .exposureManual).isUsable
                && model.isFeatureWritable("ExposureTime")
                && exposureRange.map { $0.maximum > $0.minimum } == true
            if let exposureRange, canWriteExposure {
                exposureSlider?.minValue = exposureRange.minimum
                exposureSlider?.maxValue = exposureRange.maximum
                exposureSlider?.doubleValue = Double(exposure.readbackMicroseconds ?? 10_000)
            }
            exposureSlider?.isHidden = !canWriteExposure
            exposureSlider?.isEnabled = exposure.autoMode == .manual

            let supportedAutoModes = model.enumerationValues(for: "ExposureAuto")
            let modeItems: [(symbol: String, title: String)] = [
                ("Off", "Fixed / Manual"),
                ("Once", "Auto once"),
                ("Continuous", "Auto continuous")
            ].filter { supportedAutoModes.contains($0.symbol) }
            exposureModePicker.removeAllItems()
            for item in modeItems {
                exposureModePicker.addItem(withTitle: item.title)
                exposureModePicker.lastItem?.representedObject = item.symbol
            }
            if let mode = exposure.autoMode {
                let symbol = mode == .manual ? "Off" : (mode == .once ? "Once" : "Continuous")
                if let index = modeItems.firstIndex(where: { $0.symbol == symbol }) {
                    exposureModePicker.selectItem(at: index)
                }
            }
            let canWriteAutoMode = capabilities.availability(of: .exposureAuto).isUsable
                && model.isFeatureWritable("ExposureAuto")
            exposureModePicker.isHidden = !canWriteAutoMode || modeItems.isEmpty
        }

        if let gain = controls.gain {
            gainValue.stringValue = "Current: \(gain.readbackPercent)%"
            let canWriteGain = capabilities.availability(of: .analogGain).isUsable
                && model.isFeatureWritable("AmcamAnalogGainPercent")
                && gain.minimumPercent < gain.maximumPercent
                && model.numericRange(for: "AmcamAnalogGainPercent") != nil
            if canWriteGain {
                gainSlider?.minValue = Double(gain.minimumPercent)
                gainSlider?.maxValue = Double(gain.maximumPercent)
                gainSlider?.doubleValue = Double(gain.readbackPercent)
            }
            gainSlider?.isHidden = !canWriteGain
            gainValue.isHidden = false
        }

        if let white = controls.whiteBalance {
            if let temperature = white.temperature {
                temperatureSlider?.doubleValue = Double(temperature)
                let temperatureRange = model.numericRange(for: "AmcamWhiteBalanceTemperature")
                if let temperatureRange, temperatureRange.maximum > temperatureRange.minimum {
                    temperatureSlider?.minValue = temperatureRange.minimum
                    temperatureSlider?.maxValue = temperatureRange.maximum
                }
                temperatureSlider?.isHidden = !capabilities.availability(of: .whiteBalance).isUsable
                    || !model.isFeatureWritable("AmcamWhiteBalanceTemperature")
                    || temperatureRange.map { $0.maximum > $0.minimum } != true
                temperatureValue.stringValue = "Current: \(temperature) K"
                temperatureValue.isHidden = false
            }
            if let tint = white.tint {
                tintSlider?.doubleValue = Double(tint)
                let tintRange = model.numericRange(for: "AmcamWhiteBalanceTint")
                if let tintRange, tintRange.maximum > tintRange.minimum {
                    tintSlider?.minValue = tintRange.minimum
                    tintSlider?.maxValue = tintRange.maximum
                }
                tintSlider?.isHidden = !capabilities.availability(of: .whiteBalance).isUsable
                    || !model.isFeatureWritable("AmcamWhiteBalanceTint")
                    || tintRange.map { $0.maximum > $0.minimum } != true
                tintValue.stringValue = "Current: \(tint)"
                tintValue.isHidden = false
            }
            if let rgb = white.rgbGain, rgb.count == 3 {
                redField.stringValue = String(rgb[0])
                greenField.stringValue = String(rgb[1])
                blueField.stringValue = String(rgb[2])
                rgbGainRow?.isHidden = !capabilities.availability(of: .whiteBalance).isUsable
                    || !model.isFeatureWritable("AmcamWhiteBalanceRGBGain")
            }
        }

        if let image = controls.image {
            if let enabled = image.colorMatrixEnabled {
                colorMatrixButton.state = enabled ? .on : .off
                colorMatrixButton.isHidden = !capabilities.availability(of: .colorCorrection).isUsable
                    || !model.isFeatureWritable("AmcamColorMatrixEnabled")
            }
            pixelFormatPicker.removeAllItems()
            for code in image.supportedPixelFormats {
                pixelFormatPicker.addItem(withTitle: AmcamPixelFormatCode(rawValue: code)?.title ?? "Format \(code)")
                pixelFormatPicker.lastItem?.representedObject = code
            }
            if let code = image.pixelFormatCode,
               let index = image.supportedPixelFormats.firstIndex(of: code) {
                pixelFormatPicker.selectItem(at: index)
            }
            let canWritePixelFormat = capabilities.availability(of: .pixelFormatSelection).isUsable
                && model.isFeatureWritable("AmcamPixelFormat")
            pixelFormatPicker.isHidden = !canWritePixelFormat || image.supportedPixelFormats.isEmpty
        }

        if let rate = controls.frameRate.readbackFramesPerSecond {
            frameRateSlider?.doubleValue = rate
        }
        let frameRateRange = model.numericRange(for: "AmcamFixedFrameRate")
        let canWriteFrameRate = capabilities.availability(of: .preciseFrameRate).isUsable
            && model.isFeatureWritable("AmcamFixedFrameRate")
            && frameRateRange.map { $0.maximum > $0.minimum } == true
        frameRateSlider?.isHidden = !canWriteFrameRate
        if canWriteFrameRate, let frameRateRange {
            frameRateSlider?.minValue = frameRateRange.minimum
            frameRateSlider?.maxValue = frameRateRange.maximum
        }

        // Fixed FPS and discrete speed are alternative SDK control modes;
        // prefer precise FPS when it is writable, otherwise expose the level control.
        if !canWriteFrameRate,
           controls.frameRate.speedLevelSupported,
           let currentLevel = controls.frameRate.currentSpeedLevel,
           let speedRange = model.numericRange(for: "AmcamFrameSpeedLevel"),
           capabilities.availability(of: .discreteFrameSpeed).isUsable,
           model.isFeatureWritable("AmcamFrameSpeedLevel") {
            speedLevelValue.stringValue = "Current speed level: \(currentLevel)"
            speedLevelValue.isHidden = false
            if speedRange.maximum > speedRange.minimum {
                speedLevelSlider?.minValue = speedRange.minimum
                speedLevelSlider?.maxValue = speedRange.maximum
                speedLevelSlider?.doubleValue = Double(currentLevel)
                speedLevelSlider?.isHidden = false
            }
        }
    }

    @objc private func refreshCamera() { model.refreshControls(); refreshValues() }
    @objc private func resolutionChanged() {
        if let index = resolutionPicker.selectedItem?.representedObject as? Int { model.setResolution(index) }
    }
    @objc private func exposureModeChanged() {
        guard let symbol = exposureModePicker.selectedItem?.representedObject as? String else { return }
        switch symbol {
        case "Off": model.setAutoExposureMode(.manual)
        case "Once": model.setAutoExposureMode(.once)
        case "Continuous": model.setAutoExposureMode(.continuous)
        default: return
        }
    }
    @objc private func exposureChanged() {
        guard let rawValue = exposureSlider?.doubleValue,
              let value = model.normalizedNumericValue(rawValue, for: "ExposureTime"),
              value >= 0, value <= Double(UInt32.max) else { return }
        exposureSlider?.doubleValue = value
        model.setExposureTime(UInt32(value.rounded(.towardZero)))
    }
    @objc private func gainChanged() {
        guard let rawValue = gainSlider?.doubleValue,
              let value = model.normalizedNumericValue(rawValue, for: "AmcamAnalogGainPercent"),
              value >= 0, value <= Double(UInt16.max) else { return }
        gainSlider?.doubleValue = value
        model.setExposureGain(UInt16(value.rounded(.towardZero)))
    }
    @objc private func temperatureChanged() {
        guard let rawValue = temperatureSlider?.doubleValue,
              let value = model.normalizedNumericValue(rawValue, for: "AmcamWhiteBalanceTemperature"),
              value >= Double(Int32.min), value <= Double(Int32.max) else { return }
        temperatureSlider?.doubleValue = value
        model.setWhiteBalanceTemperature(Int32(value.rounded(.towardZero)))
    }
    @objc private func tintChanged() {
        guard let rawValue = tintSlider?.doubleValue,
              let value = model.normalizedNumericValue(rawValue, for: "AmcamWhiteBalanceTint"),
              value >= Double(Int32.min), value <= Double(Int32.max) else { return }
        tintSlider?.doubleValue = value
        model.setWhiteBalanceTint(Int32(value.rounded(.towardZero)))
    }
    @objc private func applyRGB() {
        guard let r = Int32(redField.stringValue), let g = Int32(greenField.stringValue), let b = Int32(blueField.stringValue) else { return }
        model.setWhiteBalanceRGBGain([r, g, b])
    }
    @objc private func colorMatrixChanged() { model.setColorMatrixEnabled(colorMatrixButton.state == .on) }
    @objc private func pixelFormatChanged() {
        if let code = pixelFormatPicker.selectedItem?.representedObject as? Int32 { model.setPixelFormat(code) }
    }
    @objc private func frameRateChanged() {
        guard let rawValue = frameRateSlider?.doubleValue,
              let value = model.normalizedNumericValue(rawValue, for: "AmcamFixedFrameRate") else { return }
        frameRateSlider?.doubleValue = value
        model.setFixedFrameRate(value)
    }
    @objc private func speedLevelChanged() {
        guard let rawValue = speedLevelSlider?.doubleValue,
              let value = model.normalizedNumericValue(rawValue, for: "AmcamFrameSpeedLevel") else { return }
        speedLevelSlider?.doubleValue = value
        model.setFrameSpeedLevel(Int(value.rounded(.towardZero)))
    }
}
