import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var watcher = ProcessWatcher.shared
    @ObservedObject private var voiceManager = VoiceManager.shared
    @State private var launchAtStartup: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var statusMessage: String = ""
    @State private var hooksInstalled: Bool = HookServer.shared.isHooksConfigured

    // Hotkey
    @State private var hotkeyFlags: UInt    = AppState.shared.hotkeyFlags
    @State private var hotkeyCode: UInt16   = AppState.shared.hotkeyCode

    // Bindings in minutes for the absence field
    private var absenceMinutes: Binding<Double> {
        Binding(
            get: { state.absenceInterval / 60 },
            set: { state.absenceInterval = max(1, $0) * 60 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                // MARK: Google Antigravity CLI Integration
                GroupBox("Google Antigravity CLI Integration") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Lumo operates as a native HUD companion for your terminal `agy` session, powered by Google One AI Premium (Ultra). No external API keys required.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)

                        Divider()

                        // Process Status
                        HStack(spacing: 8) {
                            Circle()
                                .fill(watcher.isAgyRunning ? Color.green : Color.secondary.opacity(0.5))
                                .frame(width: 8, height: 8)
                            Text(watcher.isAgyRunning ? "Terminal Process: Running (Active `agy` detected)" : "Terminal Process: Idle (Waiting for `agy` in terminal)")
                                .font(.system(size: 12, weight: .medium))
                        }

                        // Socket Status
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("IPC Unix Socket: ~/.lumo/lumo.sock (Ready)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        // Hooks Status
                        HStack(spacing: 8) {
                            Circle()
                                .fill(hooksInstalled ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(hooksInstalled ? "Hooks Configured: ~/.gemini/config/hooks.json" : "Hooks Not Installed")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(hooksInstalled ? .secondary : .orange)
                        }

                        // Supported Features List
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active Capabilities:")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text("• PreToolUse: Interactive Allow / Deny approval in Notch")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                            Text("• PostToolUse: Live step & command execution ticker")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                            Text("• PreInvocation: Notch thinking pulse animation")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                            Text("• Stop: Haptic sound and task completion card")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        HStack(spacing: 12) {
                            Button("Install Hooks") {
                                installHooks()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Uninstall Hooks") {
                                uninstallHooks()
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button("Open Terminal") {
                                openTerminal()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(8)
                }

                // MARK: AI Model & Reasoning Engine
                GroupBox("AI Model & Reasoning Engine") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select the default intelligence engine for Lumo HUD and Antigravity CLI. Powered by Google One AI Ultra.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)

                        // Model Cards / Radio Rows
                        VStack(spacing: 6) {
                            ForEach(AIModelOption.allModels) { model in
                                let isSelected = (state.selectedModel == model.id)
                                Button {
                                    state.selectedModel = model.id
                                    SoundEngine.shared.play("blip")
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                            .foregroundColor(isSelected ? Color(hex: model.tagColor) : .secondary)
                                            .font(.system(size: 13))

                                        Image(systemName: model.icon)
                                            .foregroundColor(Color(hex: model.tagColor))
                                            .font(.system(size: 13))
                                            .frame(width: 18)

                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 6) {
                                                Text(model.name)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.primary)

                                                Text(model.provider)
                                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                                    .foregroundColor(Color(hex: model.tagColor))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .background(Color(hex: model.tagColor).opacity(0.12))
                                                    .clipShape(Capsule())
                                            }
                                            Text(model.subtitle)
                                                .font(.system(size: 10.5))
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected ? Color(hex: model.tagColor).opacity(0.08) : Color.white.opacity(0.02))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(isSelected ? Color(hex: model.tagColor).opacity(0.4) : Color.gray.opacity(0.15), lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Divider()

                        // Reasoning Effort Selector
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Reasoning Effort")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)

                            Picker("Effort", selection: $state.selectedEffort) {
                                Text("Low").tag("low")
                                Text("Medium").tag("medium")
                                Text("High").tag("high")
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(8)
                }

                // MARK: Voice & Speech Commands
                GroupBox("Voice Commands & Dictation") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(voiceManager.isAuthorized ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(voiceManager.isAuthorized ? "Speech Recognition: Ready" : "Microphone & Speech: Requires Authorization")
                                .font(.system(size: 12, weight: .semibold))
                        }

                        Text("Speak prompts hands-free in the Notch or say 'Allow' / 'Deny' on permission cards.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Toggle("Read AI responses aloud (Text-to-Speech)", isOn: $voiceManager.ttsEnabled)
                            .font(.system(size: 11.5))

                        HStack {
                            Button(voiceManager.isAuthorized ? "Permissions Granted" : "Authorize Microphone & Speech") {
                                voiceManager.requestPermissions()
                            }
                            .buttonStyle(.bordered)
                            .disabled(voiceManager.isAuthorized)
                        }
                    }
                    .padding(8)
                }

                // MARK: Sound
                GroupBox("Sound") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Enable sounds", isOn: $state.soundEnabled)
                        HStack(spacing: 8) {
                            Text("Volume")
                                .frame(width: 56, alignment: .leading)
                            Slider(value: $state.soundVolume, in: 0...0.2)
                                .disabled(!state.soundEnabled)
                            Text("\(Int(state.soundVolume / 0.2 * 100)) %")
                                .frame(width: 36, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }
                    .padding(6)
                }

                // MARK: Timings
                GroupBox("Behavior") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Close after")
                            TextField("60", value: $state.autoCloseInterval, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 64)
                            Text("s inactive")
                        }
                        HStack(spacing: 8) {
                            Text("Hide after")
                            TextField("3", value: absenceMinutes, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 48)
                            Text("min without movement")
                        }
                    }
                    .padding(6)
                }

                // MARK: Hotkey
                GroupBox("Hotkey") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show island with shortcut", isOn: $state.hotkeyEnabled)
                        if state.hotkeyEnabled {
                            HStack(spacing: 8) {
                                Text("Shortcut")
                                    .frame(width: 70, alignment: .leading)
                                ShortcutRecorderButton(flags: $hotkeyFlags, code: $hotkeyCode)
                                    .onChange(of: hotkeyFlags) { _, v in state.hotkeyFlags = v }
                                    .onChange(of: hotkeyCode)  { _, v in state.hotkeyCode  = v }
                                Text("presses this → island opens")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(6)
                }

                // MARK: Startup
                GroupBox("Startup") {
                    Toggle("Launch at Mac startup", isOn: $launchAtStartup)
                        .onChange(of: launchAtStartup) { _, on in toggleStartup(on) }
                        .padding(6)
                }

                // MARK: Developer & GitHub
                GroupBox("Developer & Community") {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color(hex: "#38BDF8"), Color(hex: "#818CF8"), Color(hex: "#C084FC")],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 32, height: 32)
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Developed by e404r")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Official repository & source code on GitHub")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button {
                            if let url = URL(string: "https://github.com/e404r") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 11))
                                Text("GitHub: e404r")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(6)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(statusMessage.hasPrefix("❌") ? .red : .secondary)
                        .padding(.horizontal, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .frame(width: 480, height: 680)
    }

    // MARK: - Actions

    private func toggleStartup(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch {
            statusMessage = "❌ Startup: \(error.localizedDescription)"
            launchAtStartup = !on
        }
    }

    // MARK: - App Store: hooks via NSOpenPanel + security-scoped bookmark

    private func installHooks() {
        HookServer.shared.installBridgeAndHooks()
        hooksInstalled = HookServer.shared.isHooksConfigured
        statusMessage = "✓ Antigravity hooks configured in ~/.gemini/config/hooks.json"
    }

    private func uninstallHooks() {
        HookServer.shared.uninstallLumoHooks()
        hooksInstalled = HookServer.shared.isHooksConfigured
        statusMessage = "✓ Hooks removed."
    }

    private func openTerminal() {
        let terminalBundleIds = [
            "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty",
            "com.mitchellh.ghostty", "com.warp.WarpTerminal", "com.microsoft.VSCode"
        ]
        let activated = terminalBundleIds.compactMap { id in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
        }.first.map { $0.activate(options: .activateIgnoringOtherApps) }
        if activated == nil {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        }
    }
}

// MARK: - Shortcut recorder button

struct ShortcutRecorderButton: View {
    @Binding var flags: UInt
    @Binding var code: UInt16
    @State private var isRecording = false

    var body: some View {
        Button {
            guard !isRecording else { return }
            isRecording = true
            var token: Any?
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
                guard !mods.isEmpty else { return event }
                DispatchQueue.main.async {
                    self.flags = mods.rawValue
                    self.code = event.keyCode
                    self.isRecording = false
                    if let t = token { NSEvent.removeMonitor(t) }
                }
                return nil
            }
        } label: {
            Text(isRecording ? "Press keys…" : shortcutLabel)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(isRecording ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var shortcutLabel: String {
        let f = NSEvent.ModifierFlags(rawValue: flags)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        s += keyChar(code)
        return s.isEmpty ? "None" : s
    }

    private func keyChar(_ c: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
            11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U",
            34:"I", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M", 49:"Space", 50:"`", 27:"-"
        ]
        return map[c] ?? "·"
    }
}
