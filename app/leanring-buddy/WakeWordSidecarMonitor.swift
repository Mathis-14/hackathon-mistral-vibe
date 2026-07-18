//
//  WakeWordSidecarMonitor.swift
//  Vibe Buddy
//
//  Spawns the Python wake-word sidecar (app/wakeword/hey_vibe_sidecar.py)
//  and fires a callback whenever it prints "WAKE" on stdout. The sidecar is
//  optional tooling for the demo machine: if the directory, venv or model
//  files are missing, the monitor logs once and stays off — the app is
//  fully functional without it (fn+control still summons the panel).
//

import Foundation

@MainActor
final class WakeWordSidecarMonitor {
    static let enabledDefaultsKey = "vibebuddy.wakeword"
    static let directoryDefaultsKey = "vibebuddy.wakewordDir"

    /// Fired on the main actor each time the sidecar detects "Hey Vibe".
    var onWake: (() -> Void)?

    private var process: Process?
    private var restartCount = 0
    private let maxRestarts = 5

    private var sidecarDirectory: URL {
        if let override = UserDefaults.standard.string(forKey: Self.directoryDefaultsKey) {
            return URL(fileURLWithPath: override)
        }
        // Demo-machine default: the repo checkout. Harmless elsewhere — the
        // existence checks below just turn the feature off.
        return URL(fileURLWithPath: "/Users/edouardfoussier/code/hackathons/wkd-hacks/mistral-vibe-hack/hackathon-mistral-vibe/app/wakeword")
    }

    func startIfAvailable() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.enabledDefaultsKey) as? Bool == false {
            print("🎧 Wake word: disabled via defaults")
            return
        }

        let directory = sidecarDirectory
        let python = directory.appendingPathComponent(".venv/bin/python")
        let script = directory.appendingPathComponent("hey_vibe_sidecar.py")
        let model = directory.appendingPathComponent("hey_vibe.onnx")
        let modelData = directory.appendingPathComponent("hey_vibe.onnx.data")

        let fileManager = FileManager.default
        for required in [python, script, model, modelData] where !fileManager.fileExists(atPath: required.path) {
            print("🎧 Wake word: OFF — missing \(required.lastPathComponent) in \(directory.path)")
            return
        }

        launch(python: python, script: script)
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    private func launch(python: URL, script: URL) {
        let sidecar = Process()
        sidecar.executableURL = python
        sidecar.arguments = [script.path, "--threshold", "0.45", "--cooldown", "2.0"]
        sidecar.currentDirectoryURL = script.deletingLastPathComponent()

        let stdout = Pipe()
        sidecar.standardOutput = stdout
        sidecar.standardError = FileHandle.standardError

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let lines = String(decoding: handle.availableData, as: UTF8.self)
            for line in lines.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                Task { @MainActor [weak self] in
                    switch trimmed {
                    case "READY":
                        print("🎧 Wake word ACTIVE — say « Hey Vibe »")
                        self?.restartCount = 0
                    case "WAKE":
                        print("🎧 Wake word fired")
                        self?.onWake?()
                    default:
                        break
                    }
                }
            }
        }

        sidecar.terminationHandler = { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.process = nil
                guard self.restartCount < self.maxRestarts else {
                    print("🎧 Wake word: sidecar keeps dying (status \(finished.terminationStatus)) — giving up")
                    return
                }
                self.restartCount += 1
                print("🎧 Wake word: sidecar exited (status \(finished.terminationStatus)) — restart \(self.restartCount)/\(self.maxRestarts) in 3s")
                try? await Task.sleep(for: .seconds(3))
                self.startIfAvailable()
            }
        }

        do {
            try sidecar.run()
            process = sidecar
            print("🎧 Wake word: sidecar launched (pid \(sidecar.processIdentifier))")
        } catch {
            print("🎧 Wake word: failed to launch sidecar — \(error.localizedDescription)")
        }
    }
}
