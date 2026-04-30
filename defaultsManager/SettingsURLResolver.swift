//
//  SettingsURLResolver.swift
//  defaultsManager
//
//  Maps defaults domains (and optionally categories) to macOS System Settings
//  deep-link URLs using the x-apple.systempreferences: URL scheme.
//  Individual JSON entries may carry a `settings_url` override for more
//  specific anchors (e.g. a particular Privacy sub-pane).
//

import Foundation

enum SettingsURLResolver {

    /// Returns the best System Settings URL for a given entry, or nil if none exists.
    static func url(for entry: DefaultEntry) -> URL? {
        // Per-entry JSON override wins
        if let override = entry.settingsURL, let url = URL(string: override) {
            return url
        }
        guard let pane = paneIdentifier(domain: entry.domain, category: entry.category) else {
            return nil
        }
        return URL(string: "x-apple.systempreferences:\(pane)")
    }

    // MARK: - Domain → Pane mapping

    private static func paneIdentifier(domain: String, category: String) -> String? {
        switch domain {

        // Dock
        case "com.apple.dock":
            return "com.apple.preference.dock"

        // Finder — no System Settings pane; Finder has its own Preferences menu
        case "com.apple.finder", "com.apple.desktopservices", "com.apple.frameworks.diskimages",
             "com.apple.NetworkBrowser":
            return nil

        // Screenshots — no dedicated pane (settings live in the Screenshot app itself)
        case "com.apple.screencapture":
            return nil

        // Screen saver / Desktop
        case "com.apple.screensaver":
            return "com.apple.preference.desktopscreeneffect"

        // Accessibility
        case "com.apple.universalaccess":
            return "com.apple.Accessibility"

        // Trackpad
        case "com.apple.AppleMultitouchTrackpad",
             "com.apple.driver.AppleBluetoothMultitouch.trackpad":
            return "com.apple.preference.trackpad"

        // Mouse
        case "com.apple.driver.AppleBluetoothMultitouch.mouse":
            return "com.apple.preference.mouse"

        // Bluetooth
        case "com.apple.BluetoothAudioAgent":
            return "com.apple.BluetoothSettings"

        // Software Update
        case "com.apple.SoftwareUpdate":
            return "com.apple.Software-Update-Settings.extension"

        // Login window / Users & Groups
        case "com.apple.loginwindow":
            return "com.apple.preferences.users"

        // Clock / Control Center
        case "com.apple.menuextra.clock":
            return "com.apple.ControlCenter-Settings.extension"

        // Battery (menu bar icon)
        case "com.apple.menuextra.battery":
            return "com.apple.Battery"

        // Mission Control / Spaces
        case "com.apple.spaces":
            return "com.apple.preference.expose"

        // Time Machine
        case "com.apple.TimeMachine":
            return "com.apple.Time-Machine-Settings.extension"

        // Printing
        case "com.apple.print.PrintingPrefs":
            return "com.apple.preference.printfax"

        // Window Manager (Ventura+)
        case "com.apple.WindowManager":
            return "com.apple.Desktop-Settings.extension"

        // App Store / Commerce
        case "com.apple.appstore", "com.apple.commerce":
            return "com.apple.preferences.appstore"

        // Siri
        case "com.apple.Siri":
            return "com.apple.preference.speech"

        // System Preferences / Resume
        case "com.apple.systempreferences":
            return "com.apple.systempreferences.GeneralSettings"

        // Crash Reporter, ImageCapture — no relevant Settings pane
        case "com.apple.CrashReporter", "com.apple.ImageCapture":
            return nil

        // Simulator / Xcode — no pane
        case "com.apple.iphonesimulator", "com.apple.dt.Xcode":
            return nil

        // App-only settings (no System Settings pane)
        case "com.apple.Safari", "com.apple.mail", "com.apple.Mail",
             "com.apple.terminal", "com.apple.Terminal",
             "com.apple.ActivityMonitor", "com.apple.TextEdit",
             "com.apple.MobileSMS", "com.apple.Music", "com.apple.iTunes",
             "com.apple.addressbook", "com.apple.iCal", "com.apple.reminders",
             "com.apple.dashboard", "org.x.X11",
             "com.apple.helpviewer", "com.apple.LaunchServices",
             "com.apple.CloudSubscriptionFeatures.optIn",
             "com.apple.appleseed.FeedbackAssistant",
             "com.apple.DiskUtility", "com.apple.QuickTimePlayerX":
            return nil

        // NSGlobalDomain — resolve by category
        case "NSGlobalDomain", "Apple Global Domain", "kCFPreferencesAnyApplication",
             "com.apple.HIToolbox":
            return globalDomainPane(for: category)

        default:
            return nil
        }
    }

    /// NSGlobalDomain spans many categories — pick the most relevant pane.
    private static func globalDomainPane(for category: String) -> String? {
        switch category {
        case "Window Manager":
            return "com.apple.Desktop-Settings.extension"
        case "App Store":
            return "com.apple.preferences.appstore"
        case "Keyboard":
            return "com.apple.preference.keyboard"
        case "Trackpad":
            return "com.apple.preference.trackpad"
        case "Mouse":
            return "com.apple.preference.mouse"
        case "Dock":
            return "com.apple.preference.dock"
        case "Screen", "Screenshots":
            return "com.apple.preference.displays"
        case "Accessibility":
            return "com.apple.Accessibility"
        case "Language & Region":
            return "com.apple.Localization-Settings.extension"
        case "General", "Input":
            return "com.apple.systempreferences.GeneralSettings"
        default:
            return "com.apple.systempreferences.GeneralSettings"
        }
    }
}
