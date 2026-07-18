//
//  VibeAgentLauncher.swift
//  Vibe Buddy
//
//  Launches a Mistral Vibe Code CLI agent (`vibe -p`) on the configured
//  project directory. Fire-and-forget: the spawned agent writes its session
//  under ~/.vibe/logs/session within seconds, where VibeSessionWatcher picks
//  it up — status, title and live cost appear in the panel's VIBE CODE
//  SESSIONS strip without any extra plumbing.
//
//  Interface contract verified live on vibe 2.21.0 (see docs in the repo):
//  --trust is required for non-interactive runs, --max-price caps spend.
//

import Foundation

@MainActor
enum VibeAgentLauncher {
    static let projectDirectoryDefaultsKey = "vibebuddy.projectDirectory"

    private static let vibeBinaryCandidates = [
        NSHomeDirectory() + "/.local/bin/vibe",
        "/usr/local/bin/vibe",
        "/opt/homebrew/bin/vibe",
    ]

    static var projectDirectory: String {
        UserDefaults.standard.string(forKey: projectDirectoryDefaultsKey)
            ?? "/Users/edouardfoussier/code/hackathons/wkd-hacks/mistral-vibe-hack/demo-repo"
    }

    /// Spawns a detached Vibe Code agent for `task`. Returns the project
    /// directory it runs in, or nil when the vibe binary is missing.
    @discardableResult
    static func launch(task: String) -> String? {
        guard let vibeBinary = vibeBinaryCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            print("🧑‍💻 Vibe launcher: no vibe binary found — install the Vibe Code CLI")
            return nil
        }

        let directory = projectDirectory
        let agent = Process()
        agent.executableURL = URL(fileURLWithPath: vibeBinary)
        agent.arguments = [
            "-p", task,
            "--output", "streaming",
            "--trust",
            "--auto-approve",
            "--max-price", "1.0",
            "--max-turns", "25",
        ]
        agent.currentDirectoryURL = URL(fileURLWithPath: directory)
        agent.environment = ProcessInfo.processInfo.environment
        agent.standardOutput = FileHandle.nullDevice
        agent.standardError = FileHandle.nullDevice

        do {
            try agent.run()
            print("🧑‍💻 Vibe launcher: agent started (pid \(agent.processIdentifier)) in \(directory)")
            return directory
        } catch {
            print("🧑‍💻 Vibe launcher: failed to start — \(error.localizedDescription)")
            return nil
        }
    }

    /// Extracts a Vibe Code task from user input when it uses one of the
    /// launch prefixes: typed "/vibe <task>" or spoken "Vibe, <task>" /
    /// "Vibe <task>". Returns nil for normal chat messages.
    static func task(fromInput input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()

        for prefix in ["/vibe ", "vibe, ", "vibe "] where lowered.hasPrefix(prefix) {
            let task = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return task.isEmpty ? nil : task
        }
        return nil
    }
}
