import XCTest
@testable import GenTLAPI

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

    func testInfoCommandIdentifiersMatchGenTL16() {
        XCTAssertEqual(GenTLInfoCommand.TransportLayer.charEncoding.rawValue, 8)
        XCTAssertEqual(GenTLInfoCommand.TransportLayer.genTLVersionMajor.rawValue, 9)
        XCTAssertEqual(GenTLInfoCommand.TransportLayer.genTLVersionMinor.rawValue, 10)
        XCTAssertEqual(GenTLInfoCommand.Interface.transportType.rawValue, 2)
        XCTAssertEqual(GenTLInfoCommand.Device.timestampFrequency.rawValue, 9)
        XCTAssertEqual(GenTLInfoCommand.Port.portName.rawValue, 12)

        XCTAssertEqual(GenTLInfoCommand.Stream.payloadSize.rawValue, 7)
        XCTAssertEqual(GenTLInfoCommand.Stream.transportType.rawValue, 10)

        XCTAssertEqual(GenTLInfoCommand.Buffer.pixelFormat.rawValue, 20)
        XCTAssertEqual(GenTLInfoCommand.Buffer.dataSize.rawValue, 27)
        XCTAssertEqual(GenTLInfoCommand.Buffer.timestampNanoseconds.rawValue, 28)
        XCTAssertEqual(GenTLInfoCommand.Buffer.isComposite.rawValue, 31)

        XCTAssertEqual(GenTLInfoCommand.Event.maxSize.rawValue, 3)
        XCTAssertEqual(GenTLInfoCommand.Event.infoDataSizeMax.rawValue, 4)
        XCTAssertEqual(GenTLInfoCommand.EventData.numericID.rawValue, 2)
    }
}
