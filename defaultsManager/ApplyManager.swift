//
//  ApplyManager.swift
//  defaultsManager
//

import Foundation

/// Thin wrapper around `/usr/bin/defaults`. Stateless and safe to call from any thread.
nonisolated enum ApplyManager {

    enum ApplyError: LocalizedError {
        case unsupportedType(DefaultValueType)
        case needsFullDiskAccess(String)   // domain is in a sandbox container
        case invalidValue(String, DefaultValueType)
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let t):
                return "Cannot write value of type '\(t.rawValue)' — edit not supported."
            case .needsFullDiskAccess(let domain):
                return "'\(domain)' runs in a sandbox container. defaultsManager needs Full Disk Access to modify its preferences."
            case .invalidValue(let value, let type):
                switch type {
                case .bool:    return "'\(value)' is not a valid boolean — use true or false."
                case .integer: return "'\(value)' is not a valid integer."
                case .float:   return "'\(value)' is not a valid number."
                default:       return "'\(value)' is not a valid \(type.rawValue) value."
                }
            case .commandFailed(let msg):
                return "defaults write failed: \(msg)"
            }
        }
    }

    /// Returns true if the domain stores its prefs inside ~/Library/Containers (sandboxed app).
    static func isContainerised(domain: String) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(domain)")
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Returns true if writing to this domain will fail due to missing Full Disk Access.
    /// Probes by running `defaults read <domain>` and checking for a permission error.
    static func needsFullDiskAccess(for domain: String) -> Bool {
        guard isContainerised(domain: domain) else { return false }
        // `defaults read <domain>` exits 0 when accessible (even if domain is empty).
        // It exits non-zero with "Could not read domain" when FDA is required.
        // stdout (the whole domain dump) is not needed — discard it.
        let result = runDefaults(["read", domain], captureStdout: false)
        return result.exitCode != 0 && result.output.contains("Could not read domain")
    }

    /// Reads the current system value for the given entry.
    /// Returns nil if not set or on error.
    static func readCurrentValue(domain: String, key: String) -> String? {
        let args = domainArgs(for: domain) + [key]
        let result = runDefaults(["read"] + args, captureStderr: false)
        guard result.exitCode == 0 else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validates `raw` for `type` and converts it into the canonical form
    /// `defaults write` expects. `defaults` silently writes 0 for unparsable
    /// numbers (e.g. "0,5" or "abc") and rejects "1"/"0" for `-bool`, so this
    /// must run before every write.
    static func normalisedValue(_ raw: String, for type: DefaultValueType) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .bool:
            switch trimmed.lowercased() {
            case "true", "yes", "1":  return "true"
            case "false", "no", "0":  return "false"
            default: throw ApplyError.invalidValue(raw, type)
            }
        case .integer:
            guard let i = Int(trimmed) else { throw ApplyError.invalidValue(raw, type) }
            return String(i)
        case .float:
            // Accept a decimal comma (German / European locales).
            let dotted = trimmed.replacingOccurrences(of: ",", with: ".")
            guard let d = Double(dotted), d.isFinite else { throw ApplyError.invalidValue(raw, type) }
            return dotted
        case .string:
            // Documented values come from shell scripts; `Process` does no
            // shell expansion, so "${HOME}" would otherwise be written literally.
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return raw
                .replacingOccurrences(of: "${HOME}", with: home)
                .replacingOccurrences(of: "$HOME", with: home)
        case .array, .dict, .data:
            throw ApplyError.unsupportedType(type)
        }
    }

    /// Writes a new value to the system using `defaults write`.
    static func write(domain: String, key: String, value: String, type: DefaultValueType) throws {
        guard type.isEditable else {
            throw ApplyError.unsupportedType(type)
        }
        let normalised = try normalisedValue(value, for: type)
        let domainPart = domainArgs(for: domain)
        let args = ["write"] + domainPart + [key, type.defaultsFlag, normalised]
        let result = runDefaults(args)
        if result.exitCode != 0 {
            if needsFullDiskAccess(for: domain) {
                throw ApplyError.needsFullDiskAccess(domain)
            }
            throw ApplyError.commandFailed(result.output)
        }
    }

    /// Deletes a key from the system defaults.
    static func delete(domain: String, key: String) throws {
        let args = ["delete"] + domainArgs(for: domain) + [key]
        let result = runDefaults(args)
        if result.exitCode != 0 {
            throw ApplyError.commandFailed(result.output)
        }
    }

    // MARK: - Typed plist access (used by full backup / restore)

    /// Reads a whole domain as a property-list dictionary.
    /// A domain that does not exist yet yields an empty dictionary.
    static func exportDomain(_ domain: String) throws -> [String: Any] {
        let result = runDefaults(["export"] + domainArgs(for: domain) + ["-"])
        guard result.exitCode == 0 else {
            if needsFullDiskAccess(for: domain) { throw ApplyError.needsFullDiskAccess(domain) }
            throw ApplyError.commandFailed(result.output)
        }
        guard let data = result.output.data(using: .utf8),
              let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw ApplyError.commandFailed("unexpected export output for \(domain)") }
        return dict
    }

    /// Writes one key with its exact plist type (bool, real, array, dict, date, data …)
    /// via `defaults write <domain> <key> '<xml fragment>'`. Leaves all other keys untouched.
    static func writePlistValue(domain: String, key: String, value: Any) throws {
        try writePlistFragment(domain: domain, key: key, fragment: plistFragment(for: value))
    }

    /// Same as `writePlistValue`, with the value already encoded by `plistFragment(for:)`.
    static func writePlistFragment(domain: String, key: String, fragment: String) throws {
        let args = ["write"] + domainArgs(for: domain) + [key, fragment]
        let result = runDefaults(args)
        guard result.exitCode == 0 else {
            if needsFullDiskAccess(for: domain) { throw ApplyError.needsFullDiskAccess(domain) }
            throw ApplyError.commandFailed(result.output)
        }
    }

    /// `<integer>5</integer>`, `<true/>`, `<array>…</array>` — the XML body of a plist.
    static func plistFragment(for value: Any) throws -> String {
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        let xml = String(decoding: data, as: UTF8.self)
        guard let start = xml.range(of: "<plist version=\"1.0\">"),
              let end = xml.range(of: "</plist>", options: .backwards)
        else { throw ApplyError.commandFailed("could not encode value") }
        return xml[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Short human-readable rendering of a plist value for the UI.
    static func displayString(for value: Any?) -> String {
        guard let value else { return "(not set)" }
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        }
        if let s = value as? String { return s }
        if let a = value as? [Any] { return "[" + a.map { displayString(for: $0) }.joined(separator: ", ") + "]" }
        if let d = value as? [String: Any] {
            return "{" + d.keys.sorted().map { "\($0) = \(displayString(for: d[$0]))" }.joined(separator: "; ") + "}"
        }
        if let data = value as? Data { return "<\(data.count) bytes>" }
        if let date = value as? Date { return ISO8601DateFormatter().string(from: date) }
        return String(describing: value)
    }

    // MARK: - Shell command rendering

    /// A copy-pasteable `defaults write …` command with all arguments shell-quoted.
    static func shellCommand(domain: String, key: String, type: DefaultValueType, value: String) -> String {
        let parts = ["defaults", "write"] + domainArgs(for: domain).map(shellQuote)
            + [shellQuote(key), type.defaultsFlag, shellQuote(value)]
        return parts.joined(separator: " ")
    }

    /// Quotes `s` for POSIX shells. Plain words are returned unchanged.
    static func shellQuote(_ s: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.,:/@%+=")
        if !s.isEmpty, s.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return s
        }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Helpers

    static func domainArgs(for domain: String) -> [String] {
        switch domain {
        case "Apple Global Domain", "NSGlobalDomain", "":
            return ["-globalDomain"]
        default:
            return [domain]
        }
    }

    private struct RunResult {
        let exitCode: Int32
        let output: String
    }

    /// Runs `defaults` and collects its output. stdout and stderr are drained
    /// concurrently *before* waiting for exit — otherwise a large domain dump
    /// (>64 KB pipe buffer) blocks the child and `waitUntilExit()` never returns.
    private static func runDefaults(_ args: [String],
                                    captureStdout: Bool = true,
                                    captureStderr: Bool = true) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = args

        let outPipe = captureStdout ? Pipe() : nil
        let errPipe = captureStderr ? Pipe() : nil
        process.standardOutput = outPipe ?? FileHandle.nullDevice
        process.standardError = errPipe ?? FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return RunResult(exitCode: -1, output: error.localizedDescription)
        }

        var errData = Data()
        let group = DispatchGroup()
        if let errPipe {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
        }
        let outData = outPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        group.wait()
        process.waitUntilExit()

        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        let combined = (out + err).trimmingCharacters(in: .whitespacesAndNewlines)
        return RunResult(exitCode: process.terminationStatus, output: combined)
    }
}
