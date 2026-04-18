import SwiftUI

@main
struct FBILinkMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 640, minHeight: 420)
                .onAppear { AppDelegate.model = model }
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
