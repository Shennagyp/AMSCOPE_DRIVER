import AmcamABI
import XCTest

final class AmcamABITests: XCTestCase {
    func testCopiesNullTerminatedDeviceFieldsWithinTheirFixedBounds() {
        var device = AmcamDeviceV2()
        withUnsafeMutableBytes(of: &device.displayname) {
            $0.initializeMemory(as: UInt8.self, repeating: 0, )
            $0.copyBytes(from: Array("Mock AmScope Camera".utf8))
        }
        withUnsafeMutableBytes(of: &device.id) {
            $0.initializeMemory(as: UInt8.self, repeating: 0, )
            $0.copyBytes(from: Array("MOCK-001".utf8))
        }

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
            $0.initializeMemory(as: UInt8.self, repeating: 0x41, )
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
        withUnsafeMutableBytes(of: &device.id) {
            $0.initializeMemory(as: UInt8.self, repeating: 0, )
            $0.copyBytes(from: Array("CAMERA-IDENTIFIER".utf8))
        }

        var destination = [CChar](repeating: 0x5a, count: 4)
        let result = destination.withUnsafeMutableBufferPointer {
            amcam_device_copy_identifier(&device, $0.baseAddress, $0.count)
        }

        XCTAssertEqual(result, 0)
        XCTAssertEqual(destination, [0x5a, 0x5a, 0x5a, 0x5a])
    }

}
