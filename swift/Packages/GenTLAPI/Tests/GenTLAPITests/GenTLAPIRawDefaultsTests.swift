import XCTest
import GenTLABI
import GenTLAPI

private struct DefaultGenTLAPI: GenTLAPI {}

final class GenTLAPIRawDefaultsTests: XCTestCase {
    func testUnimplementedDefaultFunctionsReturnGenTLStatusCodes() {
        let api = DefaultGenTLAPI()

        XCTAssertEqual(api.GCInitLib(), GenTLABI.GenTLABI_ErrorNotImplemented())
        XCTAssertEqual(api.GCCloseLib(), GenTLABI.GenTLABI_ErrorNotImplemented())

        var system: GenTLABI.TL_HANDLE = nil
        XCTAssertEqual(api.TLOpen(&system), GenTLABI.GenTLABI_ErrorNotImplemented())

        var interfaceCount: UInt32 = 0
        XCTAssertEqual(
            api.TLGetNumInterfaces(system, &interfaceCount),
            GenTLABI.GenTLABI_ErrorNotImplemented()
        )

        XCTAssertEqual(
            api.GCReadPort(nil, 0, nil, nil),
            GenTLABI.GenTLABI_ErrorNotImplemented()
        )
        XCTAssertEqual(
            api.GCRegisterEvent(nil, 0, nil),
            GenTLABI.GenTLABI_ErrorNotImplemented()
        )
        XCTAssertEqual(
            api.EventGetData(nil, nil, nil, 0),
            GenTLABI.GenTLABI_ErrorNotImplemented()
        )
        XCTAssertEqual(
            api.DSGetNumFlows(nil, nil),
            GenTLABI.GenTLABI_ErrorNotImplemented()
        )
    }
}
