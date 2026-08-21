import UIKit
import UserNotifications

/// Handles APNs registration, device token upload, and incoming push routing.
class PushService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushService()

    // Update this to your backend URL (local dev or deployed server)
    private let backendURL = Config.backendURL

    private override init() { super.init() }

    // MARK: - Setup

    func setup() {
        UNUserNotificationCenter.current().delegate = self

        // Register notification category with quick-reply actions
        let actions = TransactionCategory.quickActions.map { cat in
            UNNotificationAction(
                identifier: cat.actionId,
                title: cat.displayName,
                options: []
            )
        }
        let category = UNNotificationCategory(
            identifier: "TRANSACTION_CATEGORY",
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Asks for notification permission.
    ///
    /// Deliberately *not* called at launch: a cold permission prompt before the
    /// user has seen what notifications are for gets denied, and that denial is
    /// hard to undo. The "Enable Notifications" row on the home screen calls
    /// this once the user opts in.
    func requestPermission(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            DispatchQueue.main.async {
                // Remote push only matters when there is a server to send it.
                if granted && Config.isBackendConfigured {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                completion?(granted)
            }
        }
    }

    // MARK: - Token registration

    func didRegisterToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        print("[Push] Device token: \(token)")
        uploadToken(token)
    }

    private func uploadToken(_ token: String) {
        guard Config.isBackendConfigured,
              let url = URL(string: "\(backendURL)/register-device") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["device_token": token])
        URLSession.shared.dataTask(with: req) { _, _, error in
            if let error { print("[Push] Token upload error: \(error)") }
            else { print("[Push] Token uploaded ✅") }
        }.resume()
    }

    // MARK: - Foreground display

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handler([.banner, .sound, .badge])
    }

    // MARK: - Tap / action response

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler handler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let txId     = userInfo["tx_id"] as? Int ?? 0
        let merchant = userInfo["merchant"] as? String ?? ""
        let amount   = userInfo["amount"] as? Double ?? 0
        let currency = userInfo["currency"] as? String ?? "UZS"

        // User tapped a category action button
        if response.actionIdentifier != UNNotificationDefaultActionIdentifier,
           let cat = TransactionCategory.from(actionId: response.actionIdentifier) {
            sendCategorization(txId: txId, merchant: merchant, category: cat)
        } else {
            // User tapped the notification body → open app with pre-filled AddTransaction
            NotificationCenter.default.post(
                name: .openAddTransaction,
                object: nil,
                userInfo: [
                    "merchant": merchant,
                    "amount": amount,
                    "currency": currency,
                    "tx_id": txId,
                ]
            )
        }
        handler()
    }

    // MARK: - Categorization API call

    func sendCategorization(txId: Int, merchant: String, category: TransactionCategory) {
        guard let url = URL(string: "\(backendURL)/categorize") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "tx_id": txId,
            "merchant": merchant,
            "category": category.rawValue,
            "icon": category.icon,
            "color_hex": category.colorHex,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let openAddTransaction = Notification.Name("openAddTransaction")
}

// MARK: - Category quick actions

struct TransactionCategory {
    let rawValue: String
    let displayName: String
    let icon: String
    let colorHex: String

    var actionId: String { "CAT_\(rawValue)" }

    static func from(actionId: String) -> TransactionCategory? {
        let raw = actionId.replacingOccurrences(of: "CAT_", with: "")
        return quickActions.first { $0.rawValue == raw }
    }

    // Most common expense categories shown as quick actions in the notification
    static let quickActions: [TransactionCategory] = [
        .init(rawValue: "food",        displayName: "Еда",        icon: "fork.knife",        colorHex: "#FF9F0A"),
        .init(rawValue: "transport",   displayName: "Транспорт",  icon: "car.fill",          colorHex: "#30D158"),
        .init(rawValue: "groceries",   displayName: "Магазин",    icon: "cart.fill",         colorHex: "#34C759"),
        .init(rawValue: "fuel",        displayName: "Топливо",    icon: "fuelpump.fill",     colorHex: "#FF6B00"),
        .init(rawValue: "cafe",        displayName: "Кафе",       icon: "cup.and.saucer.fill",colorHex: "#AC8E68"),
        .init(rawValue: "other",       displayName: "Другое",     icon: "ellipsis.circle",   colorHex: "#636366"),
    ]
}
