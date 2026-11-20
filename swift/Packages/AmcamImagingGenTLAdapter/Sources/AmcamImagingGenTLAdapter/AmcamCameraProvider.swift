import AmcamCameraModel
import Foundation
import GenTLABI
import GenTLAPI
import GenTLRouter

public struct AmcamCameraCandidate: Sendable, Identifiable {
    public let device: AmcamDevice
    public let runtimeDevice: GenTLRuntimeDevice

    public var id: String { device.identifier }

    fileprivate init(device: AmcamDevice, runtimeDevice: GenTLRuntimeDevice) {
        self.device = device
        self.runtimeDevice = runtimeDevice
    }
}

public struct AmcamCameraProviderFailure: Equatable, Sendable, Identifiable {
    public let backendID: String
    public let message: String
    public var id: String { backendID }

    public init(backendID: String, message: String) {
        self.backendID = backendID
        self.message = message
    }
}

public struct AmcamCameraDiscoveryReport: Sendable {
    public let devices: [AmcamCameraCandidate]
    public let failures: [AmcamCameraProviderFailure]

    public init(devices: [AmcamCameraCandidate], failures: [AmcamCameraProviderFailure]) {
        self.devices = devices
        self.failures = failures
    }

    public var isComplete: Bool { failures.isEmpty }
}

/// Owns AmScope SDK registration and GenTL discovery. The application receives
/// camera-model values and opaque runtime devices, never GenTL handles or ABI calls.
public actor AmcamCameraProvider {
    private let router: GenTLRouter
    private var discoveryTask: Task<AmcamCameraDiscoveryReport, Never>?

    public init(backendID: String = "amcam-sdk") throws {
        let router = GenTLRouter()
        try router.registerAmcam(backendID: backendID)
        self.router = router
    }

    /// GenTL discovery and metadata calls are synchronous vendor operations;
    /// keep them off the UI executor.
    public func discover(timeout: UInt64 = 2_000) async -> AmcamCameraDiscoveryReport {
        if let discoveryTask {
            return await discoveryTask.value
        }
        let router = self.router
        let task = Task.detached(priority: .userInitiated) {
            Self.discover(using: router, timeout: timeout)
        }
        discoveryTask = task
        let report = await task.value
        discoveryTask = nil
        return report
    }

    private static func discover(
        using router: GenTLRouter,
        timeout: UInt64
    ) -> AmcamCameraDiscoveryReport {
        let report = router.discover(timeout: timeout)
        let candidates = report.devices.map { candidate -> AmcamCameraCandidate in
            let displayName = (try? readDeviceString(
                candidate,
                command: Int32(GenTLABI.DEVICE_INFO_DISPLAYNAME.rawValue)
            )).flatMap { $0.isEmpty ? nil : $0 } ?? candidate.deviceID
            let modelName = try? readDeviceString(
                candidate,
                command: Int32(GenTLABI.DEVICE_INFO_MODEL.rawValue)
            )
            let device = AmcamDevice(
                identifier: candidate.id,
                displayName: displayName,
                modelName: modelName,
                modelFlags: nil,
                maximumSpeedLevel: nil,
                sensorPixelSizeMicrometers: nil,
                previewResolutions: []
            )
            return AmcamCameraCandidate(
                device: device,
                runtimeDevice: GenTLRuntimeDevice(candidate: candidate)
            )
        }
        return AmcamCameraDiscoveryReport(
            devices: candidates,
            failures: report.failures.map {
                AmcamCameraProviderFailure(backendID: $0.backendID, message: $0.message)
            }
        )
    }

    private static func readDeviceString(
        _ candidate: GenTLDeviceCandidate,
        command: Int32
    ) throws -> String {
        var dataType: GenTLABI.INFO_DATATYPE = 0
        var requiredSize = 0
        let queryStatus = candidate.api.IFGetDeviceInfo(
            candidate.interfaceHandle,
            candidate.deviceID.withCString { $0 },
            command,
            &dataType,
            nil,
            &requiredSize
        )
        let success = GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
        let bufferTooSmall = GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_BUFFER_TOO_SMALL)
        guard queryStatus == success || queryStatus == bufferTooSmall else {
            throw GenTLProviderMetadataError.callFailed(Int32(queryStatus))
        }
        guard requiredSize > 1, requiredSize <= 1_048_576 else {
            throw GenTLProviderMetadataError.invalidResponse
        }

        var bytes = [CChar](repeating: 0, count: requiredSize)
        var capacity = requiredSize
        let status = bytes.withUnsafeMutableBufferPointer { buffer in
            candidate.api.IFGetDeviceInfo(
                candidate.interfaceHandle,
                candidate.deviceID.withCString { $0 },
                command,
                &dataType,
                buffer.baseAddress,
                &capacity
            )
        }
        guard status == success else {
            throw GenTLProviderMetadataError.callFailed(Int32(status))
        }
        guard dataType == Int32(GenTLABI.INFO_DATATYPE_STRING.rawValue),
              capacity > 0, capacity <= bytes.count else {
            throw GenTLProviderMetadataError.invalidResponse
        }

        bytes[min(capacity, bytes.count) - 1] = 0
        return String(cString: bytes)
    }
}

private enum GenTLProviderMetadataError: Error {
    case callFailed(Int32)
    case invalidResponse
}
