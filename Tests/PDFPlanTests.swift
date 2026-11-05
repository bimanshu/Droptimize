import XCTest
@testable import Droptimize

// Portable: also runs on Linux via scripts/check-linux.sh.
final class PDFPlanTests: XCTestCase {
    func testAutoAndCompressMakeASmallerCopy() throws {
        let plan = PDFPlan(fileExtension: "pdf", suffix: "-min", appliesSizeGuard: true)
        XCTAssertEqual(try PDFPlan.make(action: .auto, option: nil), plan)
        XCTAssertEqual(try PDFPlan.make(action: .compress, option: nil), plan)
    }

    func testOtherActionsSayWhatTheyAreFor() {
        for action in [Action.convert, .halfSize, .removeBackground] {
            XCTAssertThrowsError(try PDFPlan.make(action: action, option: nil)) { error in
                XCTAssertEqual(error as? JobError, .notYet("That's for images."))
            }
        }
        for action in [Action.resize, .mute] {
            XCTAssertThrowsError(try PDFPlan.make(action: action, option: nil)) { error in
                XCTAssertEqual(error as? JobError, .notYet("That's for videos."))
            }
        }
    }

    func testProtectedAndSignedPDFsSaySoPlainly() {
        XCTAssertEqual(JobError.protectedPDF.errorDescription, "This PDF is password-protected, so it's left as it is.")
        XCTAssertEqual(JobError.signedPDF.errorDescription, "This PDF is signed. Compressing it would break the signature.")
    }
}
