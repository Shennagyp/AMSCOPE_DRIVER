import Foundation

public final class AmcamCameraDriver: @unchecked Sendable {
    private let sdk: AmcamSDK

    public init(libraryURL: URL) throws {
        self.sdk = try AmcamSDK(libraryURL: libraryURL)
    }

    public func discover() throws -> [AmcamDevice] { try sdk.enumerate() }

    public func open(deviceIdentifier: String) throws -> AmcamCameraSession {
        let opened = try sdk.open(identifier: deviceIdentifier)
        return AmcamCameraSession(
            sdk: sdk,
            handle: opened.handle,
            width: opened.width,
            height: opened.height,
            modelFlags: opened.modelFlags,
            maximumSpeedLevel: opened.maximumSpeedLevel,
            resolutions: opened.resolutions,
            currentResolutionIndex: opened.currentResolutionIndex
        )
    }
}
