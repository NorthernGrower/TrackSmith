//
//  CrashReporter.swift
//  AI Music Studio
//

import Foundation

private let crashReportKey = "com.tracksmith.crash.report"
private let crashBreadcrumbKey = "com.tracksmith.crash.screen"

private let crashLogURL: URL? = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    guard let base else { return nil }
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base.appendingPathComponent("crash.log")
}()

private func crashPendingFlagURL() -> URL? {
    crashLogURL?.deletingLastPathComponent().appendingPathComponent("crash-pending")
}

private func appendCrashLog(_ note: String) {
    guard let logURL = crashLogURL else { return }
    let entry = "\(note) — \(Date())\n"
    if let existing = try? String(contentsOf: logURL, encoding: .utf8) {
        // Keep the log from growing without bound during long sessions.
        let trimmed = existing.count > 40_000
            ? String(existing.suffix(20_000))
            : existing
        try? (trimmed + entry).write(to: logURL, atomically: true, encoding: .utf8)
    } else {
        try? entry.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

private func truncateCrashLog() {
    guard let logURL = crashLogURL else { return }
    try? "session start".write(to: logURL, atomically: true, encoding: .utf8)
}

private func crashLogTail() -> String? {
    guard let logURL = crashLogURL,
          let contents = try? String(contentsOf: logURL, encoding: .utf8),
          !contents.isEmpty else { return nil }

    let lines = contents.split(separator: "\n")
    let tail = lines.suffix(12).joined(separator: "\n")
    truncateCrashLog()
    return tail
}

/// Records uncaught NSExceptions and stage breadcrumbs to disk, so even a
/// crash that closes the app silently can be traced on the next launch.
final class CrashReporter {
    static let shared = CrashReporter()

    private init() {}

    /// Installs the uncaught-exception handler and marks the session as running.
    func install() {
        NSSetUncaughtExceptionHandler { exception in
            let screen = UserDefaults.standard.string(forKey: crashBreadcrumbKey) ?? "unknown"
            let report = [
                "name: \(exception.name.rawValue)",
                "reason: \(exception.reason ?? "none")",
                "screen: \(screen)",
                "stack: \(exception.callStackSymbols.prefix(8).joined(separator: " | "))",
            ].joined(separator: "\n")
            UserDefaults.standard.set(report, forKey: crashReportKey)
            appendCrashLog(report)
        }
        appendCrashLog("session start")
        if let pendingURL = crashPendingFlagURL() {
            try? "1".write(to: pendingURL, atomically: true, encoding: .utf8)
        }
    }

    /// Marks the session as ended cleanly, so the next launch knows the app
    /// was closed normally rather than by a crash.
    func endSession() {
        if let pendingURL = crashPendingFlagURL() {
            try? FileManager.default.removeItem(at: pendingURL)
        }
        appendCrashLog("session ended cleanly")
    }

    /// Records what the app was doing, so a crash can be traced to a screen.
    func mark(_ note: String) {
        UserDefaults.standard.set(note, forKey: crashBreadcrumbKey)
        appendCrashLog(note)
    }

    /// The most recent breadcrumb, useful when a crash leaves no report behind.
    var currentBreadcrumb: String {
        UserDefaults.standard.string(forKey: crashBreadcrumbKey) ?? "unknown"
    }

    /// Returns the crash recorded on the previous run, if any, and clears it.
    func takePendingReport() -> String? {
        defer {
            if let pendingURL = crashPendingFlagURL() {
                try? FileManager.default.removeItem(at: pendingURL)
            }
        }

        if let report = UserDefaults.standard.string(forKey: crashReportKey) {
            UserDefaults.standard.removeObject(forKey: crashReportKey)
            truncateCrashLog()
            return report
        }

        guard let pendingURL = crashPendingFlagURL(),
              FileManager.default.fileExists(atPath: pendingURL.path) else {
            return nil
        }

        return crashLogTail()
    }
}
