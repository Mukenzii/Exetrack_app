import SwiftUI
import UIKit
import BackgroundTasks

@main
struct ExeTrackApp: App {
    let persistence = PersistenceController.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        UIWindow.appearance().backgroundColor = .black
        BackgroundFetchService.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - AppDelegate (needed for APNs token callbacks)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PushService.shared.setup()
        PushService.shared.requestPermission()
        BackgroundFetchService.shared.scheduleFetch()
        BackgroundFetchService.shared.fetchNow()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        BackgroundFetchService.shared.fetchNow()
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushService.shared.didRegisterToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Push] Failed to register: \(error)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler handler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Handle silent push (auto_transaction type)
        guard let type = userInfo["type"] as? String, type == "auto_transaction" else {
            handler(.noData)
            return
        }
        // Post notification so HomeView can auto-record the transaction
        NotificationCenter.default.post(
            name: .openAddTransaction,
            object: nil,
            userInfo: userInfo as? [String: Any]
        )
        handler(.newData)
    }
}
