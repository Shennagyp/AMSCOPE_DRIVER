import Foundation

public enum AmcamProbeCleanupEvent: Equatable, Sendable {
    case error
    case newBuffer
}

public enum AmcamProbeCleanupStep: Equatable, Sendable {
    case stopAcquisition
    case unregisterEvent(AmcamProbeCleanupEvent)
    case flushAllDiscard
    case revokeBuffer(UInt)
    case closeDataStream
    case closeDevice
    case closeInterface
    case closeTransportLayer
    case closeLibrary

    public var operationName: String {
        switch self {
        case .stopAcquisition:
            return "DSStopAcquisition"
        case .unregisterEvent(.error):
            return "GCUnregisterEvent(error)"
        case .unregisterEvent(.newBuffer):
            return "GCUnregisterEvent(new-buffer)"
        case .flushAllDiscard:
            return "DSFlushQueue(AllDiscard)"
        case .revokeBuffer:
            return "DSRevokeBuffer"
        case .closeDataStream:
            return "DSClose"
        case .closeDevice:
            return "DevClose"
        case .closeInterface:
            return "IFClose"
        case .closeTransportLayer:
            return "TLClose"
        case .closeLibrary:
            return "GCCloseLib"
        }
    }
}

public struct AmcamProbeCleanupFailure: Codable, Equatable, Sendable {
    public var operation: String
    public var message: String

    public init(operation: String, message: String) {
        self.operation = operation
        self.message = message
    }
}

/// Produces and executes the probe's resource-release sequence.
///
/// A failed release stops the sequence immediately. Child resources are never
/// bypassed to close a parent module that may still be referenced by them.
public enum AmcamProbeCleanupCoordinator {
    public static func plan(
        streamIsOpen: Bool,
        acquisitionStarted: Bool,
        errorEventRegistered: Bool,
        newBufferEventRegistered: Bool,
        bufferHandles: [UInt],
        deviceIsOpen: Bool,
        interfaceIsOpen: Bool,
        transportLayerIsOpen: Bool,
        libraryInitialized: Bool
    ) -> [AmcamProbeCleanupStep] {
        var steps: [AmcamProbeCleanupStep] = []

        if streamIsOpen {
            if acquisitionStarted {
                steps.append(.stopAcquisition)
            }
            if errorEventRegistered {
                steps.append(.unregisterEvent(.error))
            }
            if newBufferEventRegistered {
                steps.append(.unregisterEvent(.newBuffer))
            }
            steps.append(.flushAllDiscard)
            steps.append(contentsOf: bufferHandles.sorted().map(AmcamProbeCleanupStep.revokeBuffer))
            steps.append(.closeDataStream)
        }

        if deviceIsOpen {
            steps.append(.closeDevice)
        }
        if interfaceIsOpen {
            steps.append(.closeInterface)
        }
        if transportLayerIsOpen {
            steps.append(.closeTransportLayer)
        }
        if libraryInitialized {
            steps.append(.closeLibrary)
        }

        return steps
    }

    public static func execute(
        _ steps: [AmcamProbeCleanupStep],
        perform: (AmcamProbeCleanupStep) throws -> Void
    ) -> [AmcamProbeCleanupFailure] {
        for step in steps {
            do {
                try perform(step)
            } catch {
                return [
                    AmcamProbeCleanupFailure(
                        operation: step.operationName,
                        message: error.localizedDescription
                    )
                ]
            }
        }
        return []
    }
}
