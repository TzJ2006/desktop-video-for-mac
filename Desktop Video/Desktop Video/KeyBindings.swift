import AppKit

/// Centralized place for keyboard shortcuts to allow easy future changes.
enum KeyBindings {
    /// Key equivalent for starting the screensaver.
    static let startScreensaverKey = "h"
    /// Modifiers for starting the screensaver (Control + Command).
    static let startScreensaverModifiers: NSEvent.ModifierFlags = [.command, .control]
}

