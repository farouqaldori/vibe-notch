//
//  TerminalMessageSender.swift
//  ClaudeIsland
//
//  Sends a typed message to the terminal that hosts a Claude Code session.
//  tmux uses `tmux send-keys`; iTerm2 and Terminal.app are scripted and
//  matched by tty, so no tmux setup is needed for them.
//

import AppKit
import Foundation
import os.log

actor TerminalMessageSender {
    static let shared = TerminalMessageSender()

    nonisolated static let logger = Logger(subsystem: "com.claudeisland", category: "MessageSender")

    private enum Route {
        case tmux(TmuxTarget)
        case iTerm2(tty: String)
        case terminalApp(tty: String)
    }

    private init() {}

    // MARK: - Public API

    /// How a typed message can reach a session
    enum Support: Sendable {
        /// tmux, Terminal.app or iTerm2
        case available
        /// Started by the Claude desktop app, which has no terminal to write to
        case claudeDesktop
        case unavailable
    }

    /// Runs `ps`, so call it off the main thread and cache the result
    nonisolated static func support(for session: SessionState) -> Support {
        guard let pid = session.pid else { return .unavailable }
        let tree = ProcessTreeBuilder.shared.buildTree()

        if session.tty != nil {
            if session.isInTmux { return .available }
            if scriptableTerminal(forClaudePid: pid, tree: tree) != nil { return .available }
        }
        return isChildOfClaudeDesktop(pid: pid, tree: tree) ? .claudeDesktop : .unavailable
    }

    /// Bring the Claude desktop app to the front
    @MainActor
    static func openClaudeDesktop() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") else {
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private nonisolated static func isChildOfClaudeDesktop(pid: Int, tree: [Int: ProcessInfo]) -> Bool {
        var current = pid
        var depth = 0
        while current > 1 && depth < 20 {
            guard let info = tree[current] else { return false }
            if info.command.contains("/Claude.app/") { return true }
            current = info.ppid
            depth += 1
        }
        return false
    }

    /// Send text (followed by Enter) to the session's terminal
    func send(_ text: String, to session: SessionState) async -> Bool {
        guard let route = await route(for: session) else {
            Self.logger.error("No route to terminal for session")
            return false
        }

        switch route {
        case .tmux(let target):
            return await ToolApprovalHandler.shared.sendMessage(text, to: target)
        case .iTerm2(let tty):
            return await runAppleScript(Self.iTermScript, arguments: [tty, text])
        case .terminalApp(let tty):
            return await runAppleScript(Self.terminalScript, arguments: [tty, text])
        }
    }

    // MARK: - Routing

    private func route(for session: SessionState) async -> Route? {
        guard let tty = session.tty else { return nil }

        if session.isInTmux, let target = await findTmuxTarget(tty: tty) {
            return .tmux(target)
        }

        guard let pid = session.pid,
              let terminal = Self.scriptableTerminal(forClaudePid: pid, tree: ProcessTreeBuilder.shared.buildTree()) else {
            return nil
        }
        let devTty = "/dev/" + tty
        switch terminal {
        case .iTerm2: return .iTerm2(tty: devTty)
        case .terminalApp: return .terminalApp(tty: devTty)
        }
    }

    private enum ScriptableTerminal {
        case iTerm2
        case terminalApp
    }

    private nonisolated static func scriptableTerminal(forClaudePid pid: Int, tree: [Int: ProcessInfo]) -> ScriptableTerminal? {
        guard let terminalPid = ProcessTreeBuilder.shared.findTerminalPid(forProcess: pid, tree: tree),
              let command = tree[terminalPid]?.command else { return nil }

        let lower = command.lowercased()
        if lower.contains("iterm") { return .iTerm2 }
        if lower.hasSuffix("/terminal") { return .terminalApp }
        return nil
    }

    private func findTmuxTarget(tty: String) async -> TmuxTarget? {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else { return nil }

        guard let output = try? await ProcessExecutor.shared.run(
            tmuxPath,
            arguments: ["list-panes", "-a", "-F", "#{session_name}:#{window_index}.#{pane_index} #{pane_tty}"]
        ) else { return nil }

        for line in output.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: " ")
            guard parts.count >= 2 else { continue }
            if parts[1].replacingOccurrences(of: "/dev/", with: "") == tty {
                return TmuxTarget(from: parts[0])
            }
        }
        return nil
    }

    // MARK: - AppleScript

    /// tty and text are passed as argv, so no escaping is needed
    private static let iTermScript = """
    on run argv
        set targetTty to item 1 of argv
        set msg to item 2 of argv
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is targetTty then
                            tell s to write text msg
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        error "session not found"
    end run
    """

    /// `do script` in a busy tab feeds the text to the running process as input
    private static let terminalScript = """
    on run argv
        set targetTty to item 1 of argv
        set msg to item 2 of argv
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is targetTty then
                        do script msg in t
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        error "tab not found"
    end run
    """

    private func runAppleScript(_ script: String, arguments: [String]) async -> Bool {
        let result = await ProcessExecutor.shared.runWithResult(
            "/usr/bin/osascript",
            arguments: ["-e", script, "--"] + arguments
        )
        switch result {
        case .success(let output) where output.exitCode == 0:
            return true
        case .success(let output):
            Self.logger.error("AppleScript failed: \(output.stderr ?? "", privacy: .public)")
            return false
        case .failure(let error):
            Self.logger.error("AppleScript failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
