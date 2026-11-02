import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fill these in from the Dodo Payments dashboard (HANDOFF.md → "Selling Pro"). Until the
/// products and checkout links are set, Pro can't be bought and the free limit isn't enforced, so
/// preview builds stay unlimited.
enum StoreConfig {
    /// Each product's ID ("pdt_…"), from Products in the dashboard.
    static let monthlyProductID: String? = nil
    static let lifetimeProductID: String? = nil
    /// Each product's checkout link (the product's share or payment link).
    static let monthlyCheckout: URL? = nil
    static let lifetimeCheckout: URL? = nil
    /// The customer portal's link, where buyers manage or cancel a subscription. Optional.
    static let customerPortal: URL? = nil
    /// Dodo's test mode (test cards, test keys) while trying purchases out; false to sell.
    static let testMode = false
    static let monthlyPrice = "$5"
    static let lifetimePrice = "$50"

    static var isSelling: Bool {
        monthlyProductID != nil && lifetimeProductID != nil && monthlyCheckout != nil && lifetimeCheckout != nil
    }
}

enum ProPlan: String, Codable, Equatable {
    case monthly, lifetime

    var title: String { self == .monthly ? "Monthly" : "Lifetime" }
}

/// A Pro license activated on this Mac, as of the last answer from Dodo Payments.
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

/// Dodo Payments' public license API (https://docs.dodopayments.com/features/license-keys): it
/// takes the key itself, no API secret. The only network calls the app makes (CORE.md Rule 4),
/// and they carry the key and this Mac's name, never files. Building requests and reading answers
/// is portable; sending them is in `ProStore`.
enum Dodo {
    static var base: URL {
        URL(string: StoreConfig.testMode ? "https://test.dodopayments.com/" : "https://live.dodopayments.com/")!
    }

    enum Endpoint: String {
        case activate, validate, deactivate
    }

    static func request(_ endpoint: Endpoint, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent("licenses").appendingPathComponent(endpoint.rawValue))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return request
    }

    /// An activation: this Mac's instance, for which product, bought by whom.
    struct Instance: Decodable {
        var id: String
        var product: Product?
        var customer: Customer?

        struct Product: Decodable {
            var productID: String

            enum CodingKeys: String, CodingKey {
                case productID = "product_id"
            }
        }

        struct Customer: Decodable {
            var email: String?
        }
    }

    struct Validity: Decodable {
        var valid: Bool
    }

    enum Failure: Error, Equatable {
        case notFound
        /// On as many Macs as the key allows.
        case tooManyMacs
        /// Cancelled, refunded or disabled.
        case inactive
        /// A real key, but for another product.
        case notDroptimize(instanceID: String)
        case unreadable

        var message: String {
            switch self {
            case .notFound: return "That key wasn't found. Check it and try again."
            case .tooManyMacs: return "This key is on too many Macs. Deactivate it on one, then try again."
            case .inactive: return "This key isn't active. If the subscription ended, renew it."
            case .notDroptimize: return "That key isn't for Droptimize Pro."
            case .unreadable: return "Couldn't read the license server's answer. Try again later."
            }
        }
    }

    /// Which plan a product is, if it's one of ours.
    static func plan(product: String?) -> ProPlan? {
        guard let product else { return nil }
        if product == StoreConfig.lifetimeProductID { return .lifetime }
        if product == StoreConfig.monthlyProductID { return .monthly }
        return nil
    }

    /// Reads an answer to `activate` (HTTP `status` and body): the license, or why not.
    static func activation(status: Int, data: Data, key: String, at now: Date,
                           plan: (String?) -> ProPlan? = plan(product:)) -> Result<License, Failure> {
        switch status {
        case 200..<300:
            guard let instance = try? JSONDecoder().decode(Instance.self, from: data) else { return .failure(.unreadable) }
            guard let kind = plan(instance.product?.productID) else {
                return .failure(.notDroptimize(instanceID: instance.id))
            }
            return .success(License(key: key, instanceID: instance.id, plan: kind, isActive: true, checked: now,
                                    email: instance.customer?.email))
        case 404: return .failure(.notFound)
        case 422: return .failure(.tooManyMacs)
        case 403: return .failure(.inactive)
        default: return .failure(.unreadable)
        }
    }

    /// Reads an answer to `validate`: the license as it stands now. A definite "no" (the key was
    /// cancelled, refunded or disabled, or this Mac's activation was removed) turns Pro off;
    /// anything else leaves it as it was (nil: keep the old one).
    static func validation(status: Int, data: Data, license: License, at now: Date) -> License? {
        guard (200..<300).contains(status), let answer = try? JSONDecoder().decode(Validity.self, from: data) else {
            return nil
        }
        var updated = license
        updated.checked = now
        updated.isActive = answer.valid
        return updated
    }

    /// Whether a `deactivate` answer means this Mac's activation is gone (or never was).
    static func deactivated(status: Int) -> Bool {
        (200..<300).contains(status) || status == 403 || status == 404
    }
}
