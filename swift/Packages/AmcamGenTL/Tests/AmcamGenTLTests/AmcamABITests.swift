import AmcamABI
import XCTest

final class AmcamABITests: XCTestCase {
    func testCopiesNullTerminatedDeviceFieldsWithinTheirFixedBounds() {
        var device = AmcamDeviceV2()
        setFixedField(&device.displayname, to: "Mock AmScope Camera")
        setFixedField(&device.id, to: "MOCK-001")

        var displayName = [CChar](repeating: 0, count: 65)
        var identifier = [CChar](repeating: 0, count: 65)

        let displayNameResult = displayName.withUnsafeMutableBufferPointer {
            amcam_device_copy_display_name(&device, $0.baseAddress, $0.count)
        }
        let identifierResult = identifier.withUnsafeMutableBufferPointer {
            amcam_device_copy_identifier(&device, $0.baseAddress, $0.count)
        }

        XCTAssertEqual(displayNameResult, 1)
        XCTAssertEqual(identifierResult, 1)
        XCTAssertEqual(String(cString: displayName), "Mock AmScope Camera")
        XCTAssertEqual(String(cString: identifier), "MOCK-001")
    }

    func testRejectsUnterminatedFixedDeviceFields() {
        var device = AmcamDeviceV2()
        withUnsafeMutableBytes(of: &device.displayname) {
            $0.initializeMemory(as: UInt8.self, repeating: 0x41, count: $0.count)
        }

        var destination = [CChar](repeating: 0x5a, count: 65)
        let result = destination.withUnsafeMutableBufferPointer {
            amcam_device_copy_display_name(&device, $0.baseAddress, $0.count)
        }

        XCTAssertEqual(result, 0)
        XCTAssertTrue(destination.allSatisfy { $0 == 0x5a })
    }

    func testRejectsDestinationThatCannotHoldTheCompleteString() {
        var device = AmcamDeviceV2()
        setFixedField(&device.id, to: "CAMERA-IDENTIFIER")

        var destination = [CChar](repeating: 0x5a, count: 4)
        let result = destination.withUnsafeMutableBufferPointer {
            amcam_device_copy_identifier(&device, $0.baseAddress, $0.count)
        }

        XCTAssertEqual(result, 0)
        XCTAssertEqual(destination, [0x5a, 0x5a, 0x5a, 0x5a])
    }

    private func setFixedField(
        _ field: inout (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                        CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                        CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                        CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                        CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                        CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                        CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                        CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar),
        to value: String
    ) {
        withUnsafeMutableBytes(of: &field) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0, count: destination.count)
            let bytes = Array(value.utf8)
            destination.copyBytes(from: bytes)
        }
    }
}
