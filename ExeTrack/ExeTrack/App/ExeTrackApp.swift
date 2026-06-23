import SwiftUI

@main
struct ExeTrackApp: App {
    let persistence = PersistenceController.shared

    init() {
        // Black window background to prevent white flash on launch
        UIWindow.appearance().backgroundColor = .black
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .preferredColorScheme(.dark)
        }
    }
}
