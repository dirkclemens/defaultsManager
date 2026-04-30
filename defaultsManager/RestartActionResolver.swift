//
//  RestartActionResolver.swift
//  defaultsManager
//

import AppKit

// MARK: - Restart Action

enum RestartAction: Equatable {
    case killProcess(String)  // terminate app by process name (Dock, Finder, SystemUIServer…)
    case logout               // changes require logging out and back in
    case none                 // takes effect immediately; no restart needed
}

// MARK: - Resolver

struct RestartActionResolver {

    /// Determines what restart action is needed after changing `entry`.
    /// Explicit `restart_action` in JSON takes priority; domain-level mapping is the fallback.
    static func action(for entry: DefaultEntry) -> RestartAction {
        if let explicit = entry.restartAction {
            return parse(explicit)
        }
        return domainFallback(for: entry.domain)
    }

    /// Terminates the target process via POSIX kill() — no LaunchServices, no sandbox restriction.
    /// Dock, Finder, and SystemUIServer all auto-relaunch after receiving SIGTERM.
    static func perform(_ action: RestartAction) {
        guard case .killProcess(let name) = action else { return }
        let bundleID = bundleIdentifier(for: name)
        let apps = bundleID != nil
            ? NSRunningApplication.runningApplications(withBundleIdentifier: bundleID!)
            : NSWorkspace.shared.runningApplications.filter { $0.localizedName == name }
        apps.forEach { kill($0.processIdentifier, SIGTERM) }
    }

    // MARK: - Private

    private static func parse(_ raw: String) -> RestartAction {
        switch raw.lowercased() {
        case "none":   return .none
        case "logout": return .logout
        default:       return .killProcess(raw)
        }
    }

    private static func domainFallback(for domain: String) -> RestartAction {
        switch domain {
        case "com.apple.dock":
            return .killProcess("Dock")
        case "com.apple.finder":
            return .killProcess("Finder")
        case "com.apple.systemuiserver",
             "com.apple.screencapture",
             "com.apple.menuextra.clock",
             "com.apple.menuextra.battery":
            return .killProcess("SystemUIServer")
        case "com.apple.universalaccess":
            return .logout
        default:
            return .none
        }
    }

    /// Maps friendly process names to bundle identifiers for reliable lookup.
    private static func bundleIdentifier(for name: String) -> String? {
        switch name {
        case "Dock":            return "com.apple.dock"
        case "Finder":          return "com.apple.finder"
        case "SystemUIServer":  return "com.apple.SystemUIServer"
        default:                return nil
        }
    }
}
