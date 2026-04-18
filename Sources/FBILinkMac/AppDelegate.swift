import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = AppDelegate.model, model.isServing else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Transfer in progress"
        alert.informativeText = "A file transfer to your 3DS is still running. Quitting now will cancel it."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            model.stop()
            return .terminateNow
        }
        return .terminateCancel
    }
}
