//
//  SessionStatusBadge.swift
//  ClaudeIsland
//
//  One icon language for session state, used by the notch and the TV tiles.
//  Three states, by color and shape:
//  red hand = needs your input, yellow spinner = in progress, green check = done.
//

import SwiftUI

enum SessionStatusKind: CaseIterable {
    case needsInput
    case working
    case done

    /// Uses the transcript too: a finished turn that ends by asking the user
    /// something needs input, not "done"
    init(session: SessionState) {
        if session.turnPrompt != nil {
            self = .needsInput
        } else {
            self.init(phase: session.phase)
        }
    }

    init(phase: SessionPhase) {
        switch phase {
        case .waitingForApproval: self = .needsInput
        case .processing, .compacting: self = .working
        // Finished its turn, idle or ended: nothing left to be done
        case .waitingForInput, .idle, .ended: self = .done
        }
    }

    var color: Color {
        switch self {
        case .needsInput: return TerminalColors.red
        case .working: return TerminalColors.yellow
        case .done: return TerminalColors.green
        }
    }

    var helpText: String {
        switch self {
        case .needsInput: return "Needs your input"
        case .working: return "In progress"
        case .done: return "Done"
        }
    }
}

/// The bare icon for a status
struct SessionStatusGlyph: View {
    let kind: SessionStatusKind
    var size: CGFloat = 11

    var body: some View {
        switch kind {
        case .working:
            ProcessingSpinner(color: kind.color)
        case .needsInput:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(kind.color)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(kind.color)
        }
    }
}

/// Icon plus a session count. A zero count is dimmed rather than hidden so the
/// notch layout stays put as sessions move between states.
struct SessionStatusBadge: View {
    let kind: SessionStatusKind
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            SessionStatusGlyph(kind: kind)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(kind.color)
                .monospacedDigit()
        }
        .opacity(count > 0 ? 1 : 0.3)
        .help("\(count) — \(kind.helpText.lowercased())")
    }
}
