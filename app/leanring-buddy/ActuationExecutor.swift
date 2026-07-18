//
//  ActuationExecutor.swift
//  Vibe Buddy
//
//  Executes a parsed [OPEN_APP:Name] actuation: resolves the app name to a
//  .app bundle on disk and asks NSWorkspace to launch/activate it.
//
//  Resolution is deliberately path-probe based (/Applications,
//  /System/Applications, ...) because NSWorkspace's lookup APIs are bundle-id
//  based, not display-name based. Callers surface the on-screen trace via
//  ActuationOverlay — this type only performs the action and reports success.
//

import AppKit

@MainActor
enum ActuationExecutor {

    /// Directories probed, in order, for "<name>.app".
    private static let applicationDirectories = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        ("~/Applications" as NSString).expandingTildeInPath,
    ]

    /// Resolves an app name (as emitted inside an [OPEN_APP:] token) to the
    /// URL of its .app bundle, or nil if no bundle exists at the known
    /// locations. Tolerates a trailing ".app" in the name.
    static func applicationURL(named appName: String) -> URL? {
        var cleanName = appName.trimmingCharacters(in: .whitespaces)
        if cleanName.lowercased().hasSuffix(".app") {
            cleanName = String(cleanName.dropLast(4))
        }
        guard !cleanName.isEmpty else { return nil }

        for directory in applicationDirectories {
            let candidatePath = "\(directory)/\(cleanName).app"
            if FileManager.default.fileExists(atPath: candidatePath) {
                return URL(fileURLWithPath: candidatePath)
            }
        }
        return nil
    }

    /// Opens (launches or activates) the named app.
    ///
    /// - Returns: true when the app bundle was resolved and the open request
    ///   was dispatched; false when no matching .app could be found (logged).
    @discardableResult
    static func openApp(named appName: String) -> Bool {
        guard let appURL = applicationURL(named: appName) else {
            print("⚠️ Actuation: no .app bundle found for \"\(appName)\" in \(applicationDirectories.joined(separator: ", "))")
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                print("⚠️ Actuation: failed to open \(appURL.path) — \(error.localizedDescription)")
            } else {
                print("🚀 Actuation: opened \(appURL.path)")
            }
        }
        return true
    }
}
