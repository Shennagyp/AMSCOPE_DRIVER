import AmcamGenTL
import SwiftUI

struct CameraMainView: View {
    @ObservedObject var model: CameraApplicationModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = model.latestImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("AMScope Imaging")
                        .font(.system(size: 24, weight: .medium))
                    Text(model.status)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                    if let error = model.errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 620)
                    }
                    if model.sdkPath == nil {
                        Button("Locate Amcam SDK…") { model.chooseSDK() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .foregroundStyle(.white)
            }

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.selectedDevice?.displayName ?? "No camera selected")
                            .font(.system(size: 13, weight: .semibold))
                        Text(model.selectedDevice?.modelCode ?? model.status)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    if model.isStreaming {
                        Circle().fill(.red).frame(width: 7, height: 7)
                        Text("LIVE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.2)
                        Text(String(format: "%.1f FPS", model.framesPerSecond))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                Spacer()
                CameraHardwareDock(model: model)
                    .padding(.bottom, 20)
            }
            .foregroundStyle(.white)
        }
        .sheet(isPresented: $model.isSettingsPresented) {
            CameraSettingsView(model: model)
                .frame(width: 440, height: 560)
                .preferredColorScheme(.dark)
        }
        .onDisappear { model.shutdown() }
        .alert("Camera error", isPresented: Binding(
            get: { model.errorMessage != nil && model.latestImage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct CameraHardwareDock: View {
    @ObservedObject var model: CameraApplicationModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .foregroundStyle(.white.opacity(0.7))
            Picker("Camera", selection: Binding(
                get: { model.selectedDeviceID },
                set: { model.selectDevice($0) }
            )) {
                if model.devices.isEmpty {
                    Text("No cameras").tag("")
                }
                ForEach(model.devices) { device in
                    Text(device.displayName).tag(device.identifier)
                }
            }
            .labelsHidden()
            .frame(width: 220)
            .disabled(model.isStreaming)

            Button { model.refreshDevices() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh camera list")

            Divider().frame(height: 28)

            Button { model.start() } label: {
                Label("Start", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(model.isStreaming || model.selectedDevice == nil)

            Button { model.stop() } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!model.isStreaming)

            Button("SDK…") { model.chooseSDK() }
                .buttonStyle(.bordered)
                .help("Select the vendor Amcam SDK")

            Button {
                model.refreshControls()
                model.isSettingsPresented = true
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .disabled(model.cameraCapabilities == nil)

            Button { model.toggleFullScreen() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Toggle full screen")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CameraSettingsView: View {
    @ObservedObject var model: CameraApplicationModel
    @State private var exposureDraft = 10_000.0
    @State private var gainDraft = 100.0
    @State private var temperatureDraft = 6_503.0
    @State private var tintDraft = 1_000.0
    @State private var redGainDraft = "100"
    @State private var greenGainDraft = "100"
    @State private var blueGainDraft = "100"
    @State private var frameRateDraft = 15.0

    private var capabilities: AmcamCameraCapabilities? { model.cameraCapabilities }
    private var controls: AmcamControlSnapshot? { model.controls }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Camera Settings")
                        .font(.system(size: 20, weight: .semibold))
                    Text(model.selectedDevice?.modelCode ?? "Unknown model")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.refreshControls() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Read current settings from camera")
            }
            .padding(20)

            Divider()

            if let capabilities {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(capabilities.availableGroups) { group in
                            FeatureGroupView(group: group, model: model,
                                             exposureDraft: $exposureDraft,
                                             gainDraft: $gainDraft,
                                             temperatureDraft: $temperatureDraft,
                                             tintDraft: $tintDraft,
                                             redGainDraft: $redGainDraft,
                                             greenGainDraft: $greenGainDraft,
                                             blueGainDraft: $blueGainDraft,
                                             frameRateDraft: $frameRateDraft)
                        }
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("No camera is open")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .onAppear {
            exposureDraft = Double(controls?.exposure?.readbackMicroseconds ?? 10_000)
            gainDraft = Double(controls?.gain?.readbackPercent ?? 100)
            temperatureDraft = Double(controls?.whiteBalance?.temperature ?? 6_503)
            tintDraft = Double(controls?.whiteBalance?.tint ?? 1_000)
            let rgb = controls?.whiteBalance?.rgbGain ?? []
            redGainDraft = String(rgb.indices.contains(0) ? rgb[0] : 100)
            greenGainDraft = String(rgb.indices.contains(1) ? rgb[1] : 100)
            blueGainDraft = String(rgb.indices.contains(2) ? rgb[2] : 100)
            frameRateDraft = controls?.frameRate.readbackFramesPerSecond ?? 15
        }
        .onChange(of: controls?.exposure?.readbackMicroseconds) { value in
            if let value { exposureDraft = Double(value) }
        }
        .onChange(of: controls?.gain?.readbackPercent) { value in
            if let value { gainDraft = Double(value) }
        }
        .onChange(of: controls?.whiteBalance?.temperature) { value in
            if let value { temperatureDraft = Double(value) }
        }
        .onChange(of: controls?.whiteBalance?.tint) { value in
            if let value { tintDraft = Double(value) }
        }
        .onChange(of: controls?.whiteBalance?.rgbGain) { values in
            if let values, values.count == 3 {
                redGainDraft = String(values[0])
                greenGainDraft = String(values[1])
                blueGainDraft = String(values[2])
            }
        }
        .onChange(of: controls?.frameRate.readbackFramesPerSecond) { value in
            if let value { frameRateDraft = value }
        }
    }
}

private struct FeatureGroupView: View {
    let group: AmcamCameraFeatureGroup
    @ObservedObject var model: CameraApplicationModel
    @Binding var exposureDraft: Double
    @Binding var gainDraft: Double
    @Binding var temperatureDraft: Double
    @Binding var tintDraft: Double
    @Binding var redGainDraft: String
    @Binding var greenGainDraft: String
    @Binding var blueGainDraft: String
    @Binding var frameRateDraft: Double

    private var capability: AmcamCameraCapabilities? { model.cameraCapabilities }
    private var controls: AmcamControlSnapshot? { model.controls }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            switch group {
            case .capture:
                resolutionControl
            case .exposureAndGain:
                exposureControls
            case .frameRate:
                frameRateControls
            case .image:
                imageControls
            default:
                ForEach(group.features.filter { capability?.availability(of: $0).available == true }) { feature in
                    let availability = capability?.availability(of: feature)
                    HStack {
                        Text(feature.rawValue)
                            .font(.system(size: 12))
                        Spacer()
                        Text(availability?.implemented == true ? "Available" : "Integration pending")
                            .font(.system(size: 10))
                            .foregroundStyle(availability?.implemented == true ? .green : .secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var resolutionControl: some View {
        if capability?.availability(of: .resolution).isUsable == true,
           let device = model.selectedDevice {
            HStack {
                Text("Live resolution")
                Spacer()
                Picker("Resolution", selection: Binding(
                    get: { model.currentResolution?.index ?? device.previewResolutions.last?.index ?? 0 },
                    set: { model.setResolution($0) }
                )) {
                    ForEach(device.previewResolutions, id: \.index) { resolution in
                        Text("\(resolution.width) × \(resolution.height)").tag(resolution.index)
                    }
                }
                .labelsHidden()
                .disabled(model.isStreaming)
            }
        }
        if capability?.availability(of: .hardwareROI).available == true {
            featureStatus(.hardwareROI)
        }
        if capability?.availability(of: .binningAndSkipping).available == true {
            featureStatus(.binningAndSkipping)
        }
    }

    @ViewBuilder
    private var exposureControls: some View {
        if capability?.availability(of: .exposureAuto).isUsable == true,
           let exposure = controls?.exposure {
            HStack {
                Text("Exposure mode")
                Spacer()
                Picker("Exposure mode", selection: Binding(
                    get: { exposure.autoMode },
                    set: { model.setAutoExposureMode($0) }
                )) {
                    Text("Fixed / Manual").tag(AmcamAutoExposureMode.manual)
                    Text("Auto continuous").tag(AmcamAutoExposureMode.continuous)
                    Text("Auto once").tag(AmcamAutoExposureMode.once)
                }
                .labelsHidden()
                .frame(width: 180)
            }
            if capability?.availability(of: .exposureManual).isUsable == true {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Exposure time")
                        Spacer()
                        Text(String(format: "%.3f ms", exposureDraft / 1000))
                            .monospacedDigit()
                    }
                    Slider(
                        value: $exposureDraft,
                        in: Double(exposure.minimumMicroseconds)...Double(exposure.maximumMicroseconds),
                        onEditingChanged: { editing in
                            if !editing {
                                model.setExposureTime(UInt32(exposureDraft.rounded()))
                            }
                        }
                    )
                    .disabled(exposure.autoMode != .manual)
                    HStack {
                        Text("\(exposure.minimumMicroseconds) µs")
                        Spacer()
                        Text("\(exposure.maximumMicroseconds) µs")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Exposure controls are not confirmed for this camera.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        if capability?.availability(of: .analogGain).isUsable == true,
           let gain = controls?.gain {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Analog gain")
                    Spacer()
                    Text("\(Int(gainDraft.rounded()))%")
                        .monospacedDigit()
                }
                Slider(
                    value: $gainDraft,
                    in: Double(gain.minimumPercent)...Double(gain.maximumPercent),
                    onEditingChanged: { editing in
                        if !editing { model.setExposureGain(UInt16(gainDraft.rounded())) }
                    }
                )
                HStack {
                    Text("\(gain.minimumPercent)%")
                    Spacer()
                    Text("\(gain.maximumPercent)%")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var imageControls: some View {
        if capability?.availability(of: .whiteBalance).isUsable == true,
           let whiteBalance = controls?.whiteBalance {
            if let temperature = whiteBalance.temperature, let tint = whiteBalance.tint {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Color temperature")
                        Spacer()
                        Text("\(Int(temperatureDraft.rounded())) K")
                            .monospacedDigit()
                    }
                    Slider(value: $temperatureDraft, in: 2_000...15_000) { editing in
                        if !editing {
                            model.setWhiteBalanceTemperatureTint(
                                temperature: Int32(temperatureDraft.rounded()),
                                tint: Int32(tintDraft.rounded())
                            )
                        }
                    }
                    HStack {
                        Text("Tint")
                        Spacer()
                        Text("\(Int(tintDraft.rounded()))")
                            .monospacedDigit()
                    }
                    Slider(value: $tintDraft, in: 200...2_500) { editing in
                        if !editing {
                            model.setWhiteBalanceTemperatureTint(
                                temperature: Int32(temperatureDraft.rounded()),
                                tint: Int32(tintDraft.rounded())
                            )
                        }
                    }
                    Text("Current readback: \(temperature) K / \(tint)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            if let rgb = whiteBalance.rgbGain, rgb.count == 3 {
                HStack(spacing: 8) {
                    TextField("R", text: $redGainDraft).frame(width: 64)
                    TextField("G", text: $greenGainDraft).frame(width: 64)
                    TextField("B", text: $blueGainDraft).frame(width: 64)
                    Button("Apply RGB") {
                        if let red = Int32(redGainDraft),
                           let green = Int32(greenGainDraft),
                           let blue = Int32(blueGainDraft) {
                            model.setWhiteBalanceRGBGain([red, green, blue])
                        }
                    }
                    .disabled(Int32(redGainDraft) == nil || Int32(greenGainDraft) == nil || Int32(blueGainDraft) == nil)
                }
                Text("RGB readback: \(rgb[0]), \(rgb[1]), \(rgb[2])")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        ForEach([AmcamCameraFeature.colorCorrection, .imageLevelRange, .blackLevel,
                 .conversionGain, .lowNoiseMode].filter {
            capability?.availability(of: $0).available == true
        }) { feature in
            featureStatus(feature)
        }
    }

    @ViewBuilder
    private var frameRateControls: some View {
        if let frameRate = controls?.frameRate,
           capability?.availability(of: .preciseFrameRate).isUsable == true,
           let minimum = frameRate.minimumFramesPerSecond,
           let maximum = frameRate.maximumFramesPerSecond {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Fixed frame rate")
                    Spacer()
                    Text(String(format: "%.1f FPS", frameRateDraft))
                        .monospacedDigit()
                }
                Slider(value: $frameRateDraft, in: minimum...maximum, step: 0.1) { editing in
                    if !editing { model.setFixedFrameRate(frameRateDraft) }
                }
            }
        }
        if let frameRate = controls?.frameRate,
           capability?.availability(of: .discreteFrameSpeed).isUsable == true,
           let maximum = frameRate.maximumSpeedLevel {
            HStack {
                Text("Sensor speed level")
                Spacer()
                Stepper(
                    "\(frameRate.currentSpeedLevel ?? 0) / \(maximum)",
                    value: Binding(
                        get: { frameRate.currentSpeedLevel ?? 0 },
                        set: { model.setFrameSpeedLevel($0) }
                    ),
                    in: 0...maximum
                )
            }
        }
        if controls?.frameRate.deviceMeasuredFramesPerSecond != nil {
            Text("Measured: \(String(format: "%.2f", controls?.frameRate.deviceMeasuredFramesPerSecond ?? 0)) FPS")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func featureStatus(_ feature: AmcamCameraFeature) -> some View {
        HStack {
            Text(feature.rawValue)
            Spacer()
            Text("Hardware-supported; UI integration pending")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
