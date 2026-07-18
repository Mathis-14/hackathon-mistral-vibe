//
//  PermissionsBanner.swift
//  Vibe Buddy
//
//  Amber banner shown at the top of the panel while a permission the demo
//  path depends on is missing. Each row deep-links to the right pane of
//  System Settings (and triggers the system prompt where macOS allows it),
//  so a fresh install self-serves instead of needing a debugging session.
//

import AppKit
import SwiftUI

struct PermissionsBanner: View {
    let needsAccessibility: Bool
    let needsScreenRecording: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.warning)
                Text("Finish setup to unlock Vibe Buddy")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
            }

            if needsAccessibility {
                permissionRow(
                    title: "Accessibility",
                    detail: "hotkeys & push-to-talk",
                    action: openAccessibilitySettings
                )
            }
            if needsScreenRecording {
                permissionRow(
                    title: "Screen Recording",
                    detail: "screen-aware answers — relaunch after granting",
                    action: requestScreenRecording
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Colors.warning.opacity(0.10))
        .overlay(alignment: .leading) {
            Rectangle().fill(DS.Colors.warning).frame(width: 3)
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textSecondary)
            }
            Spacer(minLength: 8)
            Button("Enable", action: action)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DS.Colors.warning, in: Capsule())
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func requestScreenRecording() {
        // Registers the app in the Screen Recording list and prompts when
        // macOS allows it; the settings pane opens either way.
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview("Permissions banner") {
    PermissionsBanner(needsAccessibility: true, needsScreenRecording: true)
        .frame(width: 400)
        .background(DS.Colors.background)
}
