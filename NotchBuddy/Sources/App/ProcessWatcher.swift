import Foundation
import AppKit

// MARK: - ProcessWatcher
// Monitors the system for running Google Antigravity CLI (`agy`) processes.
// Automatically awakens Lumo in the notch when agy is running and resets when finished.

final class ProcessWatcher: ObservableObject, @unchecked Sendable {
    static let shared = ProcessWatcher()

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.lumo.processWatcher", qos: .background)
    private var lastRunningState: Bool = false

    @MainActor @Published var isAgyRunning: Bool = false

    private init() {}

    func start() {
        guard timer == nil else { return }

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(1500))
        t.setEventHandler { [weak self] in
            self?.checkProcess()
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func checkProcess() {
        // Fast process lookup via pgrep -x agy
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-x", "agy"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        var isRunning = false
        do {
            try task.run()
            task.waitUntilExit()
            isRunning = (task.terminationStatus == 0)
        } catch {
            isRunning = false
        }

        // Also check if HookServer has an active socket session
        if SocketServer.shared.hasActiveSession {
            isRunning = true
        }

        if isRunning != lastRunningState {
            lastRunningState = isRunning
            Task { @MainActor in
                self.isAgyRunning = isRunning
                self.handleStateChange(isRunning: isRunning)
            }
        }
    }

    @MainActor
    private func handleStateChange(isRunning: Bool) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == "integration_claude" }) else { return }

        if isRunning {
            if state.tasks[idx].state == .idle {
                state.updateTask(id: "integration_claude", state: .thinking)
            }
            if state.mode == .hidden && state.isPresent {
                NotificationCenter.default.post(name: .hookReveal, object: nil)
            }
        } else {
            // When agy process exits
            if state.tasks[idx].state == .working || state.tasks[idx].state == .thinking {
                state.updateTask(id: "integration_claude", state: .idle)
            }
        }
    }
}
