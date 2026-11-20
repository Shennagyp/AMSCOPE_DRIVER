import AmcamCameraModel
import AmcamImagingRuntime
import Foundation

/// Converts backend-neutral camera observations into AmScope application state.
/// It has no AppKit, GenTL, vendor SDK, or device-lifecycle ownership.
public struct AmcamCameraStateResolver: Sendable {
    public typealias FeatureReader = @Sendable (String) async throws -> CameraFeatureValue

    private let profileRegistry: AmcamCameraProfileRegistry

    public init(profileRegistry: AmcamCameraProfileRegistry = AmcamCameraProfileRegistry()) {
        self.profileRegistry = profileRegistry
    }

    public func capabilities(
        for device: AmcamDevice?,
        descriptors: [CameraFeatureDescriptor],
        hasDataStream: Bool
    ) -> AmcamCameraCapabilities? {
        guard let device else { return nil }
        let availabilityByName = Dictionary(
            descriptors.map { ($0.name, $0.isAvailable) },
            uniquingKeysWith: { _, latest in latest }
        )
        let maximumSpeedLevel = descriptors.last(where: { $0.name == "AmcamFrameSpeedLevel" })?
            .numericRange.flatMap { Int(exactly: $0.maximum) }
        return profileRegistry.resolveRuntime(
            device: device,
            featureAvailabilityByName: availabilityByName,
            hasDataStream: hasDataStream,
            maximumSpeedLevel: maximumSpeedLevel
        )
    }


    public func validateWrite(
        _ value: CameraFeatureValue,
        named name: String,
        descriptors: [CameraFeatureDescriptor]
    ) -> CameraFeatureAccessError? {
        guard let descriptor = descriptors.last(where: { $0.name == name }) else {
            return .featureNotFound(name)
        }
        guard descriptor.isAvailable else {
            return .featureUnavailable(name)
        }
        guard descriptor.isWritable else {
            return .featureNotWritable(name)
        }
        guard descriptor.kind == value.kind else {
            return .valueTypeMismatch(
                feature: name,
                expected: descriptor.kind,
                actual: value.kind
            )
        }

        switch value {
        case .integer(let number):
            if let range = descriptor.numericRange,
               !isWithinRange(Double(number), range: range) {
                return .invalidValue(rangeValidationMessage(name, range: range))
            }
        case .floatingPoint(let number):
            guard number.isFinite else {
                return .invalidValue("\(name) must be a finite number.")
            }
            if let range = descriptor.numericRange,
               !isWithinRange(number, range: range) {
                return .invalidValue(rangeValidationMessage(name, range: range))
            }
        case .integerVector(let values):
            guard let expectedCount = descriptor.elementCount else {
                return .invalidValue("\(name) does not declare its vector element count.")
            }
            if values.count != expectedCount {
                return .invalidValue(
                    "\(name) requires exactly \(expectedCount) vector elements."
                )
            }
        case .enumeration(let symbol):
            if !descriptor.enumerationValues.isEmpty,
               !descriptor.enumerationValues.contains(symbol) {
                return .invalidValue(
                    "\(symbol) is not an advertised value for \(name)."
                )
            }
        case .boolean, .string:
            break
        }
        return nil
    }

    private func rangeValidationMessage(
        _ name: String,
        range: CameraFeatureNumericRange
    ) -> String {
        if let increment = range.increment {
            return "\(name) must be between \(range.minimum) and \(range.maximum) in increments of \(increment)."
        }
        return "\(name) must be between \(range.minimum) and \(range.maximum)."
    }

    private func isWithinRange(_ value: Double, range: CameraFeatureNumericRange) -> Bool {
        guard value.isFinite,
              value >= range.minimum,
              value <= range.maximum else {
            return false
        }
        guard let increment = range.increment else { return true }
        let steps = (value - range.minimum) / increment
        let nearestStep = steps.rounded()
        let tolerance = max(1e-9, abs(steps) * 1e-9)
        return abs(steps - nearestStep) <= tolerance
    }

    public func capabilityFeature(for name: String) -> AmcamCameraFeature? {
        switch name {
        case "ExposureAuto": return .exposureAuto
        case "ExposureTime": return .exposureManual
        case "AmcamAnalogGainPercent": return .analogGain
        case "AmcamColorMatrixEnabled": return .colorCorrection
        case "AmcamPixelFormat": return .pixelFormatSelection
        case "AmcamWhiteBalanceTemperature", "AmcamWhiteBalanceTint", "AmcamWhiteBalanceRGBGain":
            return .whiteBalance
        case "AmcamFixedFrameRate": return .preciseFrameRate
        case "AmcamFrameSpeedLevel": return .discreteFrameSpeed
        case "AmcamResolutionIndex": return .resolution
        default: return nil
        }
    }

    public func resolutions(from descriptors: [CameraFeatureDescriptor]) -> [AmcamResolution] {
        let resolutionDescriptor = descriptors.last(where: { $0.name == "AmcamResolutionIndex" })
        guard resolutionDescriptor?.isAvailable == true else { return [] }
        let options = resolutionDescriptor?.enumerationValues ?? []
        return options.compactMap { symbol -> AmcamResolution? in
            guard let separator = symbol.firstIndex(of: ":"),
                  let resolutionSeparator = symbol[symbol.index(after: separator)...].firstIndex(of: "x"),
                  let index = Int(symbol[..<separator]),
                  let width = Int(symbol[symbol.index(after: separator)..<resolutionSeparator]),
                  let height = Int(symbol[symbol.index(after: resolutionSeparator)...]) else {
                return nil
            }
            return AmcamResolution(index: index, width: width, height: height)
        }
    }

    public func currentResolution(
        for device: AmcamDevice?,
        descriptors: [CameraFeatureDescriptor],
        readFeature: FeatureReader
    ) async -> AmcamResolution? {
        guard let device,
              let descriptor = descriptors.last(where: { $0.name == "AmcamResolutionIndex" }),
              descriptor.isAvailable,
              descriptor.isReadable,
              case .enumeration(let symbol)? = try? await readFeature("AmcamResolutionIndex"),
              let separator = symbol.firstIndex(of: ":"),
              let index = Int(symbol[..<separator]) else {
            return nil
        }
        return device.previewResolutions.first { $0.index == index }
    }

    public func controlSnapshot(
        descriptors: [CameraFeatureDescriptor],
        readFeature: FeatureReader
    ) async -> AmcamControlSnapshot {
        // The latest descriptor for a name is authoritative. An older duplicate
        // must not re-enable a feature that the current descriptor disables.
        let latestDescriptorByName = Dictionary(
            descriptors.map { ($0.name, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let descriptorsByName = Dictionary(
            latestDescriptorByName.filter { $0.value.isAvailable },
            uniquingKeysWith: { _, latest in latest }
        )
        let readableFeatureNames = Set(
            latestDescriptorByName.values
                .filter { $0.isAvailable && $0.isReadable }
                .map { $0.name }
        )
        let safeReadFeature: FeatureReader = { name in
            guard readableFeatureNames.contains(name) else {
                throw CameraFeatureAccessError.featureUnavailable(name)
            }
            return try await readFeature(name)
        }

        let autoMode: AmcamAutoExposureMode?
        if case .enumeration(let symbol)? = try? await safeReadFeature("ExposureAuto") {
            switch symbol {
            case "Off": autoMode = .manual
            case "Once": autoMode = .once
            case "Continuous": autoMode = .continuous
            default: autoMode = nil
            }
        } else {
            autoMode = nil
        }

        let exposureDescriptor = descriptorsByName["ExposureTime"]
        let exposureValue = await readIntegerFeature("ExposureTime", readFeature: safeReadFeature)
        let exposure = exposureDescriptor.map { descriptor in
            AmcamExposureControl(
                autoMode: autoMode,
                readbackMicroseconds: unsigned32(exposureValue),
                minimumMicroseconds: unsigned32(descriptor.numericRange?.minimum),
                maximumMicroseconds: unsigned32(descriptor.numericRange?.maximum),
                defaultMicroseconds: nil
            )
        }

        let gainDescriptor = descriptorsByName["AmcamAnalogGainPercent"]
        let gainValue = await readIntegerFeature("AmcamAnalogGainPercent", readFeature: safeReadFeature)
        let gain: AmcamGainControl?
        if let gainDescriptor,
           let current = unsigned16(gainValue),
           let minimum = unsigned16(gainDescriptor.numericRange?.minimum),
           let maximum = unsigned16(gainDescriptor.numericRange?.maximum) {
            gain = AmcamGainControl(
                readbackPercent: current,
                minimumPercent: minimum,
                maximumPercent: maximum,
                defaultPercent: minimum
            )
        } else {
            gain = nil
        }

        let whiteTemperature = await readIntegerFeature(
            "AmcamWhiteBalanceTemperature", readFeature: safeReadFeature
        ).flatMap { $0 >= Int64(Int32.min) && $0 <= Int64(Int32.max) ? Int32($0) : nil }
        let whiteTint = await readIntegerFeature(
            "AmcamWhiteBalanceTint", readFeature: safeReadFeature
        ).flatMap { $0 >= Int64(Int32.min) && $0 <= Int64(Int32.max) ? Int32($0) : nil }
        let whiteRGB = await readIntegerVectorFeature(
            "AmcamWhiteBalanceRGBGain", readFeature: safeReadFeature
        ).flatMap { values -> [Int32]? in
            guard values.count == 3 else { return nil }
            let converted = values.compactMap { Int32(exactly: $0) }
            return converted.count == 3 ? converted : nil
        }
        let whiteBalance = (whiteTemperature != nil || whiteTint != nil || whiteRGB != nil)
            ? AmcamWhiteBalanceControl(
                temperature: whiteTemperature,
                tint: whiteTint,
                rgbGain: whiteRGB
            )
            : nil

        let colorMatrix: Bool?
        if case .boolean(let value)? = try? await safeReadFeature("AmcamColorMatrixEnabled") {
            colorMatrix = value
        } else {
            colorMatrix = nil
        }
        let pixelFormat = await readEnumerationFeature(
            "AmcamPixelFormat", readFeature: safeReadFeature
        ).flatMap(Int32.init)
        let supportedPixelFormats = descriptorsByName["AmcamPixelFormat"]?
            .enumerationValues.compactMap(Int32.init) ?? []
        let image = (colorMatrix != nil || pixelFormat != nil || !supportedPixelFormats.isEmpty)
            ? AmcamCameraImageControls(
                colorMatrixEnabled: colorMatrix,
                pixelFormatCode: pixelFormat,
                supportedPixelFormats: supportedPixelFormats
            )
            : nil

        let fixedRateDescriptor = descriptorsByName["AmcamFixedFrameRate"]
        let speedDescriptor = descriptorsByName["AmcamFrameSpeedLevel"]
        let fixedRateReadback = await readFloatingPointFeature(
            "AmcamFixedFrameRate", readFeature: safeReadFeature
        )
        let currentSpeed = await readIntegerFeature(
            "AmcamFrameSpeedLevel", readFeature: safeReadFeature
        ).flatMap(Int.init(exactly:))
        let frameRate = AmcamFrameRateControl(
            supported: fixedRateDescriptor?.isAvailable == true,
            minimumFramesPerSecond: fixedRateDescriptor?.numericRange?.minimum,
            maximumFramesPerSecond: fixedRateDescriptor?.numericRange?.maximum,
            readbackFramesPerSecond: fixedRateReadback,
            unsupportedReason: fixedRateDescriptor?.isAvailable == true
                ? nil
                : "Precise fixed frame rate is not available for this camera.",
            speedLevelSupported: speedDescriptor?.isAvailable == true,
            currentSpeedLevel: currentSpeed,
            maximumSpeedLevel: speedDescriptor?.numericRange.flatMap { Int(exactly: $0.maximum) }
        )

        return AmcamControlSnapshot(
            exposure: exposure,
            gain: gain,
            whiteBalance: whiteBalance,
            image: image,
            frameRate: frameRate
        )
    }

    private func readIntegerFeature(_ name: String, readFeature: FeatureReader) async -> Int64? {
        guard case .integer(let value)? = try? await readFeature(name) else { return nil }
        return value
    }

    private func readIntegerVectorFeature(_ name: String, readFeature: FeatureReader) async -> [Int64]? {
        guard case .integerVector(let values)? = try? await readFeature(name) else { return nil }
        return values
    }

    private func readEnumerationFeature(_ name: String, readFeature: FeatureReader) async -> String? {
        guard case .enumeration(let value)? = try? await readFeature(name) else { return nil }
        return value
    }

    private func readFloatingPointFeature(_ name: String, readFeature: FeatureReader) async -> Double? {
        guard case .floatingPoint(let value)? = try? await readFeature(name), value.isFinite else {
            return nil
        }
        return value
    }

    private func unsigned32(_ value: Int64?) -> UInt32? {
        guard let value, value >= 0, value <= Int64(UInt32.max) else { return nil }
        return UInt32(value)
    }

    private func unsigned32(_ value: Double?) -> UInt32? {
        guard let value, value.isFinite, value >= 0, value <= Double(UInt32.max) else { return nil }
        return UInt32(value.rounded(.towardZero))
    }

    private func unsigned16(_ value: Int64?) -> UInt16? {
        guard let value, value >= 0, value <= Int64(UInt16.max) else { return nil }
        return UInt16(value)
    }

    private func unsigned16(_ value: Double?) -> UInt16? {
        guard let value, value.isFinite, value >= 0, value <= Double(UInt16.max) else { return nil }
        return UInt16(value.rounded(.towardZero))
    }
}
