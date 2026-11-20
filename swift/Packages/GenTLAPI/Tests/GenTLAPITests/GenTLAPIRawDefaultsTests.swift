import XCTest
import GenTLABI
import GenTLAPI

private struct DefaultGenTLAPI: GenTLAPI {}

final class GenTLAPIRawDefaultsTests: XCTestCase {
    func testUnimplementedDefaultFunctionsReturnGenTLStatusCodes() {
        let api = DefaultGenTLAPI()
        let handle = UnsafeMutableRawPointer(bitPattern: 1)!

        XCTAssertEqual(api.GCInitLib(), GenTLABI.GenTLABI_ErrorNotImplemented())
        XCTAssertEqual(api.GCCloseLib(), GenTLABI.GenTLABI_ErrorNotImplemented())

        var system: GenTLABI.TL_HANDLE = handle
        XCTAssertEqual(api.TLOpen(&system), GenTLABI.GenTLABI_ErrorNotImplemented())

        var interfaceCount: UInt32 = 0
        XCTAssertEqual(
            api.TLGetNumInterfaces(system, &interfaceCount),
            GenTLABI.GenTLABI_ErrorNotImplemented()
        )

        XCTAssertEqual(
            api.GCReadPort(handle, 0, nil, nil),
            GenTLABI.GenTLABI_ErrorNotImplemented()
        )
        XCTAssertEqual(
            api.GCRegisterEvent(handle, 0, handle),
            GenTLABI.GenTLABI_ErrorNotImplemented()
        )
        XCTAssertEqual(
            api.EventGetData(handle, nil, nil, 0),
            GenTLABI.GenTLABI_ErrorNotImplemented()
        )
        XCTAssertEqual(
            api.DSGetNumFlows(handle, nil),
            GenTLABI.GenTLABI_ErrorNotImplemented()
        )
    }
}
