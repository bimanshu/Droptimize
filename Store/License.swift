import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fill these in from the Dodo Payments dashboard (HANDOFF.md → "Selling Pro"). Until the
/// product and its checkout link are set, Pro can't be bought and the free limit isn't enforced,
/// so preview builds stay unlimited.
enum StoreConfig {
    /// Pro's product ID ("pdt_…"), from Products in the dashboard.
    static let productID: String? = nil
    /// Its checkout link (the product's share or payment link).
    static let checkout: URL? = nil
    /// Dodo's test mode (test cards, test keys) while trying purchases out; false to sell.
    static let testMode = false
    /// One payment, Pro for life. The launch price: it goes up as more people download (owner, 2026-11-09).
    static let price = "$4.99"

    static var isSelling: Bool { productID != nil && checkout != nil }
}

/// A Pro license activated on this Mac, as of the last answer from Dodo Payments. Pro is a
/// one-time purchase, so it only ends if the key is refunded or disabled.
struct License: Codable, Equatable {
    var key: String
    /// This Mac's activation, needed to check or release it.
    var instanceID: String
    /// False once the key was refunded or disabled.
    var isActive: Bool
    /// The last time the server answered.
    var checked: Date
    var email: String?

    /// How often to check when online, to catch refunds. Offline, Pro just keeps working.  (tune)
    static let checkInterval: TimeInterval = 7 * 24 * 3600

    var isPro: Bool { isActive }

    func needsCheck(at now: Date) -> Bool {
        now.timeIntervalSince(checked) >= Self.checkInterval
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
            case .tooManyMacs: return "This key is already active on another Mac. Deactivate it there, then try again."
            case .inactive: return "This key isn't active (refunded or disabled)."
            case .notDroptimize: return "That key isn't for Droptimize Pro."
            case .unreadable: return "Couldn't read the license server's answer. Try again later."
            }
        }
    }

    /// Whether a key is for Droptimize Pro (and not some other product sold through Dodo).
    static func isPro(product: String?) -> Bool {
        product != nil && product == StoreConfig.productID
    }

    /// Reads an answer to `activate` (HTTP `status` and body): the license, or why not.
    static func activation(status: Int, data: Data, key: String, at now: Date,
                           isOurs: (String?) -> Bool = isPro(product:)) -> Result<License, Failure> {
        switch status {
        case 200..<300:
            guard let instance = try? JSONDecoder().decode(Instance.self, from: data) else { return .failure(.unreadable) }
            guard isOurs(instance.product?.productID) else { return .failure(.notDroptimize(instanceID: instance.id)) }
            return .success(License(key: key, instanceID: instance.id, isActive: true, checked: now,
                                    email: instance.customer?.email))
        case 404: return .failure(.notFound)
        case 422: return .failure(.tooManyMacs)
        case 403: return .failure(.inactive)
        default: return .failure(.unreadable)
        }
    }

    /// Reads an answer to `validate`: the license as it stands now. A definite "no" (the key was
    /// refunded or disabled, or this Mac's activation was removed) turns Pro off;
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
