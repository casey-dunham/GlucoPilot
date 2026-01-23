import SwiftUI
import AppKit

/// Main application entry point
/// This app runs as a menu bar agent (no dock icon, no main window)
@main
struct DexcomMenuBarApp: App {

    // The menu bar controller manages the status item and menu
    // Using StateObject ensures it persists for the app lifetime
    @StateObject private var menuBarController = MenuBarController()

    // Use NSApplicationDelegateAdaptor to configure app behavior
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty settings scene - we don't need a window
        Settings {
            EmptyView()
        }
    }
}

/// App delegate to configure the app as an agent (no dock icon)
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - app runs only in menu bar
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when windows close (we have no windows anyway)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean shutdown
    }
}
