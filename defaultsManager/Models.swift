//
//  Models.swift
//  defaultsManager
//

import Foundation

// MARK: - Default Entry

nonisolated struct DefaultEntry: Identifiable, Codable, Hashable {
    var id: String { "\(domain)|\(key)" }
    let domain: String
    let key: String
    let value: String
    let type: DefaultValueType
    let category: String
    let allValues: [String]?
    let sources: [String]?
    let description: String?
    let settingsURL: String?   // optional per-key override for System Settings deep link
    let restartAction: String? // optional override: "Dock", "Finder", "SystemUIServer", "logout", "none"

    enum CodingKeys: String, CodingKey {
        case domain, key, value, type, category, sources, description
        case allValues = "all_values"
        case settingsURL = "settings_url"
        case restartAction = "restart_action"
    }
}

// MARK: - Value Type

nonisolated enum DefaultValueType: String, Codable, CaseIterable {
    case string
    case integer
    case float
    case bool
    case array
    case dict
    case data

    var isEditable: Bool {
        switch self {
        case .string, .integer, .float, .bool: return true
        default: return false
        }
    }

    /// The flag to pass to `defaults write`
    var defaultsFlag: String {
        switch self {
        case .string: return "-string"
        case .integer: return "-integer"
        case .float: return "-float"
        case .bool: return "-bool"
        case .array: return "-array"
        case .dict: return "-dict"
        case .data: return "-data"
        }
    }
}

// MARK: - Sidebar Navigation

enum SidebarItem: Hashable {
    case favorites
    case changed
    case category(String)
}

// MARK: - Backup Entry

nonisolated struct BackupEntry: Codable {
    let domain: String
    let key: String
    let value: String
    let type: DefaultValueType
    let backedUpAt: Date
    /// false if the key did not exist when backed up — restoring then deletes it.
    /// Optional so backups written by older versions still decode (nil = was set).
    var wasSet: Bool?
}
