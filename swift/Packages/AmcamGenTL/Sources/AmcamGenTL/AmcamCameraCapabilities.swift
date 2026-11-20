import Foundation

/// Camera features exposed by the Amcam SDK wrapper. A feature is not considered
/// usable merely because its C symbol exists: model flags, safe runtime probes,
/// model profile policy, and implementation coverage are evaluated separately.
public enum AmcamCameraFeature: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case liveCapture, resolution
    case exposureAuto, exposureManual, analogGain
    case preciseFrameRate, discreteFrameSpeed
    case hardwareROI, binningAndSkipping, monochromeOutput, frameBuffer, ddrFrameBuffer
    case whiteBalance, colorCorrection, imageLevelRange, blackLevel, ispProcessor
    case triggerSoftware, triggerExternal, triggerSingle, selfTrigger, hardwareEvent
    case focusMotor, autoFocus, astroAutoFocuser
    case thermoelectricCooling, thermoelectricCoolingOnOff, sensorTemperature, coolingFan, heatAntiFog
    case conversionGain, conversionGainHDR, lowNoiseMode, hardwareLevelRange
    case filterWheel, embeddedLightSource, standaloneLightSource, st4Port, pixelFormatSelection
    case cmosSensor, ccdProgressiveSensor, ccdInterlacedSensor, highFullWell, globalShutter, ghoptoSensor
    case usb3, usb3OverUSB2, gigE, fiveGigE, tenGigE, twoPointFiveGigE, cameraLink, coaxPress

    public var id: String { rawValue }

    public var group: AmcamCameraFeatureGroup {
        switch self {
        case .liveCapture, .resolution, .hardwareROI, .binningAndSkipping,
             .monochromeOutput, .pixelFormatSelection, .frameBuffer, .ddrFrameBuffer: return .capture
        case .exposureAuto, .exposureManual, .analogGain: return .exposureAndGain
        case .preciseFrameRate, .discreteFrameSpeed: return .frameRate
        case .whiteBalance, .colorCorrection, .imageLevelRange, .blackLevel,
             .conversionGain, .conversionGainHDR, .lowNoiseMode, .ispProcessor: return .image
        case .triggerSoftware, .triggerExternal, .triggerSingle, .selfTrigger, .hardwareEvent: return .trigger
        case .focusMotor, .autoFocus: return .focus
        case .thermoelectricCooling, .thermoelectricCoolingOnOff, .sensorTemperature, .coolingFan, .heatAntiFog: return .thermal
        case .hardwareLevelRange: return .calibration
        case .filterWheel, .embeddedLightSource, .standaloneLightSource, .st4Port, .astroAutoFocuser: return .accessories
        case .cmosSensor, .ccdProgressiveSensor, .ccdInterlacedSensor, .highFullWell,
             .globalShutter, .ghoptoSensor: return .sensor
        case .usb3, .usb3OverUSB2, .gigE, .fiveGigE, .tenGigE, .twoPointFiveGigE,
             .cameraLink, .coaxPress: return .transport
        }
    }

    public var isInformational: Bool {
        switch self {
        case .cmosSensor, .ccdProgressiveSensor, .ccdInterlacedSensor, .highFullWell,
             .globalShutter, .ghoptoSensor, .usb3, .usb3OverUSB2, .gigE, .fiveGigE,
             .tenGigE, .twoPointFiveGigE, .cameraLink, .coaxPress:
            return true
        default:
            return false
        }
    }
}

public enum AmcamCameraFeatureGroup: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case capture, exposureAndGain, frameRate, image, trigger, focus, thermal, calibration, accessories
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .capture: return "Capture"
        case .exposureAndGain: return "Exposure & Gain"
        case .frameRate: return "Frame Rate"
        case .image: return "Image"
        case .trigger: return "Trigger"
        case .focus: return "Focus"
        case .thermal: return "Cooling & Temperature"
        case .calibration: return "Calibration"
        case .accessories: return "Accessories"
        case .sensor: return "Sensor"
        case .transport: return "Transport"
        }
    }

    public var features: [AmcamCameraFeature] {
        AmcamCameraFeature.allCases.filter { $0.group == self }
    }
}

public enum AmcamFeatureEvidence: String, Codable, Sendable {
    case modelFlag, runtimeProbe, sdkSymbol, modelProfile, implementation
}

public struct AmcamFeatureAvailability: Codable, Equatable, Sendable, Identifiable {
    public let feature: AmcamCameraFeature
    public let available: Bool
    public let implemented: Bool
    public let evidence: AmcamFeatureEvidence?
    public let reason: String?
    public var id: AmcamCameraFeature { feature }
    public var isUsable: Bool { available && implemented }

    public init(feature: AmcamCameraFeature, available: Bool, implemented: Bool,
                evidence: AmcamFeatureEvidence?, reason: String? = nil) {
        self.feature = feature
        self.available = available
        self.implemented = implemented
        self.evidence = evidence
        self.reason = reason
    }
}

/// Explicit per-model allow/deny policy, keyed by the SDK model descriptor name.
/// A profile can narrow hardware capabilities but cannot fabricate them.
public struct AmcamCameraModelProfile: Codable, Equatable, Sendable {
    public let modelCode: String
    public let displayName: String?
    public let allowedFeaturesByGroup: [String: Set<AmcamCameraFeature>]
    public let deniedFeatures: Set<AmcamCameraFeature>

    public var allowedFeatures: Set<AmcamCameraFeature> {
        allowedFeaturesByGroup.values.reduce(into: Set<AmcamCameraFeature>()) { $0.formUnion($1) }
    }

    public init(modelCode: String, displayName: String? = nil,
                allowedFeatures: Set<AmcamCameraFeature>,
                deniedFeatures: Set<AmcamCameraFeature> = []) {
        self.modelCode = modelCode
        self.displayName = displayName
        self.allowedFeaturesByGroup = Dictionary(grouping: allowedFeatures, by: \.group)
            .mapValues(Set.init)
            .reduce(into: [String: Set<AmcamCameraFeature>]()) { result, item in
                result[item.key.rawValue] = item.value
            }
        self.deniedFeatures = deniedFeatures
    }

    public init(modelCode: String, displayName: String? = nil,
                allowedFeaturesByGroup: [AmcamCameraFeatureGroup: Set<AmcamCameraFeature>],
                deniedFeatures: Set<AmcamCameraFeature> = []) {
        self.modelCode = modelCode
        self.displayName = displayName
        self.allowedFeaturesByGroup = Dictionary(
            uniqueKeysWithValues: allowedFeaturesByGroup.map { ($0.key.rawValue, $0.value) }
        )
        self.deniedFeatures = deniedFeatures
    }

    public init(modelCode: String, displayName: String? = nil,
                allowedFeaturesByGroup: [String: Set<AmcamCameraFeature>],
                deniedFeatures: Set<AmcamCameraFeature> = []) {
        self.modelCode = modelCode
        self.displayName = displayName
        self.allowedFeaturesByGroup = allowedFeaturesByGroup
        self.deniedFeatures = deniedFeatures
    }
}

public struct AmcamCameraCapabilities: Equatable, Sendable {
    public let modelCode: String
    public let modelFlags: UInt64
    public let features: [AmcamFeatureAvailability]

    public init(modelCode: String, modelFlags: UInt64, features: [AmcamFeatureAvailability]) {
        self.modelCode = modelCode
        self.modelFlags = modelFlags
        self.features = features
    }

    public func availability(of feature: AmcamCameraFeature) -> AmcamFeatureAvailability {
        features.first { $0.feature == feature } ?? AmcamFeatureAvailability(
            feature: feature, available: false, implemented: false,
            evidence: nil, reason: "No capability record exists for this feature."
        )
    }

    public var availableGroups: [AmcamCameraFeatureGroup] {
        AmcamCameraFeatureGroup.allCases.filter { group in
            group.features.contains { availability(of: $0).available }
        }
    }
}

/// Resolves the SDK model flags, non-mutating runtime probes, model-specific
/// policy, and application implementation coverage into one capability view.
/// Features without a dedicated model flag require a successful runtime probe.
public struct AmcamCameraProfileRegistry: Sendable {
    public typealias ProbeResults = [AmcamCameraFeature: Bool]
    private let profiles: [String: AmcamCameraModelProfile]

    public init(profiles: [AmcamCameraModelProfile] = []) {
        self.profiles = Dictionary(
            profiles.map { ($0.modelCode.trimmingCharacters(in: .whitespacesAndNewlines), $0) },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    public func profile(for modelCode: String) -> AmcamCameraModelProfile? {
        profiles[modelCode.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    public func resolve(
        modelCode: String, modelFlags: UInt64, maximumSpeedLevel: Int?,
        probes: ProbeResults, implemented: Set<AmcamCameraFeature>
    ) -> AmcamCameraCapabilities {
        let profile = profile(for: modelCode)
        let records = AmcamCameraFeature.allCases.map { feature -> AmcamFeatureAvailability in
            let flag = Self.requiredFlag(for: feature)
            let probe = probes[feature]
            let baseAvailable: Bool
            let evidence: AmcamFeatureEvidence?
            let reason: String?

            if let flag {
                let advertised = (modelFlags & flag) != 0
                let probeRequired = feature == .preciseFrameRate
                baseAvailable = advertised && (!probeRequired || probe == true) && probe != false
                evidence = probeRequired && probe == true ? .runtimeProbe : .modelFlag
                reason = baseAvailable ? nil : (advertised
                    ? "The model advertises this capability, but the runtime SDK probe did not confirm it."
                    : "The camera model does not advertise this capability.")
            } else if feature == .resolution {
                baseAvailable = probe == true
                evidence = .runtimeProbe
                reason = baseAvailable ? nil : "The camera does not expose a usable preview resolution configuration."
            } else if feature == .liveCapture {
                baseAvailable = true
                evidence = .implementation
                reason = nil
            } else if feature == .discreteFrameSpeed {
                baseAvailable = maximumSpeedLevel.map { $0 >= 0 } == true && probe == true
                evidence = .runtimeProbe
                reason = baseAvailable ? nil : "The model does not expose a usable discrete speed-level range."
            } else {
                baseAvailable = probe == true
                evidence = probe == nil ? nil : .runtimeProbe
                reason = baseAvailable ? nil : "The feature was not confirmed by a successful read-only SDK probe."
            }

            let profileAllows = profile.map { $0.allowedFeatures.contains(feature) } ?? true
            let profileDenies = profile?.deniedFeatures.contains(feature) ?? false
            let available = baseAvailable && profileAllows && !profileDenies
            let policyReason: String?
            if profileDenies {
                policyReason = "Disabled by the explicit model profile."
            } else if !profileAllows {
                policyReason = "Not included in the explicit model profile allow-list."
            } else {
                policyReason = reason
            }
            let isImplemented = implemented.contains(feature) || feature.isInformational
            return AmcamFeatureAvailability(
                feature: feature, available: available, implemented: isImplemented,
                evidence: evidence ?? (isImplemented ? .implementation : nil),
                reason: !isImplemented
                    ? "The application backend does not implement this control yet."
                    : policyReason
            )
        }
        return AmcamCameraCapabilities(modelCode: modelCode, modelFlags: modelFlags, features: records)
    }

    private static func requiredFlag(for feature: AmcamCameraFeature) -> UInt64? {
        switch feature {
        case .cmosSensor: return 0x00000001
        case .ccdProgressiveSensor: return 0x00000002
        case .ccdInterlacedSensor: return 0x00000004
        case .hardwareROI: return 0x00000008
        case .monochromeOutput: return 0x00000010
        case .binningAndSkipping: return 0x00000020
        case .thermoelectricCooling: return 0x00000080
        case .thermoelectricCoolingOnOff: return 0x00020000
        case .st4Port: return 0x00000200
        case .sensorTemperature: return 0x00000400
        case .highFullWell: return 0x00000800
        case .coolingFan: return 0x00010000
        case .ispProcessor: return 0x00040000
        case .triggerSoftware: return 0x00080000
        case .triggerExternal: return 0x00100000
        case .triggerSingle: return 0x00200000
        case .blackLevel: return 0x00400000
        case .autoFocus: return 0x00800000
        case .frameBuffer: return 0x01000000
        case .ddrFrameBuffer: return 0x02000000
        case .conversionGain: return 0x04000000
        case .preciseFrameRate: return 0x0000004000000000
        case .focusMotor: return 0x0000002000000000
        case .heatAntiFog: return 0x0000008000000000
        case .lowNoiseMode: return 0x0000010000000000
        case .hardwareLevelRange: return 0x0000020000000000
        case .hardwareEvent: return 0x0000040000000000
        case .embeddedLightSource: return 0x0000080000000000
        case .filterWheel: return 0x0000100000000000
        case .astroAutoFocuser: return 0x0002000000000000
        case .standaloneLightSource: return 0x0004000000000000
        case .cameraLink: return 0x0008000000000000
        case .coaxPress: return 0x0010000000000000
        case .selfTrigger: return 0x0040000000000000
        case .ghoptoSensor: return 0x0100000000000000
        case .usb3: return 0x00000040
        case .usb3OverUSB2: return 0x00000100
        case .gigE: return 0x0000200000000000
        case .tenGigE: return 0x0000400000000000
        case .fiveGigE: return 0x0000800000000000
        case .twoPointFiveGigE: return 0x0001000000000000
        case .exposureAuto, .exposureManual, .analogGain, .resolution, .liveCapture,
             .discreteFrameSpeed, .whiteBalance, .colorCorrection, .imageLevelRange,
             .pixelFormatSelection: return nil
        }
    }
}
