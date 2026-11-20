import XCTest
@testable import GenTLRouter

final class GenTLRouterRegistrationTests: XCTestCase {
    func testRegistrationIsLazyUntilDiscovery() throws {
        let router = GenTLRouter()
        var factoryInvocations = 0

        try router.register(backendID: "lazy-backend") {
            factoryInvocations += 1
            throw NSError(
                domain: "GenTLRouterRegistrationTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Expected test factory failure"]
            )
        }

        XCTAssertEqual(factoryInvocations, 0)
        XCTAssertEqual(router.backendIDs, ["lazy-backend"])

        let report = router.discover(timeout: 0)

        XCTAssertEqual(factoryInvocations, 1)
        XCTAssertTrue(report.devices.isEmpty)
        XCTAssertEqual(report.failures.map(\.backendID), ["lazy-backend"])
        XCTAssertTrue(report.failures[0].message.contains("Expected test factory failure"))
    }

    func testDuplicateBackendIdentifierIsRejectedWithoutReplacingRegistration() throws {
        let router = GenTLRouter()
        var firstFactoryInvocations = 0
        var secondFactoryInvocations = 0

        try router.register(backendID: "camera-backend") {
            firstFactoryInvocations += 1
            throw NSError(domain: "first", code: 1)
        }

        XCTAssertThrowsError(
            try router.register(backendID: "camera-backend") {
                secondFactoryInvocations += 1
                throw NSError(domain: "second", code: 2)
            }
        ) { error in
            guard case GenTLRouterError.duplicateBackendID("camera-backend") = error else {
                return XCTFail("Expected duplicateBackendID, received \(error)")
            }
        }

        XCTAssertEqual(router.backendIDs, ["camera-backend"])
        XCTAssertEqual(firstFactoryInvocations, 0)
        XCTAssertEqual(secondFactoryInvocations, 0)
    }

    func testBackendIdentifiersMustBeCanonicalNonEmptyValues() throws {
        let router = GenTLRouter()

        for invalidID in ["", " camera", "camera ", "\ncamera", "camera\n"] {
            XCTAssertThrowsError(
                try router.register(backendID: invalidID) {
                    throw NSError(domain: "unexpected-factory", code: 1)
                },
                "Expected backend identifier '\(invalidID.debugDescription)' to be rejected"
            ) { error in
                guard case GenTLRouterError.emptyBackendID = error else {
                    return XCTFail("Expected emptyBackendID, received \(error)")
                }
            }
        }

        XCTAssertTrue(router.backendIDs.isEmpty)
    }
}
