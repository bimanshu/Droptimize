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

    func testProLastsThroughOfflineGraceAndLifetimeForever() {
        let checked = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 24 * 3600
        let monthly = License(key: "abc-1234", instanceID: "i", plan: .monthly, isActive: true, checked: checked)
        XCTAssertTrue(monthly.isPro(at: checked.addingTimeInterval(13 * day)))
        XCTAssertFalse(monthly.isPro(at: checked.addingTimeInterval(15 * day)), "offline too long")
        XCTAssertFalse(monthly.needsCheck(at: checked.addingTimeInterval(day / 2)))
        XCTAssertTrue(monthly.needsCheck(at: checked.addingTimeInterval(day)))

        var lifetime = monthly
        lifetime.plan = .lifetime
        XCTAssertTrue(lifetime.isPro(at: checked.addingTimeInterval(400 * day)))
        XCTAssertFalse(lifetime.needsCheck(at: checked.addingTimeInterval(6 * day)))
        lifetime.isActive = false
        XCTAssertFalse(lifetime.isPro(at: checked), "refunded or disabled")
        XCTAssertEqual(monthly.maskedKey, "••••-1234")
    }

    func testRequestsAreFormEncodedPosts() throws {
        let request = LemonSqueezy.request(.activate, ["license_key": "AB C&D=1", "instance_name": "Bimanshu’s Mac"])
        XCTAssertEqual(request.url?.absoluteString, "https://api.lemonsqueezy.com/v1/licenses/activate")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertEqual(body, "instance_name=Bimanshu%E2%80%99s%20Mac&license_key=AB%20C%26D%3D1")
    }

    private let activated = """
    {"activated": true, "error": null,
     "license_key": {"id": 1, "status": "active", "key": "38b1460a-5104-4067-a91d-77b872934d51",
                     "activation_limit": 3, "activation_usage": 1, "created_at": "2026-11-01T10:00:00.000000Z", "expires_at": null},
     "instance": {"id": "47596ad9-a811-4ebf-ac8a-03fc7b6d2a17", "name": "Mac", "created_at": "2026-11-01T10:00:00.000000Z"},
     "meta": {"store_id": 11, "order_id": 2, "order_item_id": 3, "product_id": 44, "product_name": "Droptimize Pro",
              "variant_id": 5, "variant_name": "Default", "customer_id": 6, "customer_name": "Ada", "customer_email": "ada@example.com"}}
    """

    func testActivationReadsThePlanAndRefusesOtherProducts() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ours: (Int?, Int?) -> ProPlan? = { store, product in store == 11 && product == 44 ? .lifetime : nil }
        let license = try LemonSqueezy.activation(Data(activated.utf8), key: "KEY", at: now, plan: ours).get()
        XCTAssertEqual(license, License(key: "KEY", instanceID: "47596ad9-a811-4ebf-ac8a-03fc7b6d2a17", plan: .lifetime,
                                        isActive: true, checked: now, email: "ada@example.com"))

        let theirs: (Int?, Int?) -> ProPlan? = { _, _ in nil }
        XCTAssertEqual(LemonSqueezy.activation(Data(activated.utf8), key: "KEY", at: now, plan: theirs),
                       .failure(.notDroptimize(instanceID: "47596ad9-a811-4ebf-ac8a-03fc7b6d2a17")))

        let refused = #"{"activated": false, "error": "license_key not found.", "license_key": null, "instance": null, "meta": null}"#
        let failure = LemonSqueezy.activation(Data(refused.utf8), key: "KEY", at: now, plan: ours)
        XCTAssertEqual(failure, .failure(.refused("license_key not found.")))
        if case .failure(let reason) = failure {
            XCTAssertEqual(reason.message, "That key wasn't found. Check it and try again.")
        }
        XCTAssertEqual(LemonSqueezy.activation(Data("<html>".utf8), key: "KEY", at: now, plan: ours), .failure(.unreadable))
        XCTAssertNil(LemonSqueezy.plan(store: 11, product: 44), "nothing is ours until StoreConfig is filled in")
    }

    func testValidationTurnsProOffOnlyOnADefiniteNo() {
        let then = Date(timeIntervalSince1970: 1_800_000_000), now = then.addingTimeInterval(86_400)
        let license = License(key: "KEY", instanceID: "i", plan: .monthly, isActive: true, checked: then)

        let stillValid = #"{"valid": true, "error": null, "license_key": {"status": "active"}}"#
        XCTAssertEqual(LemonSqueezy.validation(Data(stillValid.utf8), license: license, at: now)?.checked, now)
        XCTAssertEqual(LemonSqueezy.validation(Data(stillValid.utf8), license: license, at: now)?.isActive, true)

        let ended = #"{"valid": true, "error": null, "license_key": {"status": "expired"}}"#
        XCTAssertEqual(LemonSqueezy.validation(Data(ended.utf8), license: license, at: now)?.isActive, false)

        let unknown = #"{"valid": false, "error": "license_key not found."}"#
        XCTAssertEqual(LemonSqueezy.validation(Data(unknown.utf8), license: license, at: now)?.isActive, false)

        let rateLimited = #"{"error": "Too many requests"}"#
        XCTAssertNil(LemonSqueezy.validation(Data(rateLimited.utf8), license: license, at: now), "says nothing about the key")
        XCTAssertNil(LemonSqueezy.validation(Data("oops".utf8), license: license, at: now))
    }
}
