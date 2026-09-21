import OtohaChatKit
import SwiftUI

@main
struct OtohaChatApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(AppSession.shared.store)
                .task { await AppSession.shared.store.bootstrap() }
        }
    }
}
