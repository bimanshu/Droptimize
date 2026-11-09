import XCTest
@testable import Droptimize

// Portable: also runs on Linux via scripts/check-linux.sh.
final class PDFPlanTests: XCTestCase {
    func testAutoAndCompressMakeASmallerCopy() throws {
        let plan = PDFPlan(fileExtension: "pdf", suffix: "-min", appliesSizeGuard: true)
        XCTAssertEqual(try PDFPlan.make(action: .auto, option: nil), plan)
        XCTAssertEqual(try PDFPlan.make(action: .compress, option: nil), plan)
    }

    func testConvertMakesPageImages() throws {
        XCTAssertEqual(try PDFPlan.make(action: .convert, option: nil),
                       PDFPlan(fileExtension: "png", suffix: "", appliesSizeGuard: false, pageFormat: .png), "PNG by default")
        XCTAssertEqual(try PDFPlan.make(action: .convert, option: .format(.jpeg)).pageFormat, .jpeg)
        XCTAssertEqual(try PDFPlan.make(action: .convert, option: .format(.jpeg)).fileExtension, "jpg")
        XCTAssertEqual(try PDFPlan.make(action: .convert, option: .format(.webp)).pageFormat, .png, "only PNG or JPG")
    }

    func testOtherActionsSayWhatTheyAreFor() {
        for action in [Action.halfSize, .removeBackground] {
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

final class PDFConversionTests: XCTestCase {
    func testPagesForImagesAreShapedLikeThemAndAtMostA4() {
        let scan = PDFTuning.pageSize(pixelWidth: 2480, pixelHeight: 3508)          // A4 at 300 dpi
        XCTAssertEqual(scan.width, 595.3, accuracy: 0.1)
        XCTAssertEqual(scan.height, 842, accuracy: 0.001)
        let photo = PDFTuning.pageSize(pixelWidth: 4032, pixelHeight: 3024)
        XCTAssertEqual(photo.width, 842, accuracy: 0.001)
        XCTAssertEqual(photo.height, 631.5, accuracy: 0.001)
        let icon = PDFTuning.pageSize(pixelWidth: 300, pixelHeight: 200)
        XCTAssertTrue(icon == (300, 200), "a small picture isn't blown up")
    }

    func testPicturesKeepAtMost300PPIOnTheirPage() {
        XCTAssertEqual(PDFTuning.pixelScale(pixelWidth: 2480, pixelHeight: 3508), 1, "a 300 dpi A4 scan stays as it is")
        XCTAssertEqual(PDFTuning.pixelScale(pixelWidth: 8000, pixelHeight: 6000), 3508.3 / 8000, accuracy: 0.001)
        XCTAssertEqual(PDFTuning.pixelScale(pixelWidth: 300, pixelHeight: 200), 1)
    }

    func testPageImagesAreRetinaSharp() {
        XCTAssertTrue(PDFTuning.pageImageSize(pointWidth: 595, pointHeight: 842) == (1190, 1684))
        let poster = PDFTuning.pageImageSize(pointWidth: 5000, pointHeight: 3000)
        XCTAssertEqual(poster.width, PDFTuning.maxPageImageSide, "huge pages are capped")
    }

    func testImagesIntoOnePDFCountAsOneFreeFile() {
        XCTAssertTrue(Job.combinesIntoOnePDF(kinds: [.image], action: .convert, option: .pdf))
        XCTAssertFalse(Job.combinesIntoOnePDF(kinds: [.document], action: .convert, option: .pdf), "each document is its own PDF")
        XCTAssertFalse(Job.combinesIntoOnePDF(kinds: [.image], action: .convert, option: .format(.webp)))
        XCTAssertEqual(Job.freeFiles(fileCount: 12, kinds: [.image], action: .convert, option: .pdf), 1)
        XCTAssertEqual(Job.freeFiles(fileCount: 12, kinds: [.image], action: .compress, option: nil), 12)
    }
}

final class DocumentPlanTests: XCTestCase {
    func testWordDocumentsBecomePDFs() throws {
        XCTAssertEqual(try DocumentPlan.make(action: .auto, option: nil), DocumentPlan(fileExtension: "pdf"))
        XCTAssertEqual(try DocumentPlan.make(action: .convert, option: .pdf), DocumentPlan(fileExtension: "pdf"))
        XCTAssertThrowsError(try DocumentPlan.make(action: .compress, option: nil)) { error in
            XCTAssertEqual(error as? JobError, .notYet("Word documents become PDFs: drop on Convert."))
        }
        XCTAssertEqual(DocumentPlan.extensions, ["docx", "doc"])
    }

    func testWordThenPagesThenTheBuiltInReader() {
        XCTAssertEqual(DocumentEngine.order(wordInstalled: true, pagesInstalled: true), [.word, .pages, .builtIn])
        XCTAssertEqual(DocumentEngine.order(wordInstalled: false, pagesInstalled: true), [.pages, .builtIn])
        XCTAssertEqual(DocumentEngine.order(wordInstalled: false, pagesInstalled: false), [.builtIn])
        XCTAssertEqual(DocumentEngine.word.bundleIdentifier, "com.microsoft.Word")
        XCTAssertEqual(DocumentEngine.pages.bundleIdentifier, "com.apple.iWork.Pages")
    }

    func testTheCardSaysWhyTheLayoutMayDiffer() {
        XCTAssertEqual(DocumentEngine.builtInNote(tried: [.builtIn], refused: nil), "Without Word or Pages, layout may differ")
        XCTAssertEqual(DocumentEngine.builtInNote(tried: [.word, .builtIn], refused: nil), "Word didn't help: layout may differ")
        XCTAssertEqual(DocumentEngine.builtInNote(tried: [.word, .pages, .builtIn], refused: .word),
                       "Allow Word in Settings for an exact copy")
    }
}
