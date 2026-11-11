import XCTest
@testable import Droptimize
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Portable: also run on Linux by scripts/check-linux.sh.
final class StoreTests: XCTestCase {
    func testThreeFreeFilesADayCountedPerFile() {
        var allowance = FreeAllowance()
        XCTAssertEqual(allowance.remaining(on: "2026-11-01"), 3)
        XCTAssertEqual(allowance.grant(5, on: "2026-11-01"), 3, "a big drop runs what's left")
        allowance.record(2, on: "2026-11-01")
        XCTAssertEqual(allowance.remaining(on: "2026-11-01"), 1)
        XCTAssertEqual(allowance.grant(4, on: "2026-11-01"), 1)
        allowance.record(1, on: "2026-11-01")
        XCTAssertEqual(allowance.grant(1, on: "2026-11-01"), 0)
        XCTAssertEqual(allowance.remaining(on: "2026-11-02"), 3, "a new day starts fresh")
        allowance.record(1, on: "2026-11-02")
        XCTAssertEqual(allowance, FreeAllowance(day: "2026-11-02", used: 1))
    }

    func testDaysFollowTheUsersCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let lateEvening = Date(timeIntervalSince1970: 1_793_550_000)     // 2026-11-01 21:50 in India
        XCTAssertEqual(FreeAllowance.day(of: lateEvening, calendar: calendar), "2026-11-01")
        let afterMidnightInIndia = lateEvening.addingTimeInterval(3 * 3600)
        XCTAssertEqual(FreeAllowance.day(of: afterMidnightInIndia, calendar: calendar), "2026-11-02")
    }

    func testProLastsForLifeUnlessRefunded() {
        let checked = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 24 * 3600
        var license = License(key: "abc-1234", instanceID: "i", isActive: true, checked: checked)
        XCTAssertTrue(license.isPro, "one payment, Pro for life, online or not")
        XCTAssertFalse(license.needsCheck(at: checked.addingTimeInterval(6 * day)))
        XCTAssertTrue(license.needsCheck(at: checked.addingTimeInterval(7 * day)), "weekly, to catch refunds")
        XCTAssertEqual(license.maskedKey, "••••-1234")
        license.isActive = false
        XCTAssertFalse(license.isPro, "refunded or disabled")
    }

    func testRequestsAreJSONPostsToTheLicenseAPI() throws {
        let request = Dodo.request(.activate, ["license_key": "PRO-AAAA-BBBB", "name": "Bimanshu’s Mac"])
        XCTAssertEqual(request.url?.absoluteString, "https://live.dodopayments.com/licenses/activate")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body, ["license_key": "PRO-AAAA-BBBB", "name": "Bimanshu’s Mac"])
    }

    // As documented at https://docs.dodopayments.com/api-reference/licenses/activate-license (201).
    private let activated = """
    {"id": "lki_123", "business_id": "bus_1", "name": "Mac", "license_key_id": "lic_123",
     "created_at": "2026-11-02T10:00:00.000Z",
     "product": {"product_id": "pdt_pro", "name": "Droptimize Pro"},
     "customer": {"customer_id": "cus_1", "name": "Ada", "email": "ada@example.com", "phone_number": null}}
    """

    func testActivationReadsTheKeyAndRefusesOtherProducts() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ours: (String?) -> Bool = { $0 == "pdt_pro" }
        let license = try Dodo.activation(status: 201, data: Data(activated.utf8), key: "KEY", at: now, isOurs: ours).get()
        XCTAssertEqual(license, License(key: "KEY", instanceID: "lki_123", isActive: true, checked: now,
                                        email: "ada@example.com"))

        let theirs: (String?) -> Bool = { _ in false }
        XCTAssertEqual(Dodo.activation(status: 201, data: Data(activated.utf8), key: "KEY", at: now, isOurs: theirs),
                       .failure(.notDroptimize(instanceID: "lki_123")))

        let refusal = Data(#"{"code": "NOT_FOUND", "message": "License key not found"}"#.utf8)
        XCTAssertEqual(Dodo.activation(status: 404, data: refusal, key: "KEY", at: now, isOurs: ours), .failure(.notFound))
        XCTAssertEqual(Dodo.activation(status: 422, data: refusal, key: "KEY", at: now, isOurs: ours), .failure(.tooManyMacs))
        XCTAssertEqual(Dodo.activation(status: 403, data: refusal, key: "KEY", at: now, isOurs: ours), .failure(.inactive))
        XCTAssertEqual(Dodo.activation(status: 201, data: Data("<html>".utf8), key: "KEY", at: now, isOurs: ours),
                       .failure(.unreadable))
        XCTAssertEqual(Dodo.Failure.tooManyMacs.message, "This key is already active on another Mac. Deactivate it there, then try again.")
        XCTAssertTrue(Dodo.isPro(product: "pdt_0NrhmMZKN9pE9ck3YwEGT"), "Droptimize Pro, live")
        XCTAssertFalse(Dodo.isPro(product: "pdt_pro"), "another product's key")
        XCTAssertFalse(Dodo.isPro(product: nil))
        XCTAssertTrue(StoreConfig.isSelling)
        XCTAssertFalse(StoreConfig.testMode, "live keys only")
    }

    func testGetProOpensTheWebsitesPricing() {
        XCTAssertEqual(StoreConfig.pricing.absoluteString, "https://droptimize.app/#pricing")
    }

    func testValidationTurnsProOffOnlyOnADefiniteNo() {
        let then = Date(timeIntervalSince1970: 1_800_000_000), now = then.addingTimeInterval(86_400)
        let license = License(key: "KEY", instanceID: "lki_1", isActive: true, checked: then)

        let valid = Dodo.validation(status: 200, data: Data(#"{"valid": true}"#.utf8), license: license, at: now)
        XCTAssertEqual(valid?.checked, now)
        XCTAssertEqual(valid?.isActive, true)

        let cancelled = Dodo.validation(status: 200, data: Data(#"{"valid": false}"#.utf8), license: license, at: now)
        XCTAssertEqual(cancelled?.isActive, false, "a refund disables the key")

        XCTAssertNil(Dodo.validation(status: 422, data: Data("{}".utf8), license: license, at: now), "says nothing about the key")
        XCTAssertNil(Dodo.validation(status: 200, data: Data("oops".utf8), license: license, at: now))
    }

    func testDeactivationCountsAMissingActivationAsGone() {
        XCTAssertTrue(Dodo.deactivated(status: 200))
        XCTAssertTrue(Dodo.deactivated(status: 404), "the key is gone")
        XCTAssertTrue(Dodo.deactivated(status: 403), "this Mac's activation is gone")
        XCTAssertFalse(Dodo.deactivated(status: 422))
    }
}
