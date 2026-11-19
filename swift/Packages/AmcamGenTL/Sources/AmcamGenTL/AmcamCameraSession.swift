import AmcamABI
import Foundation

private final class AmcamCallbackContext {
    weak var session: AmcamCameraSession?
    init(session: AmcamCameraSession) { self.session = session }
}

public final class AmcamCameraSession: @unchecked Sendable {
    private static let callback: AmcamEventCallback = { event, context in
        guard let context else { return }
        Unmanaged<AmcamCallbackContext>.fromOpaque(context).takeUnretainedValue().session?.handle(event: event)
    }

    private let sdk: AmcamSDK
    private let lock = NSLock()
    private let controlLock = NSRecursiveLock()
    private let modelFlags: UInt64?
    private let maximumSpeedLevel: Int?
    private var handle: UnsafeMutableRawPointer?
    private var width: Int
    private var height: Int
    private let resolutions: [AmcamResolution]
    private var currentResolutionIndex: Int?
    private var buffer: UnsafeMutableRawPointer?
    private var bufferCapacity = 0
    private var callbackContext: UnsafeMutableRawPointer?
    private var frameHandler: (@Sendable (Result<AmcamFrame, AmcamCameraError>) -> Void)?
    private var starting = false
    private var stopping = false
    private var streaming = false
    private var requestedExposureMicroseconds: UInt32?
    private var requestedFrameRate: Double?
    private var requestedSpeedLevel: Int?

    init(
        sdk: AmcamSDK,
        handle: UnsafeMutableRawPointer,
        width: Int,
        height: Int,
        modelFlags: UInt64?,
        maximumSpeedLevel: Int?,
        resolutions: [AmcamResolution],
        currentResolutionIndex: Int?
    ) {
        self.sdk = sdk
        self.handle = handle
        self.width = width
        self.height = height
        self.modelFlags = modelFlags
        self.maximumSpeedLevel = maximumSpeedLevel
        self.resolutions = resolutions
        self.currentResolutionIndex = currentResolutionIndex
    }

    public func currentResolution() -> AmcamResolution? {
        controlLock.lock()
        defer { controlLock.unlock() }
        guard let currentResolutionIndex else { return nil }
        return resolutions.first { $0.index == currentResolutionIndex }
    }

    public func supportsResolutionChange() -> Bool {
        sdk.resolutionChangeAvailable
    }

    /// Resolution changes are only valid while the stream is stopped.
    public func setResolution(index: Int) throws -> AmcamResolution {
        controlLock.lock()
        defer { controlLock.unlock() }

        lock.lock()
        guard !starting, !stopping, !streaming, let activeHandle = handle else {
            let isClosed = handle == nil
            lock.unlock()
            throw isClosed
                ? AmcamCameraError.sessionClosed
                : AmcamCameraError.resolutionChangeRequiresStoppedStream
        }
        lock.unlock()

        let resolution = try sdk.setResolution(
            activeHandle,
            index: index,
            supportedResolutions: resolutions
        )

        lock.lock()
        width = resolution.width
        height = resolution.height
        currentResolutionIndex = resolution.index
        lock.unlock()
        return resolution
    }

    public func start(onFrame: @escaping @Sendable (Result<AmcamFrame, AmcamCameraError>) -> Void) throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        lock.lock()
        guard handle != nil else { lock.unlock(); throw AmcamCameraError.sessionClosed }
        guard callbackContext == nil else {
            lock.unlock()
            throw AmcamCameraError.transitionInProgress
        }
        guard !streaming, !starting, !stopping else { lock.unlock(); throw AmcamCameraError.alreadyStreaming }

        let (pixels, overflow1) = width.multipliedReportingOverflow(by: height)
        let (capacity, overflow2) = pixels.multipliedReportingOverflow(by: 4)
        guard !overflow1, !overflow2, capacity > 0, capacity <= 512 * 1024 * 1024 else {
            lock.unlock()
            throw AmcamCameraError.frameBufferTooLarge
        }

        let newBuffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 64)
        newBuffer.initializeMemory(as: UInt8.self, repeating: 0, count: capacity)
        buffer = newBuffer
        bufferCapacity = capacity
        frameHandler = onFrame

        let retained = Unmanaged.passRetained(AmcamCallbackContext(session: self)).toOpaque()
        callbackContext = retained
        starting = true
        streaming = true
        let activeHandle = handle!
        lock.unlock()

        // Do not hold the session lock while invoking the SDK: it may deliver a callback
        // before Amcam_StartPullModeWithCallback returns.
        let result = sdk.startPull(activeHandle, callback: Self.callback, context: retained)

        lock.lock()
        starting = false
        if result < 0 {
            streaming = false
            callbackContext = nil
            frameHandler = nil
            buffer?.deallocate()
            buffer = nil
            bufferCapacity = 0
            lock.unlock()
            Unmanaged<AmcamCallbackContext>.fromOpaque(retained).release()
            throw AmcamCameraError.streamStartFailed(result)
        }
        lock.unlock()
    }

    public func stop() throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        lock.lock()
        guard !starting, !stopping else { lock.unlock(); throw AmcamCameraError.transitionInProgress }
        guard let handle else { lock.unlock(); throw AmcamCameraError.sessionClosed }
        guard streaming else { lock.unlock(); throw AmcamCameraError.notStreaming }

        // Mark delivery inactive before entering the SDK. Never hold the session lock
        // across Amcam_Stop because the SDK may be waiting for an event callback to return.
        streaming = false
        stopping = true
        lock.unlock()

        let result = sdk.stop(handle)

        lock.lock()
        stopping = false
        guard result >= 0 else {
            streaming = true
            lock.unlock()
            throw AmcamCameraError.streamStopFailed(result)
        }

        frameHandler = nil
        let context = callbackContext
        callbackContext = nil
        buffer?.deallocate()
        buffer = nil
        bufferCapacity = 0
        lock.unlock()
        if let context { Unmanaged<AmcamCallbackContext>.fromOpaque(context).release() }
    }

    public func close() throws {
        controlLock.lock()
        defer { controlLock.unlock() }
        lock.lock()
        guard !starting, !stopping else { lock.unlock(); throw AmcamCameraError.transitionInProgress }
        let isStreaming = streaming
        let needsCallbackCleanup = callbackContext != nil
        lock.unlock()

        if isStreaming {
            try stop()
        } else if needsCallbackCleanup {
            // A disconnect/error event may end delivery while the SDK still owns the callback.
            lock.lock()
            guard !stopping, let handle else { lock.unlock(); throw AmcamCameraError.transitionInProgress }
            stopping = true
            lock.unlock()

            let result = sdk.stop(handle)

            lock.lock()
            stopping = false
            guard result >= 0 else { lock.unlock(); throw AmcamCameraError.streamStopFailed(result) }
            let context = callbackContext
            callbackContext = nil
            frameHandler = nil
            buffer?.deallocate()
            buffer = nil
            bufferCapacity = 0
            lock.unlock()
            if let context { Unmanaged<AmcamCallbackContext>.fromOpaque(context).release() }
        }

        lock.lock()
        guard let handle else { lock.unlock(); return }
        self.handle = nil
        lock.unlock()
        sdk.close(handle)
    }

    deinit {
        do {
            try close()
        } catch {
            // The SDK may still own the native handle, callback and pull buffer.
            // Keep its dylib loaded rather than unloading code still in use.
            sdk.retainForProcessLifetimeAfterCleanupFailure()
        }
    }


    public func readControls() throws -> AmcamControlSnapshot {
        controlLock.lock()
        defer { controlLock.unlock() }
        let activeHandle = try controlHandle()
        return try readControls(
            using: activeHandle,
            requestedExposure: requestedExposureMicroseconds,
            requestedFrameRate: requestedFrameRate,
            requestedSpeedLevel: requestedSpeedLevel
        )
    }

    public func setAutomaticExposure(enabled: Bool) throws -> AmcamControlSnapshot {
        controlLock.lock()
        defer { controlLock.unlock() }
        let activeHandle = try controlHandle()
        try sdk.setAutoExposure(activeHandle, enabled: enabled)
        let candidateRequestedExposure = enabled ? nil : requestedExposureMicroseconds
        let snapshot = try readControls(
            using: activeHandle,
            requestedExposure: candidateRequestedExposure,
            requestedFrameRate: requestedFrameRate,
            requestedSpeedLevel: requestedSpeedLevel
        )
        guard snapshot.exposure.automaticEnabled == enabled else {
            throw AmcamCameraError.controlReadbackMismatch(control: "automatic exposure", requested: enabled ? "on" : "off", actual: snapshot.exposure.automaticEnabled ? "on" : "off")
        }
        requestedExposureMicroseconds = candidateRequestedExposure
        return snapshot
    }

    public func setExposureTime(microseconds: UInt32) throws -> AmcamControlSnapshot {
        controlLock.lock()
        defer { controlLock.unlock() }
        let activeHandle = try controlHandle()
        let current = try sdk.readExposureTime(activeHandle)
        guard microseconds >= current.minimum, microseconds <= current.maximum else {
            throw AmcamCameraError.exposureOutOfRange(requested: microseconds, minimum: current.minimum, maximum: current.maximum)
        }
        let automaticExposureEnabled = try sdk.readAutoExposure(activeHandle)
        guard !automaticExposureEnabled else {
            throw AmcamCameraError.automaticExposureMustBeDisabled
        }
        try sdk.setExposureTime(activeHandle, microseconds: microseconds)
        let snapshot = try readControls(
            using: activeHandle,
            requestedExposure: microseconds,
            requestedFrameRate: requestedFrameRate,
            requestedSpeedLevel: requestedSpeedLevel
        )
        requestedExposureMicroseconds = microseconds
        return snapshot
    }

    public func setFixedFrameRate(framesPerSecond: Double) throws -> AmcamControlSnapshot {
        controlLock.lock()
        defer { controlLock.unlock() }
        let activeHandle = try controlHandle()
        guard modelFlags.map({ ($0 & AmcamSDK.preciseFrameRateFlag) != 0 }) == true else {
            throw AmcamCameraError.unsupportedControl("This camera model does not advertise precise fixed-frame-rate control.")
        }
        guard framesPerSecond.isFinite, framesPerSecond > 0 else {
            throw AmcamCameraError.invalidFrameRate(framesPerSecond)
        }

        let minimum = try sdk.readOption(activeHandle, option: AmcamSDK.optionMinimumPreciseFrameRate)
        let maximum = try sdk.readOption(activeHandle, option: AmcamSDK.optionMaximumPreciseFrameRate)
        guard minimum > 0, maximum >= minimum else {
            throw AmcamCameraError.unsupportedControl("The SDK did not report a valid precise frame-rate range.")
        }
        let scaledFramesPerSecond = framesPerSecond * 10.0
        let requestedTenthsValue = scaledFramesPerSecond.rounded()
        guard scaledFramesPerSecond.isFinite,
              requestedTenthsValue >= 1,
              requestedTenthsValue <= Double(Int32.max),
              abs(scaledFramesPerSecond - requestedTenthsValue) < 0.000_001 else {
            throw AmcamCameraError.invalidFrameRate(framesPerSecond)
        }
        let requestedTenths = Int32(requestedTenthsValue)
        guard requestedTenths >= minimum, requestedTenths <= maximum else {
            throw AmcamCameraError.frameRateOutOfRange(
                requested: framesPerSecond,
                minimum: Double(minimum) / 10.0,
                maximum: Double(maximum) / 10.0
            )
        }

        try sdk.setOption(activeHandle, option: AmcamSDK.optionPreciseFrameRate, value: requestedTenths)
        let candidateRequestedFrameRate = Double(requestedTenths) / 10.0
        let snapshot = try readControls(
            using: activeHandle,
            requestedExposure: requestedExposureMicroseconds,
            requestedFrameRate: candidateRequestedFrameRate,
            requestedSpeedLevel: nil
        )
        guard let readback = snapshot.frameRate.readbackFramesPerSecond,
              abs(readback - Double(requestedTenths) / 10.0) < 0.051 else {
            throw AmcamCameraError.controlReadbackMismatch(
                control: "fixed frame rate",
                requested: "\(Double(requestedTenths) / 10.0) FPS",
                actual: snapshot.frameRate.readbackFramesPerSecond.map { "\($0) FPS" } ?? "unavailable"
            )
        }
        requestedFrameRate = candidateRequestedFrameRate
        requestedSpeedLevel = nil
        return snapshot
    }

    public func setFrameRateSpeedLevel(_ level: Int) throws -> AmcamControlSnapshot {
        controlLock.lock()
        defer { controlLock.unlock() }
        let activeHandle = try controlHandle()
        guard let maximumSpeedLevel,
              maximumSpeedLevel >= 0,
              maximumSpeedLevel <= Int(UInt16.max) else {
            throw AmcamCameraError.unsupportedControl("The camera model does not report a discrete frame-speed range supported by the Amcam ABI.")
        }
        guard level >= 0, level <= maximumSpeedLevel else {
            throw AmcamCameraError.speedLevelOutOfRange(requested: level, minimum: 0, maximum: maximumSpeedLevel)
        }
        try sdk.setSpeedLevel(activeHandle, level: level)
        let snapshot = try readControls(
            using: activeHandle,
            requestedExposure: requestedExposureMicroseconds,
            requestedFrameRate: nil,
            requestedSpeedLevel: level
        )
        guard snapshot.frameRate.currentSpeedLevel == level else {
            throw AmcamCameraError.controlReadbackMismatch(
                control: "camera frame-speed level",
                requested: "\(level)",
                actual: snapshot.frameRate.currentSpeedLevel.map(String.init) ?? "unavailable"
            )
        }
        requestedFrameRate = nil
        requestedSpeedLevel = level
        return snapshot
    }

    private func controlHandle() throws -> UnsafeMutableRawPointer {
        lock.lock()
        defer { lock.unlock() }
        guard !starting, !stopping, let handle else {
            throw handle == nil ? AmcamCameraError.sessionClosed : AmcamCameraError.transitionInProgress
        }
        return handle
    }

    private func readControls(
        using handle: UnsafeMutableRawPointer,
        requestedExposure: UInt32?,
        requestedFrameRate: Double?,
        requestedSpeedLevel: Int?
    ) throws -> AmcamControlSnapshot {
        let automatic = try sdk.readAutoExposure(handle)
        let exposureReadback = try sdk.readExposureTime(handle)
        let exposure = AmcamExposureControl(
            automaticEnabled: automatic,
            readbackMicroseconds: exposureReadback.current,
            minimumMicroseconds: exposureReadback.minimum,
            maximumMicroseconds: exposureReadback.maximum,
            defaultMicroseconds: exposureReadback.defaultValue,
            requestedMicroseconds: requestedExposure
        )

        let preciseSupported = modelFlags.map { ($0 & AmcamSDK.preciseFrameRateFlag) != 0 } == true
        var minimumFPS: Double?
        var maximumFPS: Double?
        var readbackFPS: Double?
        var preciseFailure: String?

        if preciseSupported {
            do {
                let minimum = try sdk.readOption(handle, option: AmcamSDK.optionMinimumPreciseFrameRate)
                let maximum = try sdk.readOption(handle, option: AmcamSDK.optionMaximumPreciseFrameRate)
                let current = try sdk.readOption(handle, option: AmcamSDK.optionPreciseFrameRate)
                guard minimum > 0, maximum >= minimum, current >= minimum, current <= maximum else {
                    throw AmcamCameraError.unsupportedControl("The SDK returned an invalid precise frame-rate range or readback.")
                }
                minimumFPS = Double(minimum) / 10.0
                maximumFPS = Double(maximum) / 10.0
                readbackFPS = Double(current) / 10.0
            } catch {
                preciseFailure = "Precise frame-rate control is advertised, but the SDK query failed: \(error.localizedDescription)"
            }
        } else {
            preciseFailure = "This camera does not advertise precise fixed FPS; use its discrete frame-speed level instead."
        }

        let currentSpeed = try? sdk.readSpeedLevel(handle)
        let speedSupported = sdk.speedControlAvailable &&
            maximumSpeedLevel.map { $0 >= 0 && $0 <= Int(UInt16.max) } == true &&
            currentSpeed.map { value in
                guard let maximumSpeedLevel else { return false }
                return value >= 0 && value <= maximumSpeedLevel
            } == true
        let capabilityMessage: String?
        if !preciseSupported && !speedSupported {
            capabilityMessage = "This camera does not advertise precise fixed FPS and the loaded SDK does not expose a usable discrete frame-speed control."
        } else if !preciseSupported {
            capabilityMessage = "This camera does not advertise precise fixed FPS; use its discrete frame-speed level instead."
        } else {
            capabilityMessage = preciseFailure
        }
        let recentRate = sdk.readRecentFrameRate(handle)
        let frameRate = AmcamFrameRateControl(
            supported: preciseSupported && preciseFailure == nil,
            minimumFramesPerSecond: minimumFPS,
            maximumFramesPerSecond: maximumFPS,
            readbackFramesPerSecond: readbackFPS,
            requestedFramesPerSecond: requestedFrameRate,
            unsupportedReason: capabilityMessage,
            speedLevelSupported: speedSupported,
            currentSpeedLevel: currentSpeed,
            requestedSpeedLevel: requestedSpeedLevel,
            maximumSpeedLevel: speedSupported ? maximumSpeedLevel : nil,
            deviceMeasuredFramesPerSecond: recentRate?.framesPerSecond,
            deviceMeasuredFrameCount: recentRate?.frameCount,
            deviceMeasurementWindowMilliseconds: recentRate?.windowMilliseconds,
            deviceTotalFrameCount: recentRate?.totalFrameCount
        )
        return AmcamControlSnapshot(exposure: exposure, frameRate: frameRate)
    }

    private func handle(event: UInt32) {
        lock.lock()
        guard streaming, let handle, let buffer, let handler = frameHandler else {
            lock.unlock()
            return
        }

        if event == AmcamSDK.imageEvent {
            var info = AmcamFrameInfoV2()
            let result = sdk.pullImage(handle, buffer: buffer, frameInfo: &info)
            guard result >= 0 else {
                streaming = false
                lock.unlock()
                handler(.failure(.cameraReadbackFailed(operation: "Amcam_PullImageV2", code: result)))
                return
            }
            let frameWidth = Int(info.width)
            let frameHeight = Int(info.height)
            let (rowBytes, overflow1) = frameWidth.multipliedReportingOverflow(by: 3)
            let (byteCount, overflow2) = rowBytes.multipliedReportingOverflow(by: frameHeight)
            guard !overflow1, !overflow2, frameWidth == width, frameHeight == height,
                  rowBytes > 0, byteCount > 0, byteCount <= bufferCapacity else {
                streaming = false
                lock.unlock()
                handler(.failure(.invalidFrameDimensions))
                return
            }
            let frame = AmcamFrame(
                width: frameWidth,
                height: frameHeight,
                bytesPerRow: rowBytes,
                pixelFormat: .rgb24,
                bytes: Data(bytes: buffer, count: byteCount),
                sequence: (info.flag & AmcamSDK.frameSequenceFlag) != 0 ? info.seq : nil,
                deviceTimestampMicroseconds: (info.flag & AmcamSDK.frameTimestampFlag) != 0 ? info.timestamp : nil
            )
            lock.unlock()
            handler(.success(frame))
            return
        }

        if event == AmcamSDK.disconnectedEvent {
            streaming = false
            lock.unlock()
            handler(.failure(.cameraDisconnected))
            return
        }
        if event == AmcamSDK.errorEvent {
            streaming = false
            lock.unlock()
            handler(.failure(.cameraEventFailure(event)))
            return
        }
        lock.unlock()
    }
}
