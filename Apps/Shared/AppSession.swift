import OtohaChatKit
import SwiftUI

/// Owns the `ChatStore` on the main actor so `App.init` never constructs it.
@MainActor
final class AppSession: ObservableObject {
    static let shared = AppSession()
    let store: ChatStore

    private init() {
        store = ChatStore.makeDefault()
    }
}
