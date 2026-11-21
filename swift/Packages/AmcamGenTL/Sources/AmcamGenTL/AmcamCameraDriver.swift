import Foundation
import AmcamCameraModel

public final class AmcamCameraDriver: @unchecked Sendable {
    private let sdk: AmcamSDK
    private let profileRegistry: AmcamCameraProfileRegistry

    public init(
        libraryURL: URL,
        profileRegistry: AmcamCameraProfileRegistry = AmcamCameraProfileRegistry()
    ) throws {
        self.sdk = try AmcamSDK(libraryURL: libraryURL)
        self.profileRegistry = profileRegistry
    }

    public func discover() throws -> [AmcamDevice] { try sdk.enumerate() }

    public func open(deviceIdentifier: String) throws -> AmcamCameraSession {
        let opened = try sdk.open(identifier: deviceIdentifier)
        return AmcamCameraSession(
            sdk: sdk,
            handle: opened.handle,
            width: opened.width,
            height: opened.height,
            modelCode: opened.modelName ?? "Unknown",
            pullImageAPIPolicy: profileRegistry.pullImageAPIPolicy(for: opened.modelName ?? "Unknown"),
            modelFlags: opened.modelFlags,
            maximumSpeedLevel: opened.maximumSpeedLevel,
            resolutions: opened.resolutions,
            currentResolutionIndex: opened.currentResolutionIndex
        )
    }
}
