import Foundation

public enum AmcamProbeStatus: String, Codable, Equatable, Sendable {
    case success
    case failure
}

public enum AmcamProbeStage: String, Codable, CaseIterable, Equatable, Sendable {
    case argumentParsing = "argument-parsing"
    case sdkLibraryValidation = "sdk-library-validation"
    case libraryInitialization = "library-initialization"
    case sdkVersionRead = "sdk-version-read"
    case transportLayerOpen = "transport-layer-open"
    case interfaceDiscovery = "interface-discovery"
    case deviceDiscovery = "device-discovery"
    case deviceOpen = "device-open"
    case dataStreamOpen = "data-stream-open"
    case bufferPreparation = "buffer-preparation"
    case acquisitionStart = "acquisition-start"
    case frameRead = "frame-read"
    case frameValidation = "frame-validation"
    case bufferQueue = "buffer-queue"
    case acquisitionStop = "acquisition-stop"
    case outputWrite = "output-write"
    case cleanup = "cleanup"
}

public struct AmcamProbeFailure: Codable, Equatable, Sendable {
    public var stage: AmcamProbeStage
    public var message: String

    public init(stage: AmcamProbeStage, message: String) {
        self.stage = stage
        self.message = message
    }
}

public struct AmcamProbeSDKInfo: Codable, Equatable, Sendable {
    public var path: String?
    public var version: String?

    public init(path: String? = nil, version: String? = nil) {
        self.path = path
        self.version = version
    }
}

public struct AmcamProbeDeviceInfo: Codable, Equatable, Sendable {
    public var index: Int?
    public var identifier: String?
    public var modelName: String?
    public var displayName: String?
    public var discoveredCount: Int?

    public init(
        index: Int? = nil,
        identifier: String? = nil,
        modelName: String? = nil,
        displayName: String? = nil,
        discoveredCount: Int? = nil
    ) {
        self.index = index
        self.identifier = identifier
        self.modelName = modelName
        self.displayName = displayName
        self.discoveredCount = discoveredCount
    }
}

public struct AmcamProbeStreamInfo: Codable, Equatable, Sendable {
    public var identifier: String?
    public var payloadSize: Int?
    public var announcedBufferCount: Int?

    public init(
        identifier: String? = nil,
        payloadSize: Int? = nil,
        announcedBufferCount: Int? = nil
    ) {
        self.identifier = identifier
        self.payloadSize = payloadSize
        self.announcedBufferCount = announcedBufferCount
    }
}

public struct AmcamProbeImageInfo: Codable, Equatable, Sendable {
    public var width: Int?
    public var height: Int?
    public var pixelFormatCode: UInt64?
    public var pixelFormatNamespace: UInt64?
    public var bytesPerRow: Int?
    public var rowPaddingBytes: Int?
    public var sizeFilled: Int?
    public var dataSize: Int?

    public init(
        width: Int? = nil,
        height: Int? = nil,
        pixelFormatCode: UInt64? = nil,
        pixelFormatNamespace: UInt64? = nil,
        bytesPerRow: Int? = nil,
        rowPaddingBytes: Int? = nil,
        sizeFilled: Int? = nil,
        dataSize: Int? = nil
    ) {
        self.width = width
        self.height = height
        self.pixelFormatCode = pixelFormatCode
        self.pixelFormatNamespace = pixelFormatNamespace
        self.bytesPerRow = bytesPerRow
        self.rowPaddingBytes = rowPaddingBytes
        self.sizeFilled = sizeFilled
        self.dataSize = dataSize
    }
}

public struct AmcamProbeAcquisitionInfo: Codable, Equatable, Sendable {
    public var requestedFrameCount: Int?
    public var completeFrameCount: Int?
    public var incompleteFrameCount: Int?
    public var elapsedSeconds: Double?
    public var hostLoopFramesPerSecond: Double?
    public var cameraTimestampFramesPerSecond: Double?
    public var firstSequence: UInt64?
    public var lastSequence: UInt64?
    public var firstDeviceTimestampMicroseconds: UInt64?
    public var lastDeviceTimestampMicroseconds: UInt64?
    public var lastFrameSha256: String?

    public init(
        requestedFrameCount: Int? = nil,
        completeFrameCount: Int? = nil,
        incompleteFrameCount: Int? = nil,
        elapsedSeconds: Double? = nil,
        hostLoopFramesPerSecond: Double? = nil,
        cameraTimestampFramesPerSecond: Double? = nil,
        firstSequence: UInt64? = nil,
        lastSequence: UInt64? = nil,
        firstDeviceTimestampMicroseconds: UInt64? = nil,
        lastDeviceTimestampMicroseconds: UInt64? = nil,
        lastFrameSha256: String? = nil
    ) {
        self.requestedFrameCount = requestedFrameCount
        self.completeFrameCount = completeFrameCount
        self.incompleteFrameCount = incompleteFrameCount
        self.elapsedSeconds = elapsedSeconds
        self.hostLoopFramesPerSecond = hostLoopFramesPerSecond
        self.cameraTimestampFramesPerSecond = cameraTimestampFramesPerSecond
        self.firstSequence = firstSequence
        self.lastSequence = lastSequence
        self.firstDeviceTimestampMicroseconds = firstDeviceTimestampMicroseconds
        self.lastDeviceTimestampMicroseconds = lastDeviceTimestampMicroseconds
        self.lastFrameSha256 = lastFrameSha256
    }
}

/// Stable, versioned machine-readable output from the Amcam camera probe.
public struct AmcamCameraProbeReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var backend: String
    public var status: AmcamProbeStatus
    public var sdk: AmcamProbeSDKInfo?
    public var interfaceIdentifier: String?
    public var device: AmcamProbeDeviceInfo?
    public var stream: AmcamProbeStreamInfo?
    public var image: AmcamProbeImageInfo?
    public var acquisition: AmcamProbeAcquisitionInfo?
    public var outputImagePath: String?
    public var failure: AmcamProbeFailure?
    public var cleanupErrors: [String]

    public init() {
        schemaVersion = 1
        backend = "AmcamGenTL"
        status = .success
        sdk = nil
        interfaceIdentifier = nil
        device = nil
        stream = nil
        image = nil
        acquisition = nil
        outputImagePath = nil
        failure = nil
        cleanupErrors = []
    }
}
