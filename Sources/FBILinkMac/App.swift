import SwiftUI

@main
struct FBILinkMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 640, minHeight: 420)
                .onOpenURL { url in
                    if url.isFileURL {
                        model.addFiles([url])
                    } else {
                        model.addRemoteURL(url)
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
