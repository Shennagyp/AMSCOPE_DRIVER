import XCTest
@_spi(BackendConvenience) @testable import GenTLAPI

private struct EmptyRawGenTLAPI: GenTLAPI {}

final class GenTLAPITests: XCTestCase {
    func testGenTLVersionAndInfiniteConstantsMatchTheStandard() {
        XCTAssertEqual(GenTLVersion.v1_6.major, 1)
        XCTAssertEqual(GenTLVersion.v1_6.minor, 6)
        XCTAssertEqual(GenTLConstants.infiniteTimeout, UInt64.max)
        XCTAssertEqual(GenTLConstants.infiniteCount, UInt64.max)
        XCTAssertEqual(GenTLConstants.invalidHandle, 0)
    }

    func testModuleHandlesRemainDistinctTypes() {
        let system = TL_HANDLE(rawValue: 7)
        let interface = IF_HANDLE(rawValue: 7)
        let device = DEV_HANDLE(rawValue: 7)

        XCTAssertEqual(system.rawValue, interface.rawValue)
        XCTAssertEqual(interface.rawValue, device.rawValue)
        XCTAssertTrue(system.isValid)
        XCTAssertFalse(TL_HANDLE(rawValue: GenTLConstants.invalidHandle).isValid)
    }

    func testInfoValuesPreserveNativeGenTLTypes() {
        XCTAssertNotEqual(GenTLInfoValue.size(8), .uint64(8))
        XCTAssertNotEqual(GenTLInfoValue.pointerDifference(-1), .int64(-1))
        XCTAssertEqual(GenTLInfoValue.bool8(true), .bool8(true))
        XCTAssertEqual(GenTLInfoValue.pointer(0x1234), .pointer(0x1234))
    }

    func testStandardEventAndQueueIdentifiers() {
        XCTAssertEqual(GenTLEventType.error.rawValue, 0)
        XCTAssertEqual(GenTLEventType.newBuffer.rawValue, 1)
        XCTAssertEqual(GenTLEventType.featureInvalidate.rawValue, 2)
        XCTAssertEqual(GenTLQueueOperation.inputToOutput.rawValue, 0)
        XCTAssertEqual(GenTLQueueOperation.allDiscard.rawValue, 4)
        XCTAssertEqual(GenTLDeviceAccess.exclusive.rawValue, 4)
        XCTAssertEqual(GenTLDeviceAccessStatus.unknown.rawValue, 0)
        XCTAssertEqual(GenTLDeviceAccessStatus.readWrite.rawValue, 1)
        XCTAssertEqual(GenTLDeviceAccessStatus.readOnly.rawValue, 2)
        XCTAssertEqual(GenTLDeviceAccessStatus.noAccess.rawValue, 3)
        XCTAssertEqual(GenTLDeviceAccessStatus.busy.rawValue, 4)
        XCTAssertEqual(GenTLDeviceAccessStatus.openReadWrite.rawValue, 5)
        XCTAssertEqual(GenTLDeviceAccessStatus.openReadOnly.rawValue, 6)
    }

    func testInfoDataTypeIdentifiersMatchGenTL16() {
        XCTAssertEqual(GenTLInfoDataType.unknown.rawValue, 0)
        XCTAssertEqual(GenTLInfoDataType.bool8.rawValue, 11)
        XCTAssertEqual(GenTLInfoDataType.size.rawValue, 12)
        XCTAssertEqual(GenTLInfoDataType.buffer.rawValue, 13)
        XCTAssertEqual(GenTLInfoDataType.pointerDifference.rawValue, 14)
    }

    func testStandardGenTLValueEnumsMatchHeader() {
        XCTAssertEqual(GenTLCharacterEncoding.ascii.rawValue, 0)
        XCTAssertEqual(GenTLCharacterEncoding.utf8.rawValue, 1)

        XCTAssertEqual(GenTLPayloadType.image.rawValue, 1)
        XCTAssertEqual(GenTLPayloadType.multiPart.rawValue, 10)
        XCTAssertEqual(GenTLPayloadType.genDC.rawValue, 11)

        XCTAssertEqual(GenTLPixelFormatNamespace.gev.rawValue, 1)
        XCTAssertEqual(GenTLPixelFormatNamespace.pfnc16Bit.rawValue, 3)
        XCTAssertEqual(GenTLPixelFormatNamespace.pfnc32Bit.rawValue, 4)

        XCTAssertEqual(GenTLPixelEndianness.unknown.rawValue, 0)
        XCTAssertEqual(GenTLPixelEndianness.little.rawValue, 1)
        XCTAssertEqual(GenTLPixelEndianness.big.rawValue, 2)

        XCTAssertEqual(GenTLPartDataType.image2D.rawValue, 1)
        XCTAssertEqual(GenTLPartDataType.confidenceMap.rawValue, 9)
        XCTAssertEqual(GenTLPartDataType.jpeg2000.rawValue, 11)

        XCTAssertEqual(GenTLURLScheme.local.rawValue, 0)
        XCTAssertEqual(GenTLURLScheme.http.rawValue, 1)
        XCTAssertEqual(GenTLURLScheme.file.rawValue, 2)

        XCTAssertEqual(GenTLAcquisitionStartFlag.normal.rawValue, 0)
        XCTAssertEqual(GenTLAcquisitionStopFlag.normal.rawValue, 0)
        XCTAssertEqual(GenTLAcquisitionStopFlag.kill.rawValue, 1)
    }

    func testInfoCommandIdentifiersMatchGenTL16() {
        XCTAssertEqual(GenTLInfoCommand.TransportLayer.charEncoding.rawValue, 8)
        XCTAssertEqual(GenTLInfoCommand.TransportLayer.genTLVersionMajor.rawValue, 9)
        XCTAssertEqual(GenTLInfoCommand.TransportLayer.genTLVersionMinor.rawValue, 10)
        XCTAssertEqual(GenTLInfoCommand.Interface.transportType.rawValue, 2)
        XCTAssertEqual(GenTLInfoCommand.Device.timestampFrequency.rawValue, 9)
        XCTAssertEqual(GenTLInfoCommand.Port.portName.rawValue, 12)

        XCTAssertEqual(GenTLInfoCommand.Stream.payloadSize.rawValue, 7)
        XCTAssertEqual(GenTLInfoCommand.Stream.transportType.rawValue, 10)
        XCTAssertEqual(GenTLInfoCommand.Stream.numChunksMax.rawValue, 11)
        XCTAssertEqual(GenTLInfoCommand.Stream.bufferAlignment.rawValue, 13)
        XCTAssertEqual(GenTLInfoCommand.Stream.flowTable.rawValue, 14)
        XCTAssertEqual(GenTLInfoCommand.Stream.genDCPrefetchDescriptor.rawValue, 15)

        XCTAssertEqual(GenTLInfoCommand.Buffer.pixelFormat.rawValue, 20)
        XCTAssertEqual(GenTLInfoCommand.Buffer.dataSize.rawValue, 27)
        XCTAssertEqual(GenTLInfoCommand.Buffer.timestampNanoseconds.rawValue, 28)
        XCTAssertEqual(GenTLInfoCommand.Buffer.isComposite.rawValue, 31)

        XCTAssertEqual(GenTLInfoCommand.Event.maxSize.rawValue, 3)
        XCTAssertEqual(GenTLInfoCommand.Event.infoDataSizeMax.rawValue, 4)
        XCTAssertEqual(GenTLInfoCommand.EventData.numericID.rawValue, 2)
        XCTAssertEqual(GenTLInfoCommand.URL.url.rawValue, 0)
        XCTAssertEqual(GenTLInfoCommand.URL.fileName.rawValue, 10)
        XCTAssertEqual(GenTLInfoCommand.BufferPart.base.rawValue, 0)
        XCTAssertEqual(GenTLInfoCommand.BufferPart.dataPurposeID.rawValue, 13)
        XCTAssertEqual(GenTLInfoCommand.Flow.size.rawValue, 0)
        XCTAssertEqual(GenTLInfoCommand.Segment.dataSize.rawValue, 4)
    }

    func testEveryRawProtocolDefaultReturnsNotImplemented() {
        let api = EmptyRawGenTLAPI()
        let handle = UnsafeMutableRawPointer(bitPattern: 1)!
        let unsupported: GenTLABI.GC_ERROR = GenTLABI.GenTLABI_ErrorNotImplemented()

        XCTAssertEqual(api.GCGetInfo(0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.GCGetLastError(nil, nil, nil), unsupported)
        XCTAssertEqual(api.GCInitLib(), unsupported)
        XCTAssertEqual(api.GCCloseLib(), unsupported)
        XCTAssertEqual(api.GCReadPort(handle, 0, nil, nil), unsupported)
        XCTAssertEqual(api.GCWritePort(handle, 0, nil, nil), unsupported)
        XCTAssertEqual(api.GCGetPortURL(handle, nil, nil), unsupported)
        XCTAssertEqual(api.GCGetPortInfo(handle, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.GCRegisterEvent(handle, 0, handle), unsupported)
        XCTAssertEqual(api.GCUnregisterEvent(handle, 0), unsupported)
        XCTAssertEqual(api.EventGetData(handle, nil, nil, 0), unsupported)
        XCTAssertEqual(api.EventGetDataInfo(handle, nil, 0, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.EventGetInfo(handle, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.EventFlush(handle), unsupported)
        XCTAssertEqual(api.EventKill(handle), unsupported)
        XCTAssertEqual(api.TLOpen(handle), unsupported)
        XCTAssertEqual(api.TLClose(handle), unsupported)
        XCTAssertEqual(api.TLGetInfo(handle, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.TLGetNumInterfaces(handle, nil), unsupported)
        XCTAssertEqual(api.TLGetInterfaceID(handle, 0, nil, nil), unsupported)
        XCTAssertEqual(api.TLGetInterfaceInfo(handle, nil, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.TLOpenInterface(handle, nil, handle), unsupported)
        XCTAssertEqual(api.TLUpdateInterfaceList(handle, nil, 0), unsupported)
        XCTAssertEqual(api.IFClose(handle), unsupported)
        XCTAssertEqual(api.IFGetInfo(handle, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.IFGetNumDevices(handle, nil), unsupported)
        XCTAssertEqual(api.IFGetDeviceID(handle, 0, nil, nil), unsupported)
        XCTAssertEqual(api.IFUpdateDeviceList(handle, nil, 0), unsupported)
        XCTAssertEqual(api.IFGetDeviceInfo(handle, nil, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.IFOpenDevice(handle, nil, 0, handle), unsupported)
        XCTAssertEqual(api.DevGetPort(handle, handle), unsupported)
        XCTAssertEqual(api.DevGetNumDataStreams(handle, nil), unsupported)
        XCTAssertEqual(api.DevGetDataStreamID(handle, 0, nil, nil), unsupported)
        XCTAssertEqual(api.DevOpenDataStream(handle, nil, handle), unsupported)
        XCTAssertEqual(api.DevGetInfo(handle, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.DevClose(handle), unsupported)
        XCTAssertEqual(api.DSAnnounceBuffer(handle, nil, 0, nil, handle), unsupported)
        XCTAssertEqual(api.DSAllocAndAnnounceBuffer(handle, 0, nil, handle), unsupported)
        XCTAssertEqual(api.DSFlushQueue(handle, 0), unsupported)
        XCTAssertEqual(api.DSStartAcquisition(handle, 0, 0), unsupported)
        XCTAssertEqual(api.DSStopAcquisition(handle, 0), unsupported)
        XCTAssertEqual(api.DSGetInfo(handle, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.DSGetBufferID(handle, 0, handle), unsupported)
        XCTAssertEqual(api.DSClose(handle), unsupported)
        XCTAssertEqual(api.DSRevokeBuffer(handle, handle, nil, nil), unsupported)
        XCTAssertEqual(api.DSQueueBuffer(handle, handle), unsupported)
        XCTAssertEqual(api.DSGetBufferInfo(handle, handle, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.GCGetNumPortURLs(handle, nil), unsupported)
        XCTAssertEqual(api.GCGetPortURLInfo(handle, 0, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.GCReadPortStacked(handle, nil, nil), unsupported)
        XCTAssertEqual(api.GCWritePortStacked(handle, nil, nil), unsupported)
        XCTAssertEqual(api.DSGetBufferChunkData(handle, handle, nil, nil), unsupported)
        XCTAssertEqual(api.IFGetParentTL(handle, handle), unsupported)
        XCTAssertEqual(api.DevGetParentIF(handle, handle), unsupported)
        XCTAssertEqual(api.DSGetParentDev(handle, handle), unsupported)
        XCTAssertEqual(api.DSGetNumBufferParts(handle, handle, nil), unsupported)
        XCTAssertEqual(api.DSGetBufferPartInfo(handle, handle, 0, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.DSAnnounceCompositeBuffer(handle, 0, nil, nil, nil, handle), unsupported)
        XCTAssertEqual(api.DSGetBufferInfoStacked(handle, handle, nil, 0), unsupported)
        XCTAssertEqual(api.DSGetBufferPartInfoStacked(handle, handle, nil, 0), unsupported)
        XCTAssertEqual(api.DSGetNumFlows(handle, nil), unsupported)
        XCTAssertEqual(api.DSGetFlowInfo(handle, 0, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.DSGetNumBufferSegments(handle, handle, nil), unsupported)
        XCTAssertEqual(api.DSGetBufferSegmentInfo(handle, handle, 0, 0, nil, nil, nil), unsupported)
    }

}
