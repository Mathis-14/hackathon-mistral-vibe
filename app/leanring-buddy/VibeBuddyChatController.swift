//
//  VibeBuddyChatController.swift
//  Vibe Buddy
//
//  Owns the chat transcript shown in VibeBuddyPanelView and drives the
//  worker round-trip: user text in → streamed assistant reply out (live
//  worker on 127.0.0.1:8787, or the built-in replay when the worker is
//  unreachable / "vibebuddy.chatMode" == "replay").
//

import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class VibeBuddyChatController: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isStreaming = false
    /// True when the last reply came from the replay fixture — the UI can
    /// badge it so a rehearsal never gets mistaken for a live run.
    @Published private(set) var lastReplyWasReplayed = false

    /// UserDefaults key for the screenshot-context opt-out. Screenshots are
    /// attached unless the user explicitly set this to false:
    /// `defaults write com.vibebuddy.app vibebuddy.includeScreenshot -bool false`
    static let includeScreenshotDefaultsKey = "vibebuddy.includeScreenshot"

    /// Screenshot context is on by default (PRODUCT.md MUST #2); only an
    /// explicit `false` in UserDefaults disables it.
    private var isScreenshotContextEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.includeScreenshotDefaultsKey) as? Bool ?? true
    }

    func submit(_ text: String) {
        guard !isStreaming else { return }

        // "/vibe <task>" (typed) or "Vibe, <task>" (spoken) launches a real
        // Vibe Code CLI agent instead of a chat round-trip. The session
        // watcher surfaces it in the VIBE CODE SESSIONS strip within seconds.
        if let vibeTask = VibeAgentLauncher.task(fromInput: text) {
            messages.append(ChatMessage(id: UUID(), role: .user, text: text))
            let confirmation: String
            if let directory = VibeAgentLauncher.launch(task: vibeTask) {
                let project = URL(fileURLWithPath: directory).lastPathComponent
                confirmation = "🚀 Vibe Code agent launched on \(project): “\(vibeTask)”. Watch it work in VIBE CODE SESSIONS below — cost updates live."
            } else {
                BuddySoundEffects.playHiss()
                confirmation = "I couldn't find the Vibe Code CLI on this Mac — install it with `curl -LsSf https://mistral.ai/vibe/install.sh | bash` and try again."
            }
            messages.append(ChatMessage(id: UUID(), role: .assistant, text: confirmation))
            return
        }

        let userMessageId = UUID()
        messages.append(ChatMessage(id: userMessageId, role: .user, text: text))
        isStreaming = true

        let history = messages.map { message in
            (role: message.role == .user ? "user" : "assistant", content: message.text)
        }

        Task {
            // Captured ONCE per submit, before the request, so the worker
            // sees the screen as it was when the user asked.
            let screenshotData = await captureFrontmostScreenshotJPEG()
            let screenshotBase64 = screenshotData?.base64EncodedString()
            if let screenshotData,
               let userIndex = messages.firstIndex(where: { $0.id == userMessageId }) {
                // Badge the user message and render a real thumbnail so the
                // screen context is visibly attached, not just claimed.
                messages[userIndex].hasScreenshot = true
                messages[userIndex].screenshotThumbnail = Self.thumbnailData(fromJPEG: screenshotData)
            }

            var assistantMessageId: UUID?
            // Every stream token goes through this single parser before
            // anything is displayed or acted on; [OPEN_APP:] actuation always
            // draws its overlay trace, even when the open fails (MUST #6).
            var actuationParser = ActuationTokenParser()

            @MainActor func appendToAssistantMessage(_ text: String) {
                guard !text.isEmpty else { return }
                if let id = assistantMessageId,
                   let index = messages.firstIndex(where: { $0.id == id }) {
                    messages[index].text += text
                } else {
                    let message = ChatMessage(id: UUID(), role: .assistant, text: text)
                    assistantMessageId = message.id
                    messages.append(message)
                }
            }

            @MainActor func actuate(_ appNames: [String]) {
                for appName in appNames {
                    ActuationOverlay.shared.showTrace(appName: appName)
                    ActuationExecutor.openApp(named: appName)
                }
            }

            do {
                let result = try await WorkerChatReplay.streamReply(
                    messages: history,
                    screenshotBase64: screenshotBase64
                ) { delta in
                    let (displayText, appNames) = actuationParser.feed(delta: delta)
                    appendToAssistantMessage(displayText)
                    actuate(appNames)
                }
                appendToAssistantMessage(actuationParser.flush())
                executeTrailingURLToken(onMessageId: assistantMessageId)
                lastReplyWasReplayed = result.isReplayed
            } catch {
                appendToAssistantMessage(actuationParser.flush())
                BuddySoundEffects.playHiss()
                let explanation = "I couldn't reach the worker (\(error.localizedDescription)). Check that wrangler dev is running on 127.0.0.1:8787, or set chat mode to replay."
                messages.append(ChatMessage(id: UUID(), role: .assistant, text: explanation))
            }
            isStreaming = false
        }
    }

    /// The worker contract also allows a single trailing `[OPEN_URL:…]` token
    /// (worker/CONTRACT.md). URLs stream as plain text through the OPEN_APP
    /// parser, so they are handled here on the fully-accumulated reply:
    /// strip the token from the message, open the URL, draw the trace.
    private func executeTrailingURLToken(onMessageId messageId: UUID?) {
        guard let messageId,
              let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let text = messages[index].text
        guard let match = text.range(
            of: #"\[OPEN_URL:([^\]]+)\]\s*$"#,
            options: .regularExpression
        ) else { return }

        let token = String(text[match])
        let urlString = token
            .replacingOccurrences(of: "[OPEN_URL:", with: "")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        messages[index].text = String(text[..<match.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: urlString) else {
            print("🔗 Actuation: invalid OPEN_URL target — \(urlString)")
            return
        }
        ActuationOverlay.shared.showTrace(appName: url.host ?? "Link")
        NSWorkspace.shared.open(url)
    }

    /// Downscales a captured screen JPEG to a ~300px-wide thumbnail for
    /// inline display in the transcript.
    private static func thumbnailData(fromJPEG jpegData: Data) -> Data? {
        guard let image = NSImage(data: jpegData) else { return nil }
        let targetWidth: CGFloat = 300
        let scale = targetWidth / max(image.size.width, 1)
        let targetSize = NSSize(width: targetWidth, height: image.size.height * scale)
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize))
        thumbnail.unlockFocus()
        guard let tiff = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
    }

    /// Captures the frontmost display (the one with the cursor) as a JPEG
    /// no wider than 1280 px, re-encoded at 0.6 quality, and returns it as
    /// raw base64 — NO `data:` URI prefix (see app/CHAT_CONTRACT.md).
    /// Returns nil when the user opted out, capture fails, or the Screen
    /// Recording permission is missing — the chat then proceeds text-only.
    private func captureFrontmostScreenshotJPEG() async -> Data? {
        guard isScreenshotContextEnabled else { return nil }
        do {
            // CompanionScreenCaptureUtility already excludes our own windows
            // and downscales each display to max 1280 px on the long edge.
            let captures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
            guard let capture = captures.first(where: { $0.isCursorScreen }) ?? captures.first else {
                return nil
            }
            // Re-encode at 0.6 quality (the utility emits 0.8) to keep the
            // request body small; fall back to the original data if decoding fails.
            guard let bitmap = NSBitmapImageRep(data: capture.imageData),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else {
                return capture.imageData
            }
            return jpegData
        } catch {
            print("📸 Vibe Buddy: screenshot context unavailable (\(error.localizedDescription)) — sending text only")
            return nil
        }
    }
}

/// Bridges the observable controller to the closure-driven panel view so
/// MenuBarPanelManager can host a plain NSHostingView. Also owns the
/// chat/routines tab switch.
struct VibeBuddyPanelContainer: View {
    @ObservedObject var controller: VibeBuddyChatController
    @ObservedObject var routineStore: RoutineStore
    let routineScheduler: RoutineScheduler
    @ObservedObject var permissionsSource: CompanionManager
    @State private var isShowingRoutines = false
    @StateObject private var vibeSessionWatcher = VibeSessionWatcher()

    private var permissionsBanner: AnyView? {
        let needsAccessibility = !permissionsSource.hasAccessibilityPermission
        let needsScreen = !permissionsSource.hasScreenRecordingPermission
        guard needsAccessibility || needsScreen else { return nil }
        return AnyView(PermissionsBanner(
            needsAccessibility: needsAccessibility,
            needsScreenRecording: needsScreen
        ))
    }

    var body: some View {
        VibeBuddyPanelView(
            messages: controller.messages,
            isStreaming: controller.isStreaming,
            onSubmit: { [weak controller] text in controller?.submit(text) },
            headerAccessory: AnyView(HStack(spacing: 6) {
                routinesToggleButton
                quitButton
            }),
            overrideContent: isShowingRoutines
                ? AnyView(RoutinesView(store: routineStore, scheduler: routineScheduler))
                : nil,
            belowTranscript: vibeSessionWatcher.sessions.isEmpty || isShowingRoutines
                ? nil
                : AnyView(VibeSessionsStrip(sessions: vibeSessionWatcher.sessions)),
            banner: permissionsBanner
        )
        .onAppear { vibeSessionWatcher.start() }
    }

    private var quitButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Image(systemName: "power")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Colors.textTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Quit Vibe Buddy")
    }

    private var routinesToggleButton: some View {
        Button {
            isShowingRoutines.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isShowingRoutines ? "bubble.left.fill" : "clock.arrow.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                if !isShowingRoutines {
                    RoutinesBadge(store: routineStore)
                }
            }
            .foregroundStyle(DS.Colors.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isShowingRoutines ? "Back to chat" : "Routines")
    }
}
