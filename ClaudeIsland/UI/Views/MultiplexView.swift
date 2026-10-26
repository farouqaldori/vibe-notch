//
//  MultiplexView.swift
//  ClaudeIsland
//
//  Multiplex wall of running sessions — each session is a small TV
//  showing a live feed of its conversation. Sessions that need the user
//  light up their frame; clicking a TV expands it into the full chat.
//

import Combine
import SwiftUI

/// Layout constants shared with NotchViewModel so the panel can size itself to the grid
enum MultiplexLayout {
    static let tileHeight: CGFloat = 128
    static let spacing: CGFloat = 10
    static let maxVisibleRows = 3

    static func columns(for count: Int) -> Int {
        switch count {
        case ...1: return 1
        case 2...4: return 2
        default: return 3
        }
    }

    static func rows(for count: Int) -> Int {
        let cols = columns(for: count)
        return max(1, Int((Double(max(count, 1)) / Double(cols)).rounded(.up)))
    }

    static func panelWidth(for count: Int) -> CGFloat {
        switch columns(for: count) {
        case 1: return 460
        case 2: return 600
        default: return 760
        }
    }

    static func gridHeight(for count: Int) -> CGFloat {
        let rows = min(rows(for: count), maxVisibleRows)
        return CGFloat(rows) * tileHeight + CGFloat(rows - 1) * spacing
    }
}

struct MultiplexView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        if sessionMonitor.instances.isEmpty {
            emptyState
        } else {
            grid
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tv")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(.white.opacity(0.25))

            Text("No channels")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Text("Run claude in terminal")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grid

    /// Stable order so TVs don't jump around when a session changes phase:
    /// oldest session first, like fixed channel numbers.
    private var orderedInstances: [SessionState] {
        sessionMonitor.instances.sorted { a, b in
            if a.createdAt != b.createdAt {
                return a.createdAt < b.createdAt
            }
            return a.sessionId < b.sessionId
        }
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: MultiplexLayout.spacing),
            count: MultiplexLayout.columns(for: sessionMonitor.instances.count)
        )
    }

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: gridColumns, spacing: MultiplexLayout.spacing) {
                ForEach(orderedInstances, id: \.stableId) { session in
                    SessionTVTile(
                        session: session,
                        onOpen: { viewModel.showChat(for: session) },
                        onApprove: { sessionMonitor.approvePermission(sessionId: session.sessionId) },
                        onDeny: { sessionMonitor.denyPermission(sessionId: session.sessionId, reason: nil) },
                        onArchive: { sessionMonitor.archiveSession(sessionId: session.sessionId) }
                    )
                    .frame(height: MultiplexLayout.tileHeight)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - TV Tile

struct SessionTVTile: View {
    let session: SessionState
    let onOpen: () -> Void
    let onApprove: () -> Void
    let onDeny: () -> Void
    let onArchive: () -> Void

    @ObservedObject private var historyManager = ChatHistoryManager.shared
    @State private var isHovered = false
    @State private var pulse = false

    private let claudeOrange = TerminalColors.prompt

    private var history: [ChatHistoryItem] {
        historyManager.history(for: session.sessionId)
    }

    /// Input is required: a permission prompt or a question from Claude
    private var needsApproval: Bool { session.phase.isWaitingForApproval }
    private var isReady: Bool { session.phase == .waitingForInput }
    /// Only "needs input" lights the frame; done sessions stay calm
    private var needsUser: Bool { statusKind == .needsInput }

    private var accentColor: Color { statusKind.color }

    var body: some View {
        VStack(spacing: 0) {
            screen
            bezelLabel
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: isHovered ? 0.11 : 0.08))
        )
        .overlay(frameBorder)
        .shadow(color: needsUser ? accentColor.opacity(pulse ? 0.55 : 0.2) : .clear, radius: needsUser ? 10 : 0)
        .scaleEffect(isHovered ? 1.02 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { onOpen() }
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
        .animation(.smooth(duration: 0.3), value: session.phase)
        .onAppear { startPulseIfNeeded() }
        .onChange(of: needsUser) { _, _ in startPulseIfNeeded() }
        .task(id: session.sessionId) {
            // Tune in: parse the transcript so the screen has something to show
            await ChatHistoryManager.shared.loadFromFile(sessionId: session.sessionId, cwd: session.cwd)
        }
    }

    // MARK: - Frame

    private var frameBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
                needsUser ? accentColor.opacity(pulse ? 1 : 0.55) : Color.white.opacity(isHovered ? 0.18 : 0.08),
                lineWidth: needsUser ? 2 : 1
            )
    }

    private func startPulseIfNeeded() {
        guard needsUser else {
            withAnimation(.easeOut(duration: 0.2)) { pulse = false }
            return
        }
        pulse = false
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }

    // MARK: - Screen

    private var screen: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black)

            feed
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            // CRT scanlines + vignette
            Scanlines()
                .allowsHitTesting(false)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.45)],
                        center: .center,
                        startRadius: 30,
                        endRadius: 180
                    )
                )
                .allowsHitTesting(false)

            if needsUser {
                approvalOverlay
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding([.horizontal, .top], 6)
    }

    /// Last few lines of the conversation, pinned to the bottom like a terminal
    private var feed: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            ForEach(feedLines) { line in
                Text(line.text)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(line.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if session.phase == .processing || session.phase == .compacting {
                LiveCursor(color: claudeOrange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var approvalOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                Text(approvalOverlayText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(statusKind.color)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if needsApproval && session.pendingToolName != "AskUserQuestion" {
                    Button(action: onDeny) {
                        Text("Deny")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onApprove) {
                        Text("Allow")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.92))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
            )
        }
    }

    // MARK: - Bezel

    private var bezelLabel: some View {
        HStack(spacing: 6) {
            Text(session.projectName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)

            Spacer(minLength: 4)

            if isHovered && (session.phase == .idle || isReady) {
                Button(action: onArchive) {
                    Image(systemName: "power")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Turn off (archive session)")
                .transition(.opacity)
            } else {
                HStack(spacing: 4) {
                    SessionStatusGlyph(kind: statusKind, size: 10)
                    Text(statusLabel)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(statusKind.color)
                        .lineLimit(1)
                }
                .help(statusKind.helpText)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
    }

    private var statusKind: SessionStatusKind { SessionStatusKind(session: session) }

    private var statusLabel: String {
        if statusKind == .needsInput { return "NEEDS YOU" }
        switch session.phase {
        case .waitingForApproval: return "NEEDS YOU"
        case .processing, .compacting: return "IN PROGRESS"
        case .waitingForInput, .idle, .ended: return "DONE"
        }
    }

    /// For a question, show Claude's recommended answer; otherwise the tool name
    private var approvalOverlayText: String {
        if let prompt = session.turnPrompt {
            return "? " + prompt.question
        }
        if session.pendingToolName == "AskUserQuestion" {
            let questions = PendingQuestion.parse(session.activePermission?.toolInput)
            if let recommended = questions.first?.recommended {
                return "Suggests: \(recommended.displayLabel)"
            }
            return "Question — click to answer"
        }
        return MCPToolFormatter.formatToolName(session.pendingToolName ?? "Tool")
    }

    // MARK: - Feed Lines

    private struct FeedLine: Identifiable {
        let id: String
        let text: String
        let color: Color
    }

    private var feedLines: [FeedLine] {
        let lines = history.suffix(5).compactMap(feedLine(for:))
        if !lines.isEmpty { return lines }

        // Transcript not parsed yet — fall back to the hook-reported summary
        if let message = session.lastMessage {
            let prefix = session.lastMessageRole == "user" ? "› " : ""
            return [FeedLine(id: "fallback", text: prefix + flatten(message), color: .white.opacity(0.6))]
        }
        return [FeedLine(id: "empty", text: "no signal", color: .white.opacity(0.25))]
    }

    private func feedLine(for item: ChatHistoryItem) -> FeedLine? {
        switch item.type {
        case .user(let text):
            return FeedLine(id: item.id, text: "› " + flatten(text), color: .white.opacity(0.9))
        case .assistant(let text):
            return FeedLine(id: item.id, text: flatten(text), color: .white.opacity(0.6))
        case .toolCall(let tool):
            let preview = tool.inputPreview
            let label = MCPToolFormatter.formatToolName(tool.name) + (preview.isEmpty ? "" : "(\(preview))")
            return FeedLine(id: item.id, text: "⏺ " + label, color: toolColor(tool.status))
        case .thinking:
            return FeedLine(id: item.id, text: "✻ thinking…", color: .white.opacity(0.3))
        case .image:
            return FeedLine(id: item.id, text: "▣ image", color: .white.opacity(0.4))
        case .interrupted:
            return FeedLine(id: item.id, text: "⎿ interrupted", color: TerminalColors.red.opacity(0.8))
        }
    }

    private func toolColor(_ status: ToolStatus) -> Color {
        switch status {
        case .running: return claudeOrange.opacity(0.9)
        case .waitingForApproval: return TerminalColors.amber
        case .success: return TerminalColors.green.opacity(0.75)
        case .error: return TerminalColors.red.opacity(0.85)
        case .interrupted: return .white.opacity(0.35)
        }
    }

    private func flatten(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}

// MARK: - CRT Details

private struct Scanlines: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(0.025)))
                y += 3
            }
        }
    }
}

private struct LiveCursor: View {
    let color: Color
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 5, height: 9)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
