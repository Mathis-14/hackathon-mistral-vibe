//
//  PermissionsGlanceView.swift
//  Vibe Buddy
//
//  All macOS permissions at a glance — green checks when granted, one-click
//  Enable when not. Shown at the top of the routines/settings tab; the
//  amber PermissionsBanner still handles the missing-permission nudge on
//  the chat tab.
//

import AppKit
import SwiftUI

struct PermissionsGlanceView: View {
    @ObservedObject var companionManager: CompanionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PERMISSIONS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(DS.Colors.textTertiary)

            permissionRow(
                title: "Accessibility",
                detail: "hotkeys & push-to-talk",
                granted: companionManager.hasAccessibilityPermission,
                pane: "Privacy_Accessibility"
            )
            permissionRow(
                title: "Screen Recording",
                detail: "screen-aware answers",
                granted: companionManager.hasScreenRecordingPermission,
                pane: "Privacy_ScreenCapture"
            )
            permissionRow(
                title: "Microphone",
                detail: "Voxtral voice input",
                granted: companionManager.hasMicrophonePermission,
                pane: "Privacy_Microphone"
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Colors.surface1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        pane: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(granted ? DS.Colors.success : DS.Colors.warning)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.Colors.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textSecondary)
            }

            Spacer(minLength: 8)

            if !granted {
                Button("Enable") {
                    if pane == "Privacy_ScreenCapture" {
                        CGRequestScreenCaptureAccess()
                    }
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DS.Colors.warning, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}
