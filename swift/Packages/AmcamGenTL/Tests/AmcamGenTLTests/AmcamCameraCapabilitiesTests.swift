import XCTest
@testable import AmcamGenTL

final class AmcamCameraCapabilitiesTests: XCTestCase {
    private let implemented: Set<AmcamCameraFeature> = [
        .liveCapture, .resolution, .exposureAuto, .exposureManual,
        .preciseFrameRate, .discreteFrameSpeed
    ]

    func testModelFlagsResolveOnlyAdvertisedHardwareFeatures() {
        let flags: UInt64 = 0x00000008 | 0x0000004000000000
        let capabilities = AmcamCameraProfileRegistry().resolve(
            modelCode: "MU503",
            modelFlags: flags,
            maximumSpeedLevel: 3,
            probes: [.exposureAuto: true, .exposureManual: true, .preciseFrameRate: true, .discreteFrameSpeed: true],
            implemented: implemented
        )

        XCTAssertTrue(capabilities.availability(of: .hardwareROI).available)
        XCTAssertFalse(capabilities.availability(of: .hardwareROI).isUsable)
        XCTAssertTrue(capabilities.availability(of: .preciseFrameRate).isUsable)
        XCTAssertFalse(capabilities.availability(of: .thermoelectricCooling).available)
        XCTAssertTrue(capabilities.availability(of: .exposureManual).isUsable)
    }

    func testModelProfileCanRestrictButCannotInventCapabilities() {
        let profile = AmcamCameraModelProfile(
            modelCode: "MU503",
            displayName: "MU503",
            allowedFeatures: [.liveCapture, .resolution, .exposureAuto, .exposureManual],
            deniedFeatures: [.exposureAuto]
        )
        let registry = AmcamCameraProfileRegistry(profiles: [profile])
        let capabilities = registry.resolve(
            modelCode: "MU503",
            modelFlags: 0,
            maximumSpeedLevel: nil,
            probes: [.exposureAuto: true, .exposureManual: true],
            implemented: implemented
        )

        XCTAssertFalse(capabilities.availability(of: .exposureAuto).available)
        XCTAssertTrue(capabilities.availability(of: .exposureManual).available)
        XCTAssertFalse(capabilities.availability(of: .preciseFrameRate).available)
        XCTAssertTrue(capabilities.availability(of: .exposureAuto).reason?.contains("Disabled") == true)
    }

    func testUnconfirmedProbeDoesNotExposeFeature() {
        let capabilities = AmcamCameraProfileRegistry().resolve(
            modelCode: "UnknownModel",
            modelFlags: 0,
            maximumSpeedLevel: nil,
            probes: [:],
            implemented: implemented
        )

        XCTAssertFalse(capabilities.availability(of: .exposureManual).available)
        XCTAssertFalse(capabilities.availability(of: .analogGain).available)
        XCTAssertFalse(capabilities.availableGroups.contains(.exposureAndGain))
    }

    func testDiscreteSpeedRequiresUsableModelRangeAndSuccessfulProbe() {
        let registry = AmcamCameraProfileRegistry()
        let noRange = registry.resolve(
            modelCode: "ModelA", modelFlags: 0, maximumSpeedLevel: nil,
            probes: [.discreteFrameSpeed: true], implemented: implemented
        )
        let noProbe = registry.resolve(
            modelCode: "ModelA", modelFlags: 0, maximumSpeedLevel: 4,
            probes: [.discreteFrameSpeed: false], implemented: implemented
        )

        XCTAssertFalse(noRange.availability(of: .discreteFrameSpeed).available)
        XCTAssertFalse(noProbe.availability(of: .discreteFrameSpeed).available)
    }

    func testAvailableGroupsContainOnlyUsableFeatures() {
        let capabilities = AmcamCameraProfileRegistry().resolve(
            modelCode: "ModelA", modelFlags: 0x0000004000000000,
            maximumSpeedLevel: nil, probes: [:],
            implemented: [.liveCapture, .resolution, .preciseFrameRate]
        )

        XCTAssertTrue(capabilities.availableGroups.contains(.capture))
        XCTAssertTrue(capabilities.availableGroups.contains(.frameRate))
        XCTAssertFalse(capabilities.availableGroups.contains(.exposureAndGain))
    }
}
