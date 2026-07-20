import AppKit
import SwiftUI

struct RelaySettingsView: View {
    @Bindable var settings: RelaySettingsStore
    let updateController: RelayUpdateController
    let shortcutError: String?

    @State private var confirmingRestore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsGroup("Relay AI") {
                    settingRow(
                        "Model",
                        detail: settings.controllerModel.detail
                    ) {
                        Picker(
                            "Model",
                            selection: $settings.controllerModel
                        ) {
                            ForEach(RelayControllerModel.allCases) { model in
                                Text(model.title).tag(model)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 176)
                    }
                    rowDivider
                    settingRow(
                        "Reasoning effort",
                        detail: "Higher effort can improve difficult answers but takes longer."
                    ) {
                        Picker(
                            "Reasoning effort",
                            selection: $settings.controllerReasoningEffort
                        ) {
                            ForEach(
                                settings.controllerModel.supportedReasoningEfforts
                            ) { effort in
                                Text(effort.title).tag(effort)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 128)
                    }
                }

                settingsGroup("Behavior") {
                    settingToggle(
                        "Show Relay at launch",
                        detail: "Shows the compact notch surface when Relay opens.",
                        isOn: $settings.showAtLaunch
                    )
                    rowDivider
                    settingToggle(
                        "Automatic activity peeks",
                        detail: "Briefly surfaces tasks that need attention.",
                        isOn: $settings.automaticPeeks
                    )
                    rowDivider
                    settingToggle(
                        "Follow pointer across displays",
                        detail: "Moves compact Relay after you settle on another display.",
                        isOn: $settings.followsPointerAcrossDisplays
                    )
                }

                settingsGroup("Voice & Shortcut") {
                    settingToggle(
                        "Speak voice-command answers",
                        detail: "Keeps microphone input available when turned off.",
                        isOn: $settings.speaksVoiceResponses
                    )
                    rowDivider
                    settingRow(
                        "Voice",
                        detail: "Uses the macOS system voice unless you choose one."
                    ) {
                        Picker("Voice", selection: voiceSelection) {
                            Text("System Voice").tag("")
                            ForEach(RelaySpeechVoiceOption.installed) { voice in
                                Text(voice.name).tag(voice.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 160)
                    }
                    rowDivider
                    settingRow(
                        "Push-to-talk",
                        detail: "Use a modifier chord or modifiers plus a key. Delete restores Option-Space."
                    ) {
                        RelayShortcutRecorder(
                            shortcut: settings.shortcut,
                            onCommit: { settings.shortcut = $0 }
                        )
                    }
                    if let shortcutError {
                        Text(shortcutError)
                            .font(.caption)
                            .foregroundStyle(RelayPalette.critical)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 9)
                            .accessibilityLabel(
                                "Shortcut error: \(shortcutError)"
                            )
                    }
                }

                settingsGroup("Updates") {
                    settingToggle(
                        "Check automatically",
                        detail: "Relay only reads the signed update feed.",
                        isOn: $settings.automaticallyChecksForUpdates
                    )
                    rowDivider
                    settingRow(
                        "Check cadence",
                        detail: settings.automaticallyChecksForUpdates
                            ? "How often Relay checks in the background."
                            : "Enable automatic checks to use a cadence."
                    ) {
                        Picker(
                            "Update cadence",
                            selection: $settings.updateCadence
                        ) {
                            ForEach(RelayUpdateCadence.allCases) { cadence in
                                Text(cadence.title).tag(cadence)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 110)
                        .disabled(!settings.automaticallyChecksForUpdates)
                    }
                    rowDivider
                    settingRow(
                        "Relay \(updateController.installedVersion)",
                        detail: updateStatusCopy
                    ) {
                        Button("Check Now") {
                            updateController.checkForUpdates()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(updateController.presentation == .checking)
                        .accessibilityHint(
                            "Checks Relay's signed update feed immediately"
                        )
                    }
                }

                settingsGroup("Usage") {
                    settingToggle(
                        "Apply reset credits automatically",
                        detail: "Uses a credit one hour before it expires.",
                        isOn: $settings.autoApplyResetCredits
                    )
                }

                settingsGroup("Application") {
                    settingRow(
                        "Quit Relay",
                        detail: "Stops Relay and closes its notch surface."
                    ) {
                        Button("Quit Relay") {
                            NSApplication.shared.terminate(nil)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(RelayPalette.critical)
                    }
                }

                HStack {
                    Spacer()
                    Button(
                        confirmingRestore ? "Confirm Restore" : "Restore Defaults"
                    ) {
                        if confirmingRestore {
                            settings.restoreDefaults()
                            confirmingRestore = false
                        } else {
                            confirmingRestore = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(
                        confirmingRestore ? RelayPalette.critical : nil
                    )
                    .accessibilityHint(
                        confirmingRestore
                            ? "Confirms restoring every Relay setting"
                            : "Requires confirmation before changing settings"
                    )
                    Spacer()
                }
                .padding(.bottom, 4)
            }
            .padding(14)
        }
        .scrollIndicators(.automatic)
    }

    private var voiceSelection: Binding<String> {
        Binding(
            get: {
                guard let identifier = settings.speechVoiceIdentifier else {
                    return ""
                }
                return RelaySpeechVoiceOption.installed.contains {
                    $0.id == identifier
                } ? identifier : ""
            },
            set: { settings.speechVoiceIdentifier = $0.isEmpty ? nil : $0 }
        )
    }

    private var updateStatusCopy: String {
        switch updateController.presentation {
        case .idle:
            "Check the signed feed without waiting for the schedule."
        case .checking:
            "Checking the signed feed…"
        case let .available(version):
            "Version \(version) is ready to install above."
        case let .downloading(version, _):
            "Downloading version \(version)."
        case let .preparing(version):
            "Preparing version \(version)."
        case .upToDate:
            "Relay is up to date."
        case let .failed(message):
            message
        }
    }

    private var rowDivider: some View {
        Divider()
            .overlay(RelayPalette.hairline)
            .padding(.leading, 12)
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(RelayPalette.tertiaryText)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                content()
            }
            .background(RelayPalette.elevatedSurface)
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(RelayPalette.hairline, lineWidth: 1)
            }
        }
    }

    private func settingToggle(
        _ title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        settingRow(title, detail: detail) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(RelayPalette.accent)
        }
    }

    private func settingRow<Control: View>(
        _ title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(RelayPalette.primaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(RelayPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
