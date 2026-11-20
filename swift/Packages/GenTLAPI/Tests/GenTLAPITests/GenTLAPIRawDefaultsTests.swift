import XCTest
import GenTLABI
import GenTLAPI

private struct DefaultGenTLAPI: GenTLAPI {}

final class GenTLAPIRawDefaultsTests: XCTestCase {
    func testUnimplementedDefaultFunctionsReturnGenTLStatusCodes() {
        let api = DefaultGenTLAPI()

        XCTAssertEqual(api.GCInitLib(), GenTLABI.GC_ERR_NOT_IMPLEMENTED)
        XCTAssertEqual(api.GCCloseLib(), GenTLABI.GC_ERR_NOT_IMPLEMENTED)

        var system: GenTLABI.TL_HANDLE = nil
        XCTAssertEqual(api.TLOpen(&system), GenTLABI.GC_ERR_NOT_IMPLEMENTED)

        var interfaceCount: UInt32 = 0
        XCTAssertEqual(
            api.TLGetNumInterfaces(system, &interfaceCount),
            GenTLABI.GC_ERR_NOT_IMPLEMENTED
        )

        XCTAssertEqual(
            api.GCReadPort(nil, 0, nil, nil),
            GenTLABI.GC_ERR_NOT_IMPLEMENTED
        )
        XCTAssertEqual(
            api.GCRegisterEvent(nil, 0, nil),
            GenTLABI.GC_ERR_NOT_IMPLEMENTED
        )
        XCTAssertEqual(
            api.EventGetData(nil, nil, nil, 0),
            GenTLABI.GC_ERR_NOT_IMPLEMENTED
        )
        XCTAssertEqual(
            api.DSGetNumFlows(nil, nil),
            GenTLABI.GC_ERR_NOT_IMPLEMENTED
        )
    }
}
