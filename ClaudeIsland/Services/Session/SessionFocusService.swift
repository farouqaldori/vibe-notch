//
//  SessionFocusService.swift
//  ClaudeIsland
//
//  Brings the app hosting a Claude session to the foreground.
//

import AppKit
import Foundation

enum SessionFocusService {
    /// Focus the app that owns this session.
    /// tmux sessions use the existing yabai window lookup; sessions running in
    /// the Claude desktop app are opened through the app's session deep link.
    static func focus(_ session: SessionState) {
        if session.isInTmux {
            Task {
                if let pid = session.pid {
                    _ = await YabaiController.shared.focusWindow(forClaudePid: pid)
                } else {
                    _ = await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd)
                }
            }
        } else if session.isInDesktopApp {
            openInClaudeDesktop(session)
        }
    }

    private static func openInClaudeDesktop(_ session: SessionState) {
        // The desktop app addresses sessions as `local_<uuid>`; the hook's
        // session_id is the CLI's own UUID and does not match for new sessions.
        let appSessionId: String
        if let hostSessionId = session.hostSessionId, !hostSessionId.isEmpty {
            appSessionId = hostSessionId.hasPrefix("local_") ? hostSessionId : "local_\(hostSessionId)"
        } else {
            appSessionId = "local_\(session.sessionId)"
        }

        var components = URLComponents()
        components.scheme = "claude"
        components.host = "claude.ai"
        components.path = "/epitaxy/\(appSessionId)"

        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
