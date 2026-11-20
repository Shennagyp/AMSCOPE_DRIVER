import XCTest
@testable import GenTLRouter

private final class InvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

final class GenTLRouterRegistrationTests: XCTestCase {
    func testRegistrationIsLazyUntilDiscovery() throws {
        let router = GenTLRouter()
        let factoryInvocations = InvocationCounter()

        try router.register(backendID: "lazy-backend") {
            factoryInvocations.increment()
            throw NSError(
                domain: "GenTLRouterRegistrationTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Expected test factory failure"]
            )
        }

        XCTAssertEqual(factoryInvocations.value, 0)
        XCTAssertEqual(router.backendIDs, ["lazy-backend"])

        let report = router.discover(timeout: 0)

        XCTAssertEqual(factoryInvocations.value, 1)
        XCTAssertTrue(report.devices.isEmpty)
        let failure = try XCTUnwrap(report.failures.first)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(failure.backendID, "lazy-backend")
        XCTAssertTrue(failure.message.contains("Expected test factory failure"))
    }

    func testDuplicateBackendIdentifierIsRejectedWithoutReplacingRegistration() throws {
        let router = GenTLRouter()
        let firstFactoryInvocations = InvocationCounter()
        let secondFactoryInvocations = InvocationCounter()

        try router.register(backendID: "camera-backend") {
            firstFactoryInvocations.increment()
            throw NSError(domain: "first", code: 1)
        }

        XCTAssertThrowsError(
            try router.register(backendID: "camera-backend") {
                secondFactoryInvocations.increment()
                throw NSError(domain: "second", code: 2)
            }
        ) { error in
            guard case GenTLRouterError.duplicateBackendID("camera-backend") = error else {
                return XCTFail("Expected duplicateBackendID, received \(error)")
            }
        }

        XCTAssertEqual(router.backendIDs, ["camera-backend"])
        XCTAssertEqual(firstFactoryInvocations.value, 0)
        XCTAssertEqual(secondFactoryInvocations.value, 0)
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
