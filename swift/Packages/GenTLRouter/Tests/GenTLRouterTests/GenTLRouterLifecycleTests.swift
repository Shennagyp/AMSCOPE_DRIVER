import Foundation
import XCTest
import GenTLABI
@_spi(BackendConvenience) import GenTLAPI
@testable import GenTLRouter

private struct CallCounts {
    var gcInit = 0
    var gcClose = 0
    var tlOpen = 0
    var tlClose = 0
    var tlUpdateInterfaces = 0
    var interfaceOpen = 0
    var interfaceClose = 0
    var interfaceUpdateDevices = 0
    var deviceClose = 0
    var bufferRevoke = 0
    var bufferQueue = 0
    var dataStreamClose = 0
    var acquisitionStop = 0
}

private final class RecordingGenTLAPI: GenTLAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = CallCounts()
    private let failSystemOpen: Bool
    private let failLibraryClose: Bool
    private let failDeviceClose: Bool

    private let systemToken = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    private let interfaceToken = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    let deviceToken = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    private let streamToken = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    private let eventToken = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    private let bufferToken = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    private var bufferMemory: UnsafeMutableRawPointer?
    private var eventDelivered = false
    private var queuedBufferCount = 0
    private var flushCountValue = 0
    private var failBufferRevoke = false
    private var queueBufferFailuresRemaining = 0
    private var forceEventTimeout = false

    init(
        failSystemOpen: Bool = false,
        failLibraryClose: Bool = false,
        failDeviceClose: Bool = false
    ) {
        self.failSystemOpen = failSystemOpen
        self.failLibraryClose = failLibraryClose
        self.failDeviceClose = failDeviceClose
    }

    deinit {
        systemToken.deallocate()
        interfaceToken.deallocate()
        deviceToken.deallocate()
        streamToken.deallocate()
        eventToken.deallocate()
        bufferToken.deallocate()
        bufferMemory?.deallocate()
    }

    private func record(_ update: (inout CallCounts) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        update(&calls)
    }

    func snapshot() -> CallCounts {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    private func writeCString(
        _ value: String,
        output: UnsafeMutablePointer<CChar>?,
        size: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard let size else { return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER) }
        let bytes = value.utf8CString
        let capacity = size.pointee
        size.pointee = bytes.count
        guard let output else { return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS) }
        guard capacity >= bytes.count else { return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_BUFFER_TOO_SMALL) }
        for (index, byte) in bytes.enumerated() {
            output[index] = byte
        }
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func GCInitLib() -> GenTLABI.GC_ERROR {
        record { $0.gcInit += 1 }
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func GCCloseLib() -> GenTLABI.GC_ERROR {
        record { $0.gcClose += 1 }
        return failLibraryClose ? GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_RESOURCE_IN_USE) : GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func TLOpen(_ phTL: UnsafeMutablePointer<GenTLABI.TL_HANDLE?>?) -> GenTLABI.GC_ERROR {
        record { $0.tlOpen += 1 }
        guard let phTL else { return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER) }
        if failSystemOpen {
            phTL.pointee = nil
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_ERROR)
        }
        phTL.pointee = systemToken
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func TLClose(_ hTL: GenTLABI.TL_HANDLE) -> GenTLABI.GC_ERROR {
        record { $0.tlClose += 1 }
        return hTL == systemToken ? GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS) : GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE)
    }

    func TLUpdateInterfaceList(
        _ hTL: GenTLABI.TL_HANDLE,
        _ pbChanged: UnsafeMutablePointer<GenTLABI.bool8_t>?,
        _ iTimeout: UInt64
    ) -> GenTLABI.GC_ERROR {
        record { $0.tlUpdateInterfaces += 1 }
        guard hTL == systemToken else { return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE) }
        pbChanged?.pointee = 0
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func TLGetNumInterfaces(
        _ hTL: GenTLABI.TL_HANDLE,
        _ piNumIfaces: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        guard hTL == systemToken, let piNumIfaces else { return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER) }
        piNumIfaces.pointee = 1
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func TLGetInterfaceID(
        _ hTL: GenTLABI.TL_HANDLE,
        _ iIndex: UInt32,
        _ sID: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard hTL == systemToken, iIndex == 0 else { return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_INDEX) }
        return writeCString("interface-0", output: sID, size: piSize)
    }

    func TLOpenInterface(
        _ hTL: GenTLABI.TL_HANDLE,
        _ sIfaceID: UnsafePointer<CChar>?,
        _ phIface: UnsafeMutablePointer<GenTLABI.IF_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        guard hTL == systemToken, let sIfaceID, let phIface,
              String(cString: sIfaceID) == "interface-0" else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_ID)
        }
        record { $0.interfaceOpen += 1 }
        phIface.pointee = interfaceToken
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func IFClose(_ hIface: GenTLABI.IF_HANDLE) -> GenTLABI.GC_ERROR {
        record { $0.interfaceClose += 1 }
        return hIface == interfaceToken ? GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS) : GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE)
    }

    func IFUpdateDeviceList(
        _ hIface: GenTLABI.IF_HANDLE,
        _ pbChanged: UnsafeMutablePointer<GenTLABI.bool8_t>?,
        _ iTimeout: UInt64
    ) -> GenTLABI.GC_ERROR {
        record { $0.interfaceUpdateDevices += 1 }
        guard hIface == interfaceToken else { return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE) }
        pbChanged?.pointee = 0
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func IFGetNumDevices(
        _ hIface: GenTLABI.IF_HANDLE,
        _ piNumDevices: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        guard hIface == interfaceToken, let piNumDevices else { return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER) }
        piNumDevices.pointee = 1
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func IFGetDeviceID(
        _ hIface: GenTLABI.IF_HANDLE,
        _ iIndex: UInt32,
        _ sDeviceID: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard hIface == interfaceToken, iIndex == 0 else { return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_INDEX) }
        return writeCString("camera-0", output: sDeviceID, size: piSize)
    }

    func IFOpenDevice(
        _ hIface: GenTLABI.IF_HANDLE,
        _ sDeviceID: UnsafePointer<CChar>?,
        _ iOpenFlag: GenTLABI.DEVICE_ACCESS_FLAGS,
        _ phDevice: UnsafeMutablePointer<GenTLABI.DEV_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        guard hIface == interfaceToken, let sDeviceID, let phDevice,
              String(cString: sDeviceID) == "camera-0" else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_ID)
        }
        guard iOpenFlag == 4 else { return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_ACCESS_DENIED) }
        phDevice.pointee = deviceToken
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }


    private func writeInfo<T>(
        _ value: T,
        dataType: Int32,
        type: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        output: UnsafeMutableRawPointer?,
        size: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard let type, let size else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER)
        }
        let required = MemoryLayout<T>.size
        let capacity = size.pointee
        type.pointee = dataType
        size.pointee = required
        guard let output, capacity >= required else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_BUFFER_TOO_SMALL)
        }
        withUnsafeBytes(of: value) { source in
            if let base = source.baseAddress {
                output.copyMemory(from: base, byteCount: required)
            }
        }
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func queuedBuffers() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return queuedBufferCount
    }

    func setForceEventTimeout(_ value: Bool) {
        lock.lock()
        forceEventTimeout = value
        lock.unlock()
    }

    func setBufferPixels(_ pixels: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        guard pixels.count == 6, let bufferMemory else { return }
        pixels.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            bufferMemory.copyMemory(from: base, byteCount: source.count)
        }
    }

    func setFailBufferRevoke(_ value: Bool) {
        lock.lock()
        failBufferRevoke = value
        lock.unlock()
    }

    func setQueueBufferFailures(_ count: Int) {
        lock.lock()
        queueBufferFailuresRemaining = max(0, count)
        lock.unlock()
    }

    func flushCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return flushCountValue
    }

    func DevGetNumDataStreams(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ piNumDataStreams: UnsafeMutablePointer<UInt32>?
    ) -> GenTLABI.GC_ERROR {
        guard hDevice == deviceToken, let piNumDataStreams else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER)
        }
        piNumDataStreams.pointee = 1
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func DevGetDataStreamID(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ iIndex: UInt32,
        _ sDataStreamID: UnsafeMutablePointer<CChar>?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard hDevice == deviceToken, iIndex == 0 else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_INDEX)
        }
        return writeCString("stream-0", output: sDataStreamID, size: piSize)
    }

    func DevOpenDataStream(
        _ hDevice: GenTLABI.DEV_HANDLE,
        _ sDataStreamID: UnsafePointer<CChar>?,
        _ phDataStream: UnsafeMutablePointer<GenTLABI.DS_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        guard hDevice == deviceToken, let sDataStreamID, let phDataStream,
              String(cString: sDataStreamID) == "stream-0" else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_ID)
        }
        phDataStream.pointee = streamToken
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func DSGetInfo(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iInfoCmd: GenTLABI.STREAM_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard hDataStream == streamToken,
              iInfoCmd == GenTLInfoCommand.Stream.payloadSize.rawValue else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER)
        }
        return writeInfo(
            6,
            dataType: Int32(GenTLABI.INFO_DATATYPE_SIZET.rawValue),
            type: piType,
            output: pBuffer,
            size: piSize
        )
    }

    func GCRegisterEvent(
        _ hEventSrc: GenTLABI.EVENTSRC_HANDLE,
        _ iEventID: GenTLABI.EVENT_TYPE,
        _ phEvent: UnsafeMutablePointer<GenTLABI.EVENT_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        guard hEventSrc == streamToken, iEventID == 1, let phEvent else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER)
        }
        phEvent.pointee = eventToken
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func GCUnregisterEvent(
        _ hEventSrc: GenTLABI.EVENTSRC_HANDLE,
        _ iEventID: GenTLABI.EVENT_TYPE
    ) -> GenTLABI.GC_ERROR {
        guard hEventSrc == streamToken, iEventID == 1 else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER)
        }
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func DSAllocAndAnnounceBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iSize: Int,
        _ pPrivate: UnsafeMutableRawPointer?,
        _ phBuffer: UnsafeMutablePointer<GenTLABI.BUFFER_HANDLE?>?
    ) -> GenTLABI.GC_ERROR {
        guard hDataStream == streamToken, iSize == 6, let phBuffer else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER)
        }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: iSize, alignment: 8)
        let pixels: [UInt8] = [1, 2, 3, 4, 5, 6]
        pixels.withUnsafeBytes { source in
            if let base = source.baseAddress {
                memory.copyMemory(from: base, byteCount: source.count)
            }
        }
        bufferMemory = memory
        phBuffer.pointee = bufferToken
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func DSQueueBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE
    ) -> GenTLABI.GC_ERROR {
        guard hDataStream == streamToken, hBuffer == bufferToken else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE)
        }
        lock.lock()
        calls.bufferQueue += 1
        if queueBufferFailuresRemaining > 0 {
            queueBufferFailuresRemaining -= 1
            lock.unlock()
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_ERROR)
        }
        queuedBufferCount += 1
        eventDelivered = false
        lock.unlock()
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func DSStartAcquisition(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iStartFlags: GenTLABI.ACQ_START_FLAGS,
        _ iNumToAcquire: UInt64
    ) -> GenTLABI.GC_ERROR {
        guard hDataStream == streamToken, iStartFlags == 0, iNumToAcquire > 0 else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER)
        }
        eventDelivered = false
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func EventGetData(
        _ hEvent: GenTLABI.EVENT_HANDLE,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?,
        _ iTimeout: UInt64
    ) -> GenTLABI.GC_ERROR {
        guard hEvent == eventToken, let pBuffer, let piSize,
              piSize.pointee >= 2 * MemoryLayout<UInt>.size else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER)
        }
        lock.lock()
        let shouldTimeout = forceEventTimeout || eventDelivered
        lock.unlock()
        guard !shouldTimeout else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_TIMEOUT)
        }
        var words = [UInt(UInt(bitPattern: bufferToken)), 0]
        words.withUnsafeBytes { source in
            if let base = source.baseAddress {
                pBuffer.copyMemory(from: base, byteCount: source.count)
            }
        }
        piSize.pointee = words.count * MemoryLayout<UInt>.size
        lock.lock()
        eventDelivered = true
        lock.unlock()
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func DSGetBufferInfo(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ iInfoCmd: GenTLABI.BUFFER_INFO_CMD,
        _ piType: UnsafeMutablePointer<GenTLABI.INFO_DATATYPE>?,
        _ pBuffer: UnsafeMutableRawPointer?,
        _ piSize: UnsafeMutablePointer<Int>?
    ) -> GenTLABI.GC_ERROR {
        guard hDataStream == streamToken, hBuffer == bufferToken, let memory = bufferMemory else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE)
        }
        let sizeType = Int32(GenTLABI.INFO_DATATYPE_SIZET.rawValue)
        let uint64Type = Int32(GenTLABI.INFO_DATATYPE_UINT64.rawValue)
        let boolType = Int32(GenTLABI.INFO_DATATYPE_BOOL8.rawValue)
        switch iInfoCmd {
        case GenTLInfoCommand.Buffer.base.rawValue:
            var pointer: UnsafeMutableRawPointer? = memory
            return writeInfo(pointer, dataType: Int32(GenTLABI.INFO_DATATYPE_PTR.rawValue),
                             type: piType, output: pBuffer, size: piSize)
        case GenTLInfoCommand.Buffer.width.rawValue,
             GenTLInfoCommand.Buffer.height.rawValue,
             GenTLInfoCommand.Buffer.size.rawValue,
             GenTLInfoCommand.Buffer.sizeFilled.rawValue,
             GenTLInfoCommand.Buffer.dataSize.rawValue,
             GenTLInfoCommand.Buffer.xPadding.rawValue:
            let value: Int
            switch iInfoCmd {
            case GenTLInfoCommand.Buffer.width.rawValue: value = 2
            case GenTLInfoCommand.Buffer.height.rawValue: value = 1
            case GenTLInfoCommand.Buffer.size.rawValue: value = 6
            case GenTLInfoCommand.Buffer.sizeFilled.rawValue: value = 6
            case GenTLInfoCommand.Buffer.dataSize.rawValue: value = 6
            default: value = 0
            }
            return writeInfo(value, dataType: sizeType, type: piType, output: pBuffer, size: piSize)
        case GenTLInfoCommand.Buffer.pixelFormat.rawValue,
             GenTLInfoCommand.Buffer.pixelFormatNamespace.rawValue,
             GenTLInfoCommand.Buffer.frameID.rawValue,
             GenTLInfoCommand.Buffer.timestamp.rawValue:
            let value: UInt64
            switch iInfoCmd {
            case GenTLInfoCommand.Buffer.pixelFormat.rawValue: value = 0x02180014
            case GenTLInfoCommand.Buffer.pixelFormatNamespace.rawValue: value = 4
            case GenTLInfoCommand.Buffer.frameID.rawValue: value = 7
            default: value = 99
            }
            return writeInfo(value, dataType: uint64Type, type: piType, output: pBuffer, size: piSize)
        case GenTLInfoCommand.Buffer.isIncomplete.rawValue,
             GenTLInfoCommand.Buffer.imagePresent.rawValue:
            let value: UInt8 = iInfoCmd == GenTLInfoCommand.Buffer.isIncomplete.rawValue ? 0 : 1
            return writeInfo(value, dataType: boolType, type: piType, output: pBuffer, size: piSize)
        default:
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER)
        }
    }

    func EventKill(_ hEvent: GenTLABI.EVENT_HANDLE) -> GenTLABI.GC_ERROR {
        return hEvent == eventToken
            ? GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
            : GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE)
    }

    func DSStopAcquisition(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iStopFlags: GenTLABI.ACQ_STOP_FLAGS
    ) -> GenTLABI.GC_ERROR {
        record { $0.acquisitionStop += 1 }
        return hDataStream == streamToken && iStopFlags == 0
            ? GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
            : GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER)
    }

    func DSFlushQueue(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ iOperation: GenTLABI.ACQ_QUEUE_TYPE
    ) -> GenTLABI.GC_ERROR {
        guard hDataStream == streamToken, iOperation == 2 else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_PARAMETER)
        }
        lock.lock()
        flushCountValue += 1
        lock.unlock()
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func DSRevokeBuffer(
        _ hDataStream: GenTLABI.DS_HANDLE,
        _ hBuffer: GenTLABI.BUFFER_HANDLE,
        _ ppBuffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
        _ ppPrivate: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    ) -> GenTLABI.GC_ERROR {
        guard hDataStream == streamToken, hBuffer == bufferToken else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE)
        }
        lock.lock()
        calls.bufferRevoke += 1
        let shouldFail = failBufferRevoke
        lock.unlock()
        if shouldFail {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_RESOURCE_IN_USE)
        }
        if let ppBuffer { ppBuffer.pointee = bufferMemory }
        if let ppPrivate { ppPrivate.pointee = nil }
        bufferMemory?.deallocate()
        bufferMemory = nil
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func DSClose(_ hDataStream: GenTLABI.DS_HANDLE) -> GenTLABI.GC_ERROR {
        guard hDataStream == streamToken else {
            return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE)
        }
        record { $0.dataStreamClose += 1 }
        return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }

    func DevClose(_ hDevice: GenTLABI.DEV_HANDLE) -> GenTLABI.GC_ERROR {
        record { $0.deviceClose += 1 }
        guard hDevice == deviceToken else { return GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_INVALID_HANDLE) }
        return failDeviceClose ? GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_RESOURCE_IN_USE) : GenTLABI.GenTLABI_ErrorFromCode(GenTLABI.GC_ERR_SUCCESS)
    }
}

final class GenTLRouterLifecycleTests: XCTestCase {
    func testDeviceSessionForwardsTypedFeatureAccessToItsOwningBackend() throws {
        let api = RecordingGenTLAPI()
        let router = GenTLRouter()
        try router.register(backendID: "feature-backend") { api }

        let report = router.discover()
        let candidate = try XCTUnwrap(report.devices.first)
        let session = try candidate.open(access: .exclusive)
        defer { try? session.close() }

        XCTAssertTrue(session.supportsFeatureAccess)
        XCTAssertEqual(
            try session.featureDescriptors().map(\.name),
            ["MockFeature"]
        )
        XCTAssertEqual(try session.readFeature("MockFeature"), .integer(42))
        try session.writeFeature(.integer(84), named: "MockFeature")
        try session.close()

        XCTAssertThrowsError(try session.featureDescriptors()) { error in
            guard case GenTLRouterError.deviceSessionClosed("feature-backend") = error else {
                return XCTFail("Expected a closed-session error, received \(error)")
            }
        }
    }


    func testGenTLAcquisitionSessionCopiesNewBufferFramesAndRequeuesBuffers() throws {
        let api = RecordingGenTLAPI()
        let router = GenTLRouter()
        try router.register(backendID: "acquisition-backend") { api }
        let candidate = try XCTUnwrap(router.discover().devices.first)
        let device = try candidate.open(access: .exclusive)
        let acquisition = try GenTLAcquisitionSession(device: device, bufferCount: 1)
        defer {
            try? acquisition.close()
            try? device.close()
        }

        try acquisition.start(numberToAcquire: 1)
        XCTAssertEqual(api.flushCount(), 1, "Start must discard stale output events before acquisition.")
        let frame = try acquisition.nextFrame(timeoutMilliseconds: 100)

        XCTAssertEqual(frame.width, 2)
        XCTAssertEqual(frame.height, 1)
        XCTAssertEqual(frame.pixelFormat, 0x02180014)
        XCTAssertEqual(frame.pixelFormatNamespace, 4)
        XCTAssertEqual(frame.sequence, 7)
        XCTAssertEqual(frame.timestamp, 99)
        XCTAssertEqual(frame.bytes, Data([1, 2, 3, 4, 5, 6]))
        XCTAssertFalse(frame.isIncomplete)
        XCTAssertEqual(api.queuedBuffers(), 2)

        try acquisition.stop()
        XCTAssertEqual(api.flushCount(), 2, "Stop must return outstanding buffers to the input pool.")
        try acquisition.close()
        XCTAssertEqual(api.flushCount(), 3, "Close must flush before revoking announced buffers.")
        try device.close()
    }



    func testReusedAnnouncedBufferDoesNotMutatePreviouslyDeliveredFrame() throws {
        let api = RecordingGenTLAPI()
        let router = GenTLRouter()
        try router.register(backendID: "reused-buffer-copy") { api }
        let candidate = try XCTUnwrap(router.discover().devices.first)
        let device = try candidate.open(access: .exclusive)
        let acquisition = try GenTLAcquisitionSession(device: device, bufferCount: 1)
        defer {
            try? acquisition.close()
            try? device.close()
        }

        try acquisition.start(numberToAcquire: 2)
        let firstFrame = try acquisition.nextFrame(timeoutMilliseconds: 100)
        api.setBufferPixels([9, 8, 7, 6, 5, 4])
        let secondFrame = try acquisition.nextFrame(timeoutMilliseconds: 100)

        XCTAssertEqual(firstFrame.bytes, Data([1, 2, 3, 4, 5, 6]))
        XCTAssertEqual(secondFrame.bytes, Data([9, 8, 7, 6, 5, 4]))
        XCTAssertEqual(api.queuedBuffers(), 3, "The single announced buffer is requeued after each copied frame.")
        try acquisition.stop()
    }

    func testFailedBufferRequeueIsNotRetriedWithSameHandle() throws {
        let api = RecordingGenTLAPI()
        let router = GenTLRouter()
        try router.register(backendID: "buffer-requeue-failure") { api }
        let candidate = try XCTUnwrap(router.discover().devices.first)
        let device = try candidate.open(access: .exclusive)
        let acquisition = try GenTLAcquisitionSession(device: device, bufferCount: 1)
        defer {
            try? acquisition.close()
            try? device.close()
        }

        try acquisition.start(numberToAcquire: 1)
        api.setQueueBufferFailures(1)

        XCTAssertThrowsError(try acquisition.nextFrame(timeoutMilliseconds: 100)) { error in
            guard case GenTLAcquisitionError.genTLCallFailed(let operation, _) = error else {
                return XCTFail("Expected DSQueueBuffer failure, received \\(error)")
            }
            XCTAssertEqual(operation, "DSQueueBuffer")
        }

        XCTAssertEqual(api.snapshot().bufferQueue, 2, "One initial enqueue and one failed return attempt are expected.")
        XCTAssertEqual(api.queuedBuffers(), 1, "A failed return must not be retried and double-enqueue the handle.")
    }

    func testConcurrentStopExecutesProducerStopExactlyOnce() throws {
        let api = RecordingGenTLAPI()
        let router = GenTLRouter()
        try router.register(backendID: "concurrent-stop") { api }
        let candidate = try XCTUnwrap(router.discover().devices.first)
        let device = try candidate.open(access: .exclusive)
        let acquisition = try GenTLAcquisitionSession(device: device, bufferCount: 1)
        try acquisition.start()

        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            do {
                try acquisition.stop()
            } catch {
                XCTFail("Concurrent stop failed: \\(error)")
            }
        }

        XCTAssertEqual(api.snapshot().acquisitionStop, 1)
        try acquisition.close()
        try device.close()
    }

    func testConcurrentCloseReleasesStreamResourcesExactlyOnce() throws {
        let api = RecordingGenTLAPI()
        let router = GenTLRouter()
        try router.register(backendID: "concurrent-close") { api }
        let candidate = try XCTUnwrap(router.discover().devices.first)
        let device = try candidate.open(access: .exclusive)
        let acquisition = try GenTLAcquisitionSession(device: device, bufferCount: 1)
        try acquisition.start()

        DispatchQueue.concurrentPerform(iterations: 4) { _ in
            do {
                try acquisition.close()
            } catch {
                XCTFail("Concurrent close failed: \\(error)")
            }
        }

        XCTAssertEqual(api.snapshot().acquisitionStop, 1)
        XCTAssertEqual(api.snapshot().bufferRevoke, 1)
        XCTAssertEqual(api.snapshot().dataStreamClose, 1)
        try device.close()
    }

    func testEventTimeoutDoesNotPoisonAcquisitionSession() throws {
        let api = RecordingGenTLAPI()
        let router = GenTLRouter()
        try router.register(backendID: "event-timeout") { api }
        let candidate = try XCTUnwrap(router.discover().devices.first)
        let device = try candidate.open(access: .exclusive)
        let acquisition = try GenTLAcquisitionSession(device: device, bufferCount: 1)
        defer {
            try? acquisition.close()
            try? device.close()
        }

        try acquisition.start(numberToAcquire: 1)
        api.setForceEventTimeout(true)
        XCTAssertThrowsError(try acquisition.nextFrame(timeoutMilliseconds: 1)) { error in
            XCTAssertEqual(error as? GenTLAcquisitionError, .eventTimeout)
        }

        api.setForceEventTimeout(false)
        let frame = try acquisition.nextFrame(timeoutMilliseconds: 100)
        XCTAssertEqual(frame.bytes, Data([1, 2, 3, 4, 5, 6]))
        try acquisition.stop()
    }

    func testAcquisitionCloseRetainsOwnershipWhenBufferRevokeFailsAndCanRetry() throws {
        let api = RecordingGenTLAPI()
        let router = GenTLRouter()
        try router.register(backendID: "retryable-acquisition-close") { api }
        let candidate = try XCTUnwrap(router.discover().devices.first)
        let device = try candidate.open(access: .exclusive)
        let acquisition = try GenTLAcquisitionSession(device: device, bufferCount: 1)
        api.setFailBufferRevoke(true)

        XCTAssertThrowsError(try acquisition.close())
        XCTAssertEqual(api.snapshot().bufferRevoke, 1)
        XCTAssertEqual(api.snapshot().dataStreamClose, 0)

        api.setFailBufferRevoke(false)
        try acquisition.close()
        XCTAssertEqual(api.snapshot().bufferRevoke, 2)
        XCTAssertEqual(api.snapshot().dataStreamClose, 1)
        try device.close()
    }

    func testSuccessfulInitializationRollbackAllowsRetry() throws {
        let api = RecordingGenTLAPI(failSystemOpen: true)
        let router = GenTLRouter()
        try router.register(backendID: "retry-after-cleanup") { api }

        let first = router.discover()
        XCTAssertEqual(first.failures.count, 1)

        let second = router.discover()
        XCTAssertEqual(second.failures.count, 1)

        let calls = api.snapshot()
        XCTAssertEqual(calls.gcInit, 2)
        XCTAssertEqual(calls.tlOpen, 2)
        XCTAssertEqual(calls.gcClose, 2)
    }

    func testFailedDeviceCloseAbandonsAndQuarantinesProviderContext() throws {
        let api = RecordingGenTLAPI(failDeviceClose: true)
        let router = GenTLRouter()
        try router.register(backendID: "device-close-failure") { api }

        var candidate: GenTLDeviceCandidate?
        do {
            let report = router.discover()
            XCTAssertTrue(report.failures.isEmpty)
            candidate = try XCTUnwrap(report.devices.first)
        }

        var session: GenTLDeviceSession? = try XCTUnwrap(candidate).open(
            accessFlags: GenTLDeviceAccess.exclusive.rawValue
        )
        XCTAssertThrowsError(try XCTUnwrap(session).close())

        // Releasing a session whose native close failed abandons the context.
        session = nil
        candidate = nil

        let subsequent = router.discover()
        XCTAssertEqual(subsequent.devices.count, 0)
        XCTAssertEqual(subsequent.failures.count, 1)

        let calls = api.snapshot()
        XCTAssertEqual(calls.gcInit, 1)
        XCTAssertEqual(calls.tlOpen, 1)
        XCTAssertGreaterThanOrEqual(calls.deviceClose, 2)
    }

    func testFailedInitializationCleanupQuarantinesBackend() throws {
        let api = RecordingGenTLAPI(failSystemOpen: true, failLibraryClose: true)
        let router = GenTLRouter()
        try router.register(backendID: "partial-init") { api }

        let first = router.discover()
        XCTAssertEqual(first.devices.count, 0)
        XCTAssertEqual(first.failures.count, 1)

        let second = router.discover()
        XCTAssertEqual(second.devices.count, 0)
        XCTAssertEqual(second.failures.count, 1)

        // GCInitLib is the observable proof that the API factory was not
        // invoked for a second producer instance.
        let calls = api.snapshot()
        XCTAssertEqual(calls.gcInit, 1)
        XCTAssertEqual(calls.tlOpen, 1)
        XCTAssertEqual(calls.gcClose, 1)
    }

    func testNativeProducerSymlinkAliasesCannotRegisterTwice() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GenTLRouterProducerIdentity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let producer = root.appendingPathComponent("camera.cti")
        let alias = root.appendingPathComponent("camera-alias.cti")
        XCTAssertTrue(FileManager.default.createFile(atPath: producer.path, contents: Data()))
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: producer)

        let router = GenTLRouter()
        try router.registerNativeProducer(backendID: "primary", ctiURL: producer)

        XCTAssertThrowsError(
            try router.registerNativeProducer(backendID: "alias", ctiURL: alias)
        ) { error in
            guard case GenTLRouterError.duplicateBackendResource(let existingID) = error else {
                return XCTFail("Expected duplicate backend resource, received \(error)")
            }
            XCTAssertEqual(existingID, "primary")
        }
    }

    func testRepeatedDiscoveryReusesOneProducerSystemAndInterface() throws {
        let api = RecordingGenTLAPI()

        func discoverTwiceAndOpenDevice() throws {
            let router = GenTLRouter()
            try router.register(backendID: "recording") { api }

            let first = router.discover()
            XCTAssertTrue(first.failures.isEmpty)
            XCTAssertEqual(first.devices.count, 1)

            let second = router.discover()
            XCTAssertTrue(second.failures.isEmpty)
            XCTAssertEqual(second.devices.count, 1)

            let firstCandidate = try XCTUnwrap(first.devices.first)
            let secondCandidate = try XCTUnwrap(second.devices.first)

            XCTAssertEqual(firstCandidate.id, secondCandidate.id)
            XCTAssertEqual(firstCandidate.interfaceHandle, secondCandidate.interfaceHandle)
            XCTAssertTrue(
                (firstCandidate.api as AnyObject) === (secondCandidate.api as AnyObject)
            )

            let session = try firstCandidate.open(
                accessFlags: GenTLDeviceAccess.exclusive.rawValue
            )
            XCTAssertEqual(session.deviceHandle, api.deviceToken)
            try session.close()

            let activeCounts = api.snapshot()
            XCTAssertEqual(activeCounts.gcInit, 1)
            XCTAssertEqual(activeCounts.tlOpen, 1)
            XCTAssertEqual(activeCounts.interfaceOpen, 1)
            XCTAssertEqual(activeCounts.tlUpdateInterfaces, 2)
            XCTAssertEqual(activeCounts.interfaceUpdateDevices, 2)
            XCTAssertEqual(activeCounts.deviceClose, 1)
            XCTAssertEqual(activeCounts.interfaceClose, 0)
            XCTAssertEqual(activeCounts.tlClose, 0)
            XCTAssertEqual(activeCounts.gcClose, 0)
        }

        try discoverTwiceAndOpenDevice()

        // The router, both discovery reports, and the opened session have now
        // released their context. Its module hierarchy must close exactly once.
        let finalCounts = api.snapshot()
        XCTAssertEqual(finalCounts.interfaceClose, 1)
        XCTAssertEqual(finalCounts.tlClose, 1)
        XCTAssertEqual(finalCounts.gcClose, 1)
    }
}


extension RecordingGenTLAPI: GenTLFeatureAccess {
    func featureDescriptors(for device: GenTLFeatureDeviceHandle) throws -> [GenTLFeatureDescriptor] {
        guard device.rawValue == UInt(bitPattern: deviceToken) else {
            throw GenTLFeatureAccessError.featureUnavailable("wrong-device-handle")
        }
        return [
            GenTLFeatureDescriptor(
                name: "MockFeature",
                displayName: "Mock Feature",
                kind: .integer,
                isAvailable: true,
                isReadable: true,
                isWritable: true
            )
        ]
    }

    func readFeature(_ name: String, from device: GenTLFeatureDeviceHandle) throws -> GenTLFeatureValue {
        guard name == "MockFeature", device.rawValue == UInt(bitPattern: deviceToken) else {
            throw GenTLFeatureAccessError.featureNotFound(name)
        }
        return .integer(42)
    }

    func writeFeature(
        _ value: GenTLFeatureValue,
        named name: String,
        to device: GenTLFeatureDeviceHandle
    ) throws {
        guard name == "MockFeature", device.rawValue == UInt(bitPattern: deviceToken),
              value.kind == .integer else {
            throw GenTLFeatureAccessError.invalidValue(name)
        }
    }
}
