//
//  ApplyManager.swift
//  defaultsManager
//

import Foundation

class ApplyManager {

    enum ApplyError: LocalizedError {
        case unsupportedType(DefaultValueType)
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let t): return "Cannot write value of type '\(t.rawValue)' — edit not supported."
            case .commandFailed(let msg): return "defaults write failed: \(msg)"
            }
        }
    }

    /// Reads the current system value for the given entry.
    /// Returns nil if not set or on error.
    static func readCurrentValue(domain: String, key: String) -> String? {
        let args = domainArgs(for: domain) + [key]
        let result = runDefaults(["read"] + args)
        guard result.exitCode == 0 else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Writes a new value to the system using `defaults write`.
    static func write(domain: String, key: String, value: String, type: DefaultValueType) throws {
        guard type.isEditable else {
            throw ApplyError.unsupportedType(type)
        }
        let domainPart = domainArgs(for: domain)
        let args = ["write"] + domainPart + [key, type.defaultsFlag, value]
        let result = runDefaults(args)
        if result.exitCode != 0 {
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

    // MARK: - Helpers

    private static func domainArgs(for domain: String) -> [String] {
        switch domain {
        case "Apple Global Domain", "NSGlobalDomain":
            return ["-globalDomain"]
        case "":
            return ["-globalDomain"]
        default:
            return [domain]
        }
    }

    private struct RunResult {
        let exitCode: Int32
        let output: String
    }

    private static func runDefaults(_ args: [String]) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return RunResult(exitCode: -1, output: error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        let combined = (out + err).trimmingCharacters(in: .whitespacesAndNewlines)
        return RunResult(exitCode: process.terminationStatus, output: combined)
    }
}
