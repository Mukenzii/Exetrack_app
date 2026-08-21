import BackgroundTasks
import UserNotifications
import Foundation

class BackgroundFetchService {
    static let shared = BackgroundFetchService()

    private let taskId       = "com.exetrack.app.fetch-transactions"
    private let backendURL   = Config.backendURL
    private let lastFetchKey = "lastTransactionFetch"
    private let processedKey = "processedTransactionIds"

    private init() {}

    // MARK: - Registration

    func register() {
        // Registering a task we can never service would have iOS wake the app
        // on a schedule just to fail.
        guard Config.isBackendConfigured else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleFetch(task: refresh)
        }
    }

    func scheduleFetch() {
        guard Config.isBackendConfigured else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Background task handler

    private func handleFetch(task: BGAppRefreshTask) {
        scheduleFetch()
        let since = UserDefaults.standard.string(forKey: lastFetchKey)
        fetchTransactions(since: since) { transactions in
            if !transactions.isEmpty {
                self.processTransactions(transactions)
                UserDefaults.standard.set(ISO8601DateFormatter().string(from: Date()), forKey: self.lastFetchKey)
            }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { task.setTaskCompleted(success: false) }
    }

    // MARK: - API

    func fetchTransactions(since: String?, completion: @escaping ([[String: Any]]) -> Void) {
        guard Config.isBackendConfigured else { completion([]); return }
        var urlStr = "\(backendURL)/pending-transactions"
        if let since { urlStr += "?since=\(since)" }
        guard let url = URL(string: urlStr) else { completion([]); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let txs  = json["transactions"] as? [[String: Any]]
            else { completion([]); return }
            completion(txs)
        }.resume()
    }

    // MARK: - Process transactions

    func processTransactions(_ transactions: [[String: Any]]) {
        var processed = UserDefaults.standard.array(forKey: processedKey) as? [Int] ?? []

        for tx in transactions {
            let txId     = tx["id"]       as? Int    ?? 0
            let amount   = tx["amount"]   as? Double ?? 0
            let merchant = tx["merchant"] as? String ?? "Unknown"
            let currency = tx["currency"] as? String ?? "UZS"
            let autocat  = tx["auto_category"] as? String

            guard !processed.contains(txId) else { continue }
            processed.append(txId)

            // Save to CoreData
            NotificationCenter.default.post(
                name: .newPendingTransaction,
                object: nil,
                userInfo: [
                    "amount":   amount,
                    "merchant": merchant,
                    "currency": currency,
                    "category": autocat as Any,
                    "tx_id":    txId,
                ]
            )

            // Always show a banner — text depends on whether category is known
            showBanner(amount: amount, merchant: merchant, currency: currency,
                       txId: txId, autoCategory: autocat)
        }

        UserDefaults.standard.set(processed, forKey: processedKey)
    }

    // MARK: - Foreground fetch

    func fetchNow() {
        let since = UserDefaults.standard.string(forKey: lastFetchKey)
        fetchTransactions(since: since) { transactions in
            guard !transactions.isEmpty else { return }
            DispatchQueue.main.async {
                self.processTransactions(transactions)
                UserDefaults.standard.set(ISO8601DateFormatter().string(from: Date()), forKey: self.lastFetchKey)
            }
        }
    }

    // MARK: - Banner notification

    private func showBanner(amount: Double, merchant: String, currency: String,
                            txId: Int, autoCategory: String?) {
        let content = UNMutableNotificationContent()
        content.title = "\(formatAmount(amount)) \(currency)"
        if let cat = autoCategory, !cat.isEmpty {
            content.body = "\(merchant) → \(cat)"
            content.sound = .default
        } else {
            content.body  = "\(merchant) — выбери категорию"
            content.sound = .default
            content.categoryIdentifier = "TRANSACTION_CATEGORY"
        }
        content.userInfo = [
            "type": "new_transaction", "tx_id": txId,
            "amount": amount, "merchant": merchant, "currency": currency,
        ]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "tx_\(txId)", content: content, trigger: trigger)
        )
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let newPendingTransaction = Notification.Name("newPendingTransaction")
    static let newAutoTransaction    = Notification.Name("newAutoTransaction")
}

private func formatAmount(_ amount: Double) -> String {
    var n = Int(amount)
    var parts: [String] = []
    repeat {
        let rem = n % 1000
        n /= 1000
        parts.insert(n > 0 ? String(format: "%03d", rem) : String(rem), at: 0)
    } while n > 0
    return parts.joined(separator: " ")
}
