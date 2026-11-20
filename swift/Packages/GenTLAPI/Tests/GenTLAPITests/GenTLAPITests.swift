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
        let unsupported = GenTLABI.GC_ERR_NOT_IMPLEMENTED

        XCTAssertEqual(api.GCGetInfo(0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.GCGetLastError(nil, nil, nil), unsupported)
        XCTAssertEqual(api.GCInitLib(), unsupported)
        XCTAssertEqual(api.GCCloseLib(), unsupported)
        XCTAssertEqual(api.GCReadPort(nil, 0, nil, nil), unsupported)
        XCTAssertEqual(api.GCWritePort(nil, 0, nil, nil), unsupported)
        XCTAssertEqual(api.GCGetPortURL(nil, nil, nil), unsupported)
        XCTAssertEqual(api.GCGetPortInfo(nil, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.GCRegisterEvent(nil, 0, nil), unsupported)
        XCTAssertEqual(api.GCUnregisterEvent(nil, 0), unsupported)
        XCTAssertEqual(api.EventGetData(nil, nil, nil, 0), unsupported)
        XCTAssertEqual(api.EventGetDataInfo(nil, nil, 0, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.EventGetInfo(nil, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.EventFlush(nil), unsupported)
        XCTAssertEqual(api.EventKill(nil), unsupported)
        XCTAssertEqual(api.TLOpen(nil), unsupported)
        XCTAssertEqual(api.TLClose(nil), unsupported)
        XCTAssertEqual(api.TLGetInfo(nil, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.TLGetNumInterfaces(nil, nil), unsupported)
        XCTAssertEqual(api.TLGetInterfaceID(nil, 0, nil, nil), unsupported)
        XCTAssertEqual(api.TLGetInterfaceInfo(nil, nil, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.TLOpenInterface(nil, nil, nil), unsupported)
        XCTAssertEqual(api.TLUpdateInterfaceList(nil, nil, 0), unsupported)
        XCTAssertEqual(api.IFClose(nil), unsupported)
        XCTAssertEqual(api.IFGetInfo(nil, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.IFGetNumDevices(nil, nil), unsupported)
        XCTAssertEqual(api.IFGetDeviceID(nil, 0, nil, nil), unsupported)
        XCTAssertEqual(api.IFUpdateDeviceList(nil, nil, 0), unsupported)
        XCTAssertEqual(api.IFGetDeviceInfo(nil, nil, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.IFOpenDevice(nil, nil, 0, nil), unsupported)
        XCTAssertEqual(api.DevGetPort(nil, nil), unsupported)
        XCTAssertEqual(api.DevGetNumDataStreams(nil, nil), unsupported)
        XCTAssertEqual(api.DevGetDataStreamID(nil, 0, nil, nil), unsupported)
        XCTAssertEqual(api.DevOpenDataStream(nil, nil, nil), unsupported)
        XCTAssertEqual(api.DevGetInfo(nil, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.DevClose(nil), unsupported)
        XCTAssertEqual(api.DSAnnounceBuffer(nil, nil, 0, nil, nil), unsupported)
        XCTAssertEqual(api.DSAllocAndAnnounceBuffer(nil, 0, nil, nil), unsupported)
        XCTAssertEqual(api.DSFlushQueue(nil, 0), unsupported)
        XCTAssertEqual(api.DSStartAcquisition(nil, 0, 0), unsupported)
        XCTAssertEqual(api.DSStopAcquisition(nil, 0), unsupported)
        XCTAssertEqual(api.DSGetInfo(nil, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.DSGetBufferID(nil, 0, nil), unsupported)
        XCTAssertEqual(api.DSClose(nil), unsupported)
        XCTAssertEqual(api.DSRevokeBuffer(nil, nil, nil, nil), unsupported)
        XCTAssertEqual(api.DSQueueBuffer(nil, nil), unsupported)
        XCTAssertEqual(api.DSGetBufferInfo(nil, nil, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.GCGetNumPortURLs(nil, nil), unsupported)
        XCTAssertEqual(api.GCGetPortURLInfo(nil, 0, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.GCReadPortStacked(nil, nil, nil), unsupported)
        XCTAssertEqual(api.GCWritePortStacked(nil, nil, nil), unsupported)
        XCTAssertEqual(api.DSGetBufferChunkData(nil, nil, nil, nil), unsupported)
        XCTAssertEqual(api.IFGetParentTL(nil, nil), unsupported)
        XCTAssertEqual(api.DevGetParentIF(nil, nil), unsupported)
        XCTAssertEqual(api.DSGetParentDev(nil, nil), unsupported)
        XCTAssertEqual(api.DSGetNumBufferParts(nil, nil, nil), unsupported)
        XCTAssertEqual(api.DSGetBufferPartInfo(nil, nil, 0, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.DSAnnounceCompositeBuffer(nil, 0, nil, nil, nil, nil), unsupported)
        XCTAssertEqual(api.DSGetBufferInfoStacked(nil, nil, nil, 0), unsupported)
        XCTAssertEqual(api.DSGetBufferPartInfoStacked(nil, nil, nil, 0), unsupported)
        XCTAssertEqual(api.DSGetNumFlows(nil, nil), unsupported)
        XCTAssertEqual(api.DSGetFlowInfo(nil, 0, 0, nil, nil, nil), unsupported)
        XCTAssertEqual(api.DSGetNumBufferSegments(nil, nil, nil), unsupported)
        XCTAssertEqual(api.DSGetBufferSegmentInfo(nil, nil, 0, 0, nil, nil, nil), unsupported)
    }

}
