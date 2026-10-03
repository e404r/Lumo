# Contributing to Lumo

Thanks for wanting to help Lumo and our Gemini companion grow! 💫

---

## Getting Started

1. Ensure you have **macOS 15.0+** and **Xcode 16+** installed.
2. Clone the repository and navigate to the project directory:

```bash
cd NotchBuddy
xcodebuild -project Lumo.xcodeproj -scheme Lumo -configuration Debug build
```

*(Optional: if you modify `project.yml`, run `xcodegen generate` to update the Xcode project).*

---

## Areas for Contribution

- **Google Antigravity Lifecycle Enhancements**: Improving response times, richer tool visualizations, and deeper hook interactions.
- **Gemini Capabilities**: Expanding multimodal context, code analysis features, and audio/voice interactions.
- **MacBook Notch Animations**: Crafting silky 120Hz ProMotion animations and tactile haptics.
- **Bug Fixes & Optimizations**: Keeping memory and CPU usage at zero when the island is hidden.

---

## Rules of the House

- **Swift 6, SwiftUI + AppKit**: Clean, modern, native Swift. Zero heavy third-party dependencies unless strictly necessary.
- **Privacy & Security First**: Zero telemetry. All IPC happens strictly through the local Unix domain socket (`~/.lumo/lumo.sock`).
- **Never Block the CLI**: If Lumo is closed or busy, the hook bridge must immediately exit and allow terminal commands to proceed.
- **Safe Hook Management**: Never alter `~/.gemini/config/hooks.json` destructively or without backing up existing configurations.
- **Performance**: 0% CPU consumption when the island is hidden behind the notch.

---

## Pull Request Guidelines

- Keep pull requests focused on a single feature or fix.
- Include a quick GIF or screenshot for any UI / animation changes.
- Ensure the project builds cleanly with `xcodebuild` with zero warnings.
