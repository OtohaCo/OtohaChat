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
        .defaultSize(width: 1100, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    AppSession.shared.store.createConversation()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        Settings {
            SettingsView()
                .environmentObject(AppSession.shared.store)
                .frame(minWidth: 560, minHeight: 480)
        }
    }
}
