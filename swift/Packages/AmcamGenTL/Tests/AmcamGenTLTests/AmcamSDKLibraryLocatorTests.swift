import Foundation
import XCTest
@testable import AmcamGenTL

final class AmcamSDKLibraryLocatorTests: XCTestCase {
    func testPrefersApplicationBundledVendorSDK() {
        let bundle = URL(fileURLWithPath: "/Applications/Amcam Imaging.app", isDirectory: true)
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

        let candidates = AmcamSDKLibraryLocator.candidateURLs(
            bundleURL: bundle,
            homeDirectory: home
        )

        XCTAssertEqual(
            candidates.first?.path,
            "/Applications/Amcam Imaging.app/Contents/Frameworks/Vendors/amcam/macos/libamcam.dylib"
        )
    }

    func testIncludesPerUserAndMachineWideFallbacks() {
        let bundle = URL(fileURLWithPath: "/Applications/Amcam Imaging.app", isDirectory: true)
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

        let paths = AmcamSDKLibraryLocator.candidateURLs(
            bundleURL: bundle,
            homeDirectory: home
        ).map(\\.path)

        XCTAssertEqual(paths[1], "/Users/tester/Library/Application Support/AmScopeMicroscope/SDK/libamcam.dylib")
        XCTAssertEqual(paths[2], "/Library/Application Support/AmScopeMicroscope/SDK/libamcam.dylib")
        XCTAssertEqual(paths[3], "/Library/Frameworks/libamcam.dylib")
        XCTAssertEqual(paths[4], "/usr/local/lib/libamcam.dylib")
        XCTAssertEqual(paths[5], "/opt/homebrew/lib/libamcam.dylib")
    }
}
