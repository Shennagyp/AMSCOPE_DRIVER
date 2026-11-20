import XCTest
import AmcamCameraModel
import AmcamImagingRuntime
@testable import AmcamImagingState

private actor FeatureReadRecorder {
    private var names: [String] = []

    func record(_ name: String) {
        names.append(name)
    }

    func recordedNames() -> [String] {
        names
    }
}

final class AmcamCameraStateResolverTests: XCTestCase {
    func testControlSnapshotMapsTypedReadbacksAndRanges() async {
        let resolver = AmcamCameraStateResolver()
        let descriptors = [
            CameraFeatureDescriptor(
                name: "ExposureAuto", displayName: "Auto exposure", kind: .enumeration,
                isAvailable: true, isReadable: true, isWritable: true,
                enumerationValues: ["Off", "Once", "Continuous"]
            ),
            CameraFeatureDescriptor(
                name: "ExposureTime", displayName: "Exposure", kind: .integer,
                isAvailable: true, isReadable: true, isWritable: true,
                numericRange: CameraFeatureNumericRange(minimum: 100, maximum: 500_000)
            ),
            CameraFeatureDescriptor(
                name: "AmcamAnalogGainPercent", displayName: "Gain", kind: .integer,
                isAvailable: true, isReadable: true, isWritable: true,
                numericRange: CameraFeatureNumericRange(minimum: 100, maximum: 1600)
            ),
            CameraFeatureDescriptor(
                name: "AmcamPixelFormat", displayName: "Pixel format", kind: .enumeration,
                isAvailable: true, isReadable: true, isWritable: true,
                enumerationValues: ["0", "8"]
            ),
            CameraFeatureDescriptor(
                name: "AmcamFrameSpeedLevel", displayName: "Frame speed", kind: .integer,
                isAvailable: true, isReadable: true, isWritable: true,
                numericRange: CameraFeatureNumericRange(minimum: 0, maximum: 3)
            ),
            CameraFeatureDescriptor(
                name: "AmcamFixedFrameRate", displayName: "Fixed frame rate", kind: .floatingPoint,
                isAvailable: true, isReadable: true, isWritable: true,
                numericRange: CameraFeatureNumericRange(minimum: 1, maximum: 120)
            )
        ]
        let values: [String: CameraFeatureValue] = [
            "ExposureAuto": .enumeration("Off"),
            "ExposureTime": .integer(12_500),
            "AmcamAnalogGainPercent": .integer(400),
            "AmcamPixelFormat": .enumeration("8"),
            "AmcamFixedFrameRate": .floatingPoint(60),
            "AmcamFrameSpeedLevel": .integer(2)
        ]
        let snapshot = await resolver.controlSnapshot(descriptors: descriptors) { name in
            guard let value = values[name] else { throw CameraFeatureAccessError.featureNotFound(name) }
            return value
        }

        XCTAssertEqual(snapshot.exposure?.autoMode, .manual)
        XCTAssertEqual(snapshot.exposure?.readbackMicroseconds, 12_500)
        XCTAssertEqual(snapshot.exposure?.minimumMicroseconds, 100)
        XCTAssertEqual(snapshot.exposure?.maximumMicroseconds, 500_000)
        XCTAssertEqual(snapshot.gain?.readbackPercent, 400)
        XCTAssertEqual(snapshot.image?.pixelFormatCode, 8)
        XCTAssertEqual(snapshot.image?.supportedPixelFormats, [0, 8])
        XCTAssertEqual(snapshot.frameRate.readbackFramesPerSecond, 60)
        XCTAssertEqual(snapshot.frameRate.currentSpeedLevel, 2)
    }

    func testControlSnapshotNeverReadsUnavailableOrUnreadableFeatures() async {
        let resolver = AmcamCameraStateResolver()
        let descriptors = [
            CameraFeatureDescriptor(
                name: "ExposureAuto", displayName: "Auto exposure", kind: .enumeration,
                isAvailable: true, isReadable: true, isWritable: false
            ),
            CameraFeatureDescriptor(
                name: "ExposureTime", displayName: "Exposure", kind: .integer,
                isAvailable: true, isReadable: false, isWritable: true
            ),
            CameraFeatureDescriptor(
                name: "AmcamAnalogGainPercent", displayName: "Gain", kind: .integer,
                isAvailable: false, isReadable: true, isWritable: false
            ),
            CameraFeatureDescriptor(
                name: "AmcamColorMatrixEnabled", displayName: "Color matrix", kind: .boolean,
                isAvailable: false, isReadable: true, isWritable: false
            ),
            CameraFeatureDescriptor(
                name: "AmcamPixelFormat", displayName: "Pixel format", kind: .enumeration,
                isAvailable: true, isReadable: false, isWritable: false
            ),
            CameraFeatureDescriptor(
                name: "AmcamFixedFrameRate", displayName: "Fixed frame rate", kind: .floatingPoint,
                isAvailable: false, isReadable: true, isWritable: false
            ),
            CameraFeatureDescriptor(
                name: "AmcamFrameSpeedLevel", displayName: "Frame speed", kind: .integer,
                isAvailable: true, isReadable: false, isWritable: false
            ),
            CameraFeatureDescriptor(
                name: "AmcamWhiteBalanceTemperature", displayName: "White balance temperature",
                kind: .integer, isAvailable: false, isReadable: true, isWritable: false
            )
        ]
        let recorder = FeatureReadRecorder()
        _ = await resolver.controlSnapshot(descriptors: descriptors) { name in
            await recorder.record(name)
            throw CameraFeatureAccessError.featureUnavailable(name)
        }
        let attemptedReads = await recorder.recordedNames()
        XCTAssertTrue(attemptedReads.isEmpty)
    }

    func testCurrentResolutionDoesNotReadUnavailableFeature() async {
        let resolver = AmcamCameraStateResolver()
        let device = AmcamDevice(
            identifier: "camera", displayName: "Camera", modelName: "MU503",
            modelFlags: nil, maximumSpeedLevel: nil,
            sensorPixelSizeMicrometers: nil,
            previewResolutions: [AmcamResolution(index: 3, width: 1920, height: 1080)]
        )
        let recorder = FeatureReadRecorder()
        let result = await resolver.currentResolution(
            for: device,
            descriptors: [
                CameraFeatureDescriptor(
                    name: "AmcamResolutionIndex", displayName: "Resolution", kind: .enumeration,
                    isAvailable: false, isReadable: true, isWritable: false
                )
            ]
        ) { name in
            await recorder.record(name)
            return .enumeration("3:1920x1080")
        }
        let attemptedReads = await recorder.recordedNames()
        XCTAssertNil(result)
        XCTAssertTrue(attemptedReads.isEmpty)
    }

    func testMalformedResolutionOptionsAreIgnored() {
        let resolver = AmcamCameraStateResolver()
        let descriptor = CameraFeatureDescriptor(
            name: "AmcamResolutionIndex", displayName: "Resolution", kind: .enumeration,
            isAvailable: true, isReadable: true, isWritable: true,
            enumerationValues: ["0:640x480", "1:1920x1080", "broken", "2:badx720"]
        )
        XCTAssertEqual(
            resolver.resolutions(from: [descriptor]),
            [AmcamResolution(index: 0, width: 640, height: 480),
             AmcamResolution(index: 1, width: 1920, height: 1080)]
        )
    }

    func testCurrentResolutionUsesTypedFeatureReadback() async {
        let resolver = AmcamCameraStateResolver()
        let device = AmcamDevice(
            identifier: "camera", displayName: "Camera", modelName: "MU503",
            modelFlags: nil, maximumSpeedLevel: nil,
            sensorPixelSizeMicrometers: nil,
            previewResolutions: [AmcamResolution(index: 3, width: 1920, height: 1080)]
        )
        let result = await resolver.currentResolution(
            for: device,
            descriptors: [
                CameraFeatureDescriptor(
                    name: "AmcamResolutionIndex", displayName: "Resolution", kind: .enumeration,
                    isAvailable: true, isReadable: true, isWritable: true
                )
            ]
        ) { name in
            XCTAssertEqual(name, "AmcamResolutionIndex")
            return .enumeration("3:1920x1080")
        }
        XCTAssertEqual(result, AmcamResolution(index: 3, width: 1920, height: 1080))
    }

    func testFeatureWriteValidationUsesCurrentDescriptorContract() {
        let resolver = AmcamCameraStateResolver()
        let descriptors = [
            CameraFeatureDescriptor(
                name: "ExposureTime", displayName: "Exposure", kind: .integer,
                isAvailable: true, isReadable: true, isWritable: true
            ),
            CameraFeatureDescriptor(
                name: "ReadOnlyTemperature", displayName: "Temperature", kind: .integer,
                isAvailable: true, isReadable: true, isWritable: false
            ),
            CameraFeatureDescriptor(
                name: "UnavailableGain", displayName: "Gain", kind: .integer,
                isAvailable: false, isReadable: false, isWritable: false
            )
        ]

        XCTAssertNil(resolver.validateWrite(.integer(10_000), named: "ExposureTime", descriptors: descriptors))
        XCTAssertEqual(
            resolver.validateWrite(.integer(10), named: "ReadOnlyTemperature", descriptors: descriptors),
            .featureNotWritable("ReadOnlyTemperature")
        )
        XCTAssertEqual(
            resolver.validateWrite(.integer(10), named: "UnavailableGain", descriptors: descriptors),
            .featureUnavailable("UnavailableGain")
        )
        XCTAssertEqual(
            resolver.validateWrite(.boolean(true), named: "ExposureTime", descriptors: descriptors),
            .valueTypeMismatch(feature: "ExposureTime", expected: .integer, actual: .boolean)
        )
        XCTAssertEqual(
            resolver.validateWrite(.integer(10), named: "MissingFeature", descriptors: descriptors),
            .featureNotFound("MissingFeature")
        )
    }

    func testCapabilityPolicyCannotFabricateUnavailableHardwareFeatures() {
        let profile = AmcamCameraModelProfile(
            modelCode: "MU503",
            allowedFeatures: [.exposureManual]
        )
        let resolver = AmcamCameraStateResolver(
            profileRegistry: AmcamCameraProfileRegistry(profiles: [profile])
        )
        let device = AmcamDevice(
            identifier: "camera", displayName: "Camera", modelName: "MU503",
            modelFlags: nil, maximumSpeedLevel: nil,
            sensorPixelSizeMicrometers: nil, previewResolutions: []
        )
        let descriptors = [
            CameraFeatureDescriptor(
                name: "ExposureTime", displayName: "Exposure", kind: .integer,
                isAvailable: false, isReadable: false, isWritable: false
            ),
            CameraFeatureDescriptor(
                name: "ExposureAuto", displayName: "Auto exposure", kind: .enumeration,
                isAvailable: true, isReadable: true, isWritable: true,
                enumerationValues: ["Off", "Once", "Continuous"]
            )
        ]

        let capabilities = resolver.capabilities(
            for: device,
            descriptors: descriptors,
            hasDataStream: false
        )

        let manualExposure = capabilities.availability(of: .exposureManual)
        let autoExposure = capabilities.availability(of: .exposureAuto)
        let liveCapture = capabilities.availability(of: .liveCapture)

        XCTAssertFalse(manualExposure.isUsable, "A profile allow-list cannot override unavailable hardware.")
        XCTAssertFalse(autoExposure.isUsable, "Features outside the explicit allow-list remain unavailable.")
        XCTAssertFalse(liveCapture.isUsable, "A profile cannot fabricate a missing data stream.")
        XCTAssertTrue(manualExposure.reason?.contains("probe") == true)
        XCTAssertTrue(autoExposure.reason?.contains("allow-list") == true)
    }

}
