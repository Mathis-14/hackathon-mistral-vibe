//
//  VibeWorkTeleporter.swift
//  Vibe Buddy
//
//  "Open in Vibe Work": teleports a local project to Vibe Code Web
//  (chat.mistral.ai) through the Vibe CLI's hidden headless mode —
//  `vibe -p <prompt> --teleport --trust` — which creates a cloud session
//  and prints its URL (https://chat.mistral.ai/code/<projectId>/<webSessionId>)
//  as the last stdout line. Full mechanism + file:line citations into the
//  CLI source: docs/vibe-work-bridge.md.
//
//  Auth stays entirely inside the CLI (MISTRAL_API_KEY env or macOS
//  keyring) — no keys ever touch the app.
//
//  Side effects, by CLI design (vibe/core/programmatic.py): headless
//  teleport AUTO-PUSHES unpushed commits on the current branch and creates
//  a real cloud session (account compute); first run may create a Vibe
//  Code Web project. Preconditions: git repo with a GitHub remote, a
//  checked-out branch, and a resolvable MISTRAL_API_KEY.
//
//  Standalone helper by design — the integrator wires it to a button, e.g.:
//      VibeWorkTeleporter.teleportAndOpen(
//          prompt: "Continue this task in the cloud",
//          projectDirectory: session.workingDirectory)
//

import AppKit
import Foundation

enum VibeWorkTeleporter {
    enum TeleportFailure: Error, Equatable {
        case vibeBinaryMissing
        case projectDirectoryMissing(String)
        case timedOut
        case failed(message: String)
        case noURLInOutput

        var message: String {
            switch self {
            case .vibeBinaryMissing:
                return "Vibe CLI not found — install the Vibe Code CLI"
            case .projectDirectoryMissing(let path):
                return "Project directory not found: \(path)"
            case .timedOut:
                return "Teleport timed out"
            case .failed(let message):
                return message.isEmpty ? "Teleport failed" : message
            case .noURLInOutput:
                return "Teleport finished without printing a session URL"
            }
        }
    }

    private static let vibeBinaryCandidates = [
        NSHomeDirectory() + "/.local/bin/vibe",
        "/usr/local/bin/vibe",
        "/opt/homebrew/bin/vibe",
    ]

    /// Teleports `projectDirectory` to Vibe Code Web with `prompt` as the
    /// cloud agent's task. Runs the CLI off the main thread; `completion`
    /// is delivered on the main queue with the cloud session URL.
    static func teleport(
        prompt: String,
        projectDirectory: String,
        timeout: TimeInterval = 180,
        completion: @escaping (Result<URL, TeleportFailure>) -> Void
    ) {
        let finish: (Result<URL, TeleportFailure>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }

        guard let vibeBinary = vibeBinaryCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            print("🛸 Vibe Work: no vibe binary found")
            finish(.failure(.vibeBinaryMissing))
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectDirectory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            finish(.failure(.projectDirectoryMissing(projectDirectory)))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            finish(runTeleport(
                vibeBinary: vibeBinary,
                prompt: prompt,
                projectDirectory: projectDirectory,
                timeout: timeout
            ))
        }
    }

    /// Convenience: teleport, then open the returned cloud session in the
    /// default browser. Failures are logged and passed to `onFailure`.
    static func teleportAndOpen(
        prompt: String,
        projectDirectory: String,
        onFailure: ((TeleportFailure) -> Void)? = nil
    ) {
        teleport(prompt: prompt, projectDirectory: projectDirectory) { result in
            switch result {
            case .success(let url):
                print("🛸 Vibe Work: opening \(url.absoluteString)")
                NSWorkspace.shared.open(url)
            case .failure(let failure):
                print("🛸 Vibe Work: \(failure.message)")
                onFailure?(failure)
            }
        }
    }

    // MARK: - Internals

    /// Blocking; call off the main thread. Spawns
    /// `vibe -p <prompt> --teleport --trust` and parses the last stdout
    /// line that looks like a URL (the CLI's TextOutputFormatter prints the
    /// session URL last; progress lines precede it).
    private static func runTeleport(
        vibeBinary: String,
        prompt: String,
        projectDirectory: String,
        timeout: TimeInterval
    ) -> Result<URL, TeleportFailure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: vibeBinary)
        process.arguments = ["-p", prompt, "--teleport", "--trust"]
        process.currentDirectoryURL = URL(fileURLWithPath: projectDirectory)
        process.environment = ProcessInfo.processInfo.environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .failure(.failed(message: "Could not start vibe: \(error.localizedDescription)"))
        }
        print("🛸 Vibe Work: teleporting \(projectDirectory) (pid \(process.processIdentifier))")

        var timedOut = false
        let watchdog = DispatchWorkItem {
            if process.isRunning {
                timedOut = true
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // Drain pipes before waiting so a chatty child can never deadlock
        // on a full pipe buffer.
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        if timedOut {
            return .failure(.timedOut)
        }

        let output = String(data: outputData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let errorText = (String(data: errorData, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lastLine = errorText.components(separatedBy: .newlines)
                .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return .failure(.failed(message: lastLine ?? "vibe exited with status \(process.terminationStatus)"))
        }

        guard let url = sessionURL(fromOutput: output) else {
            return .failure(.noURLInOutput)
        }
        return .success(url)
    }

    /// Last stdout line that is a bare https URL — the teleport session
    /// link. Internal for tests.
    static func sessionURL(fromOutput output: String) -> URL? {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let urlLine = lines.last(where: { $0.hasPrefix("https://") }),
              let url = URL(string: urlLine),
              url.host != nil else {
            return nil
        }
        return url
    }
}
