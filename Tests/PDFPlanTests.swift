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

final class PDFTuningTests: XCTestCase {
    func testCompressToASizeNamesTheFileAfterIt() throws {
        XCTAssertEqual(try PDFPlan.make(action: .compress, option: .maxBytes(1_000_000)),
                       PDFPlan(fileExtension: "pdf", suffix: "-1mb", targetBytes: 1_000_000, appliesSizeGuard: true))
        XCTAssertEqual(try PDFPlan.make(action: .auto, option: .maxBytes(1_000_000)).targetBytes, nil,
                       "only Compress aims at a size")
    }

    func testTheLadderGoesFromSharpToSmall() {
        let ladder = PDFTuning.ladder
        XCTAssertTrue(ladder.contains(PDFTuning.screen))
        for (a, b) in zip(ladder, ladder.dropFirst()) {
            XCTAssertTrue(b.pixelsPerInch < a.pixelsPerInch || (b.pixelsPerInch == a.pixelsPerInch && b.quality < a.quality),
                          "\(a) then \(b)")
        }
    }

    func testBestFitPicksTheSharpestStepThatFits() {
        // A pretend PDF whose size falls with each step: 11 MB, 10 MB … 1 MB.
        func size(_ step: PDFTuning.Step) -> Int {
            (PDFTuning.ladder.count - PDFTuning.ladder.firstIndex(of: step)!) * 1_000_000
        }
        var tries = 0
        let fit = PDFTuning.bestFit(under: 4_500_000) { tries += 1; return size($0) }
        XCTAssertEqual(fit, PDFTuning.ladder[PDFTuning.ladder.count - 4], "4 MB, the biggest under 4.5 MB")
        XCTAssertLessThanOrEqual(tries, 4)
        XCTAssertEqual(PDFTuning.bestFit(under: 50_000_000, size: size), PDFTuning.ladder.first)
        XCTAssertNil(PDFTuning.bestFit(under: 500_000, size: size), "even the smallest is too big")
    }
}
