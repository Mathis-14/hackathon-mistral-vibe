//
//  RoutinesView.swift
//  Vibe Buddy
//
//  The routines tab shown INSIDE the panel (passed to VibeBuddyPanelView
//  as `overrideContent`): the routine list with enable toggles, "Run now",
//  relative last-run stamps and expandable artifacts, plus an in-panel
//  add-routine form. `RoutinesBadge` is the compact enabled-count chip the
//  integrator can drop into the panel header (`headerAccessory`).
//
//  All colors/spacing come from DS tokens; the card language matches the
//  chat bubbles (surface fills, subtle borders, orange accents).
//

import SwiftUI

// MARK: - Routines Badge

/// Compact chip showing how many routines are enabled — meant for the
/// panel header, next to the sparkle.
struct RoutinesBadge: View {
    @ObservedObject var store: RoutineStore

    init(store: RoutineStore) {
        self.store = store
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 9, weight: .semibold))
            Text("\(store.enabledCount)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundColor(store.enabledCount > 0 ? DS.Colors.accentText : DS.Colors.textTertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(DS.Colors.surface2))
        .overlay(Capsule().stroke(DS.Colors.borderSubtle, lineWidth: 1))
    }
}

// MARK: - Routines View

struct RoutinesView: View {
    @ObservedObject var store: RoutineStore
    @ObservedObject var scheduler: RoutineScheduler

    @State private var expandedRoutineID: UUID?
    @State private var isPresentingAddForm = false

    init(store: RoutineStore, scheduler: RoutineScheduler) {
        self.store = store
        self.scheduler = scheduler
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                toolbar

                if store.routines.isEmpty {
                    emptyState
                } else {
                    routineList
                }
            }

            if isPresentingAddForm {
                AddRoutineForm(
                    onCancel: {
                        withAnimation(.easeOut(duration: DS.Animation.fast)) {
                            isPresentingAddForm = false
                        }
                    },
                    onCreate: { name, prompt, intervalMinutes in
                        store.add(name: name, prompt: prompt, intervalMinutes: intervalMinutes)
                        withAnimation(.easeOut(duration: DS.Animation.fast)) {
                            isPresentingAddForm = false
                        }
                    }
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("ROUTINES")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(DS.Colors.textTertiary)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: DS.Animation.fast)) {
                    isPresentingAddForm = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("New routine")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(DS.Colors.accentText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(DS.Colors.accentSubtle))
                .overlay(Capsule().stroke(DS.Colors.accent.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: List

    private var routineList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(store.routines) { routine in
                    RoutineRow(
                        routine: routine,
                        isExpanded: expandedRoutineID == routine.id,
                        isRunning: scheduler.isRunning(routine),
                        onToggleExpanded: {
                            withAnimation(.easeOut(duration: DS.Animation.fast)) {
                                expandedRoutineID =
                                    expandedRoutineID == routine.id ? nil : routine.id
                            }
                        },
                        onSetEnabled: { isEnabled in
                            store.setEnabled(isEnabled, for: routine.id)
                        },
                        onRunNow: {
                            scheduler.runNow(routine)
                        },
                        onDelete: {
                            store.remove(routine.id)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(DS.Colors.accentSubtle)
                    .frame(width: 52, height: 52)
                Circle()
                    .stroke(DS.Colors.accent.opacity(0.25), lineWidth: 1)
                    .frame(width: 52, height: 52)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(DS.Colors.accentText)
            }

            VStack(spacing: 5) {
                Text("No routines yet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)

                Text("Schedule a prompt to run on repeat —\nresults land as native macOS alerts.")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .offset(y: -8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Routine Row

private struct RoutineRow: View {
    let routine: Routine
    let isExpanded: Bool
    let isRunning: Bool
    let onToggleExpanded: () -> Void
    let onSetEnabled: (Bool) -> Void
    let onRunNow: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                // Name + meta — tapping this region expands the artifact.
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.Colors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text("every \(Self.intervalLabel(minutes: routine.intervalMinutes))")
                        Text("·")
                        Text(Self.lastRunLabel(for: routine.lastRunAt))
                    }
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggleExpanded)
                .pointerCursor()

                Toggle("", isOn: Binding(get: { routine.isEnabled }, set: onSetEnabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(DS.Colors.accent)
                    .pointerCursor()
            }

            HStack(spacing: 8) {
                if isRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("Running…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.Colors.accentText)
                    }
                } else {
                    Button(action: onRunNow) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text("Run now")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(DS.Colors.accentText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DS.Colors.accentSubtle))
                        .overlay(Capsule().stroke(DS.Colors.accent.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }

                Spacer()

                if isExpanded {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DS.Colors.destructiveText.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }

                Button(action: onToggleExpanded) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.Colors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }

            if isExpanded {
                artifactSection
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DS.CornerRadius.extraLarge, style: .continuous)
                .fill(DS.Colors.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.extraLarge, style: .continuous)
                .stroke(
                    routine.isEnabled ? DS.Colors.accent.opacity(0.30) : DS.Colors.borderSubtle,
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private var artifactSection: some View {
        if let artifact = routine.lastArtifact,
           !artifact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ScrollView {
                Text(artifact)
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundColor(DS.Colors.textSecondary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .fill(DS.Colors.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .stroke(DS.Colors.borderSubtle.opacity(0.7), lineWidth: 1)
            )
        } else {
            Text("No artifact yet — run the routine to produce one.")
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.textTertiary)
        }
    }

    // MARK: Labels

    static func intervalLabel(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }

    static func lastRunLabel(for date: Date?) -> String {
        guard let date else { return "never run" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "ran \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

// MARK: - Add Routine Form

/// In-panel "sheet": a scrim + centered card presented inside the routines
/// tab. A real `.sheet` is avoided on purpose — the hosting NSPanel is a
/// borderless floating panel and AppKit sheet attachment there is fragile.
private struct AddRoutineForm: View {
    let onCancel: () -> Void
    let onCreate: (_ name: String, _ prompt: String, _ intervalMinutes: Int) -> Void

    @State private var name = ""
    @State private var prompt = ""
    @State private var intervalMinutes = 60
    @FocusState private var isNameFocused: Bool

    private static let intervalPresets: [Int] = [15, 30, 60, 120, 240]

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 12) {
                Text("New routine")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)

                fieldLabel("Name")
                TextField(
                    "",
                    text: $name,
                    prompt: Text("Morning brief").foregroundColor(DS.Colors.textTertiary)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textPrimary)
                .tint(DS.Colors.accent)
                .focused($isNameFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(fieldBackground)
                .overlay(IBeamCursorView())

                fieldLabel("Prompt")
                TextEditor(text: $prompt)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .tint(DS.Colors.accent)
                    .frame(height: 72)
                    .padding(6)
                    .background(fieldBackground)

                fieldLabel("Every")
                HStack(spacing: 6) {
                    ForEach(Self.intervalPresets, id: \.self) { minutes in
                        intervalChip(minutes)
                    }
                }

                HStack {
                    Button("Cancel", action: onCancel)
                        .dsTextButtonStyle(fontSize: 12)
                        .pointerCursor()

                    Spacer()

                    Button(action: create) {
                        Text("Add routine")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(canCreate ? DS.Colors.textOnAccent : DS.Colors.disabledText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(canCreate ? DS.Colors.accent : DS.Colors.disabledBackground)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreate)
                    .pointerCursor(isEnabled: canCreate)
                }
                .padding(.top, 2)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Colors.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Colors.borderStrong, lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isNameFocused = true
            }
        }
    }

    private func create() {
        guard canCreate else { return }
        onCreate(
            name.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            intervalMinutes
        )
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(1)
            .foregroundColor(DS.Colors.textTertiary)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
            .fill(DS.Colors.surface2)
            .overlay(
                RoundedRectangle(cornerRadius: DS.CornerRadius.medium, style: .continuous)
                    .stroke(DS.Colors.borderSubtle, lineWidth: 1)
            )
    }

    private func intervalChip(_ minutes: Int) -> some View {
        let isSelected = intervalMinutes == minutes
        return Button {
            intervalMinutes = minutes
        } label: {
            Text(RoutineRow.intervalLabel(minutes: minutes))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? DS.Colors.textOnAccent : DS.Colors.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(isSelected ? DS.Colors.accent : DS.Colors.surface2)
                )
                .overlay(
                    Capsule().stroke(
                        isSelected ? DS.Colors.accent : DS.Colors.borderSubtle,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}

// MARK: - Previews

private func makePreviewStore() -> RoutineStore {
    RoutineStore.previewStore(routines: [
        Routine(
            name: "Morning brief",
            prompt: "Give me a short brief to start my day: calendar, weather, top headlines.",
            intervalMinutes: 60,
            isEnabled: true,
            lastRunAt: Date().addingTimeInterval(-540),
            lastArtifact: """
                Good morning! Two meetings today: the Vibe Buddy demo rehearsal at 18:30 \
                and judging at 21:00. Paris is 24°C and clear this evening. Headlines: \
                Mistral tops the desktop-agent benchmarks; Apple ships the macOS 15.6 \
                notification API fixes; SSE debugging tools land in Xcode 16.
                """
        ),
        Routine(
            name: "Standup notes",
            prompt: "Summarize yesterday's commits into three standup bullets.",
            intervalMinutes: 30,
            isEnabled: true,
            lastRunAt: Date().addingTimeInterval(-60)
        ),
        Routine(
            name: "Inbox sweep",
            prompt: "List any unread emails that look urgent, one line each.",
            intervalMinutes: 240,
            isEnabled: false
        ),
    ])
}

#Preview("Routines list") {
    let store = makePreviewStore()
    return RoutinesView(
        store: store,
        scheduler: RoutineScheduler(store: store, startsAutomatically: false)
    )
    .frame(width: 400, height: 430)
    .background(DS.Colors.background)
}

#Preview("Empty state") {
    let store = RoutineStore.previewStore(routines: [])
    return RoutinesView(
        store: store,
        scheduler: RoutineScheduler(store: store, startsAutomatically: false)
    )
    .frame(width: 400, height: 430)
    .background(DS.Colors.background)
}

#Preview("Badge") {
    RoutinesBadge(store: makePreviewStore())
        .padding(24)
        .background(DS.Colors.background)
}
