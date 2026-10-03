import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let contentView = SettingsView()
        let hostingController = NSHostingController(rootView: contentView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = OverlayStyle.language() == .simplifiedChinese ? "DoubleTapTalk 设置" : "DoubleTapTalk Settings"
        // Resizable with a sane floor: the grouped Form scrolls on macOS 13+.
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 620))
        window.minSize = NSSize(width: 440, height: 500)
        window.center()
        window.isReleasedWhenClosed = false
        
        self.init(window: window)
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}