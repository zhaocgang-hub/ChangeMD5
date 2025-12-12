import SwiftUI

@main
struct BatchMD5App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 520, minHeight: 300)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
