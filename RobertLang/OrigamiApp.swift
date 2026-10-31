import SwiftUI

@main
struct OrigamiApp: App {
    @StateObject private var catalog = CatalogStore()
    var body: some Scene {
        WindowGroup {
            CatalogRootView().environmentObject(catalog)
                .preferredColorScheme(.dark)
                .task { await catalog.load() }
        }
    }
}

enum Theme {
    static let gold = Color(red: 0.70, green: 0.61, blue: 0.44)
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.10)
}
