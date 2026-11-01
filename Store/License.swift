import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fill these in from the Lemon Squeezy dashboard (HANDOFF.md → "Selling Pro"). Until they're
/// all set, Pro can't be bought and the free limit isn't enforced, so preview builds stay unlimited.
enum StoreConfig {
    /// Settings → Stores: the store's number.
    static let storeID: Int? = nil
    /// Each product's number (Products → the product → its ID).
    static let monthlyProductID: Int? = nil
    static let lifetimeProductID: Int? = nil
    /// Each product's checkout link (Share → Checkout URL).
    static let monthlyCheckout: URL? = nil
    static let lifetimeCheckout: URL? = nil
    /// Where buyers manage or cancel a subscription.
    static let manageSubscription = URL(string: "https://app.lemonsqueezy.com/my-orders")!
    static let monthlyPrice = "$5"
    static let lifetimePrice = "$50"

    static var isSelling: Bool {
        storeID != nil && monthlyProductID != nil && lifetimeProductID != nil
            && monthlyCheckout != nil && lifetimeCheckout != nil
    }
}

enum ProPlan: String, Codable, Equatable {
    case monthly, lifetime

    var title: String { self == .monthly ? "Monthly" : "Lifetime" }
}

/// A Pro license activated on this Mac, as of the last answer from Lemon Squeezy.
struct License: Codable, Equatable {
    var key: String
    /// This Mac's activation, needed to check or release it.
    var instanceID: String
    var plan: ProPlan
    /// False once the key expired (a subscription ended), was refunded or disabled.
    var isActive: Bool
    /// The last time the server answered.
    var checked: Date
    var email: String?

    /// How long Pro keeps working without reaching the server (traveling, offline). A lifetime
    /// license never needs to.                                                               (tune)
    static let monthlyOfflineGrace: TimeInterval = 14 * 24 * 3600
    /// How often to check when online: monthly daily (a cancelled subscription ends soon after),
    /// lifetime weekly (refunds).
    static let monthlyCheckInterval: TimeInterval = 24 * 3600
    static let lifetimeCheckInterval: TimeInterval = 7 * 24 * 3600

    func isPro(at now: Date) -> Bool {
        guard isActive else { return false }
        return plan == .lifetime || now.timeIntervalSince(checked) < Self.monthlyOfflineGrace
    }

    func needsCheck(at now: Date) -> Bool {
        now.timeIntervalSince(checked) >= (plan == .monthly ? Self.monthlyCheckInterval : Self.lifetimeCheckInterval)
    }

    /// "••••-4D51": enough to recognise it.
    var maskedKey: String {
        "••••-" + key.suffix(4).uppercased()
    }
}

/// Lemon Squeezy's License API (https://docs.lemonsqueezy.com/api/license-api). Public: it takes
/// the key itself, no API secret. The only network calls the app makes (CORE.md Rule 4), and they
/// carry the key and this Mac's name, never files. Building requests and reading answers is
/// portable; sending them is in `ProStore`.
enum LemonSqueezy {
    static let base = URL(string: "https://api.lemonsqueezy.com/v1/licenses/")!

    enum Endpoint: String {
        case activate, validate, deactivate
    }

    static func request(_ endpoint: Endpoint, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(endpoint.rawValue))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        // Unreserved ASCII only; everything else is percent-encoded.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        request.httpBody = fields.keys.sorted().map { name in
            let value = fields[name]?.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(name)=\(value)"
        }.joined(separator: "&").data(using: .utf8)
        return request
    }

    /// The parts of an answer we use.
    struct Response: Decodable {
        var activated: Bool?
        var valid: Bool?
        var deactivated: Bool?
        var error: String?
        var licenseKey: Key?
        var instance: Instance?
        var meta: Meta?

        struct Key: Decodable {
            var status: String?
            var key: String?
        }

        struct Instance: Decodable {
            var id: String?
        }

        struct Meta: Decodable {
            var storeID: Int?
            var productID: Int?
            var customerEmail: String?

            enum CodingKeys: String, CodingKey {
                case storeID = "store_id", productID = "product_id", customerEmail = "customer_email"
            }
        }

        enum CodingKeys: String, CodingKey {
            case activated, valid, deactivated, error, instance, meta
            case licenseKey = "license_key"
        }
    }

    enum Failure: Error, Equatable {
        /// The server said no, in its own words.
        case refused(String)
        /// A real key, but for another product or store.
        case notDroptimize(instanceID: String?)
        case unreadable

        var message: String {
            switch self {
            case .refused(let reason):
                let lowered = reason.lowercased()
                if lowered.contains("not found") { return "That key wasn't found. Check it and try again." }
                if lowered.contains("activation limit") {
                    return "This key is on too many Macs. Deactivate it on one, then try again."
                }
                if lowered.contains("expired") { return "This key has expired." }
                if lowered.contains("disabled") { return "This key has been disabled." }
                return reason
            case .notDroptimize: return "That key isn't for Droptimize Pro."
            case .unreadable: return "Couldn't read the license server's answer. Try again later."
            }
        }
    }

    /// Which plan a product is, if it's one of ours.
    static func plan(store: Int?, product: Int?) -> ProPlan? {
        guard let store, store == StoreConfig.storeID, let product else { return nil }
        if product == StoreConfig.lifetimeProductID { return .lifetime }
        if product == StoreConfig.monthlyProductID { return .monthly }
        return nil
    }

    /// Reads an answer to `activate`: the license, or why not.
    static func activation(_ data: Data, key: String, at now: Date,
                           plan: (Int?, Int?) -> ProPlan? = plan(store:product:)) -> Result<License, Failure> {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return .failure(.unreadable) }
        guard response.activated == true, let instanceID = response.instance?.id else {
            return .failure(.refused(response.error ?? "The key wasn't accepted."))
        }
        guard let kind = plan(response.meta?.storeID, response.meta?.productID) else {
            return .failure(.notDroptimize(instanceID: instanceID))
        }
        return .success(License(key: key, instanceID: instanceID, plan: kind,
                                isActive: response.licenseKey?.status == "active", checked: now,
                                email: response.meta?.customerEmail))
    }

    /// Reads an answer to `validate`: the license as it stands now. A definite "no" turns Pro off;
    /// anything unreadable leaves it as it was (the caller keeps the old one).
    static func validation(_ data: Data, license: License, at now: Date) -> License? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data), let valid = response.valid else {
            return nil
        }
        var updated = license
        updated.checked = now
        updated.isActive = valid && response.licenseKey?.status == "active"
        return updated
    }
}
