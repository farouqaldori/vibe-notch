//
//  QuestionAnswerBar.swift
//  ClaudeIsland
//
//  Answer Claude's AskUserQuestion from the notch. Claude's recommended option
//  is highlighted and can be sent in one click.
//

import SwiftUI

struct QuestionAnswerBar: View {
    let questions: [PendingQuestion]
    let isInTmux: Bool
    /// question text -> chosen label(s)
    let onAnswer: ([String: String]) -> Void
    let onGoToTerminal: () -> Void

    @State private var selections: [String: Set<String>] = [:]
    @State private var customAnswer: String = ""

    private let yellow = TerminalColors.yellow

    /// One single-select question: a tap on an option sends it right away
    private var isOneTap: Bool {
        questions.count == 1 && !questions[0].multiSelect
    }

    private var recommendedAnswers: [String: String]? {
        var answers: [String: String] = [:]
        for question in questions {
            guard let recommended = question.recommended else { return nil }
            answers[question.question] = recommended.label
        }
        return answers
    }

    private var allAnswered: Bool {
        questions.allSatisfy { !(selections[$0.question] ?? []).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topRow

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(questions) { question in
                        questionBlock(question)
                    }
                }
            }
            .frame(maxHeight: 250)

            if isOneTap {
                customAnswerField
            } else {
                sendButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.2))
    }

    // MARK: - Header

    private var topRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(TerminalColors.red)
            Text(questions.count > 1 ? "Claude has \(questions.count) questions" : "Claude needs your input")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))

            Spacer()

            if let recommended = recommendedAnswers {
                Button {
                    onAnswer(recommended)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                        Text(questions.count > 1 ? "Use all recommended" : "Use recommended")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(yellow)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if isInTmux {
                Button(action: onGoToTerminal) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Answer in terminal")
            }
        }
    }

    // MARK: - Question

    private func questionBlock(_ question: PendingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header = question.header {
                Text(header.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(yellow.opacity(0.8))
            }
            Text(question.question)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(question.options) { option in
                optionRow(option, in: question)
            }
        }
    }

    private func optionRow(_ option: PendingQuestion.Option, in question: PendingQuestion) -> some View {
        let isSelected = selections[question.question]?.contains(option.label) ?? false

        return Button {
            select(option, in: question)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: question.multiSelect
                      ? (isSelected ? "checkmark.square.fill" : "square")
                      : (isSelected ? "largecircle.fill.circle" : "circle"))
                    .font(.system(size: 11))
                    .foregroundColor(isSelected || option.isRecommended ? yellow : .white.opacity(0.35))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(option.displayLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                        if option.isRecommended {
                            Text("RECOMMENDED")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(yellow)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.45))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? yellow.opacity(0.14) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? yellow : (option.isRecommended ? yellow.opacity(0.45) : Color.clear),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func select(_ option: PendingQuestion.Option, in question: PendingQuestion) {
        if isOneTap {
            onAnswer([question.question: option.label])
            return
        }
        var current = selections[question.question] ?? []
        if question.multiSelect {
            if current.contains(option.label) {
                current.remove(option.label)
            } else {
                current.insert(option.label)
            }
        } else {
            current = [option.label]
        }
        selections[question.question] = current
    }

    // MARK: - Footer

    private var sendButton: some View {
        HStack {
            Spacer()
            Button {
                var answers: [String: String] = [:]
                for question in questions {
                    // Keep Claude's option order for multi-select answers
                    let chosen = question.options
                        .map(\.label)
                        .filter { selections[question.question]?.contains($0) ?? false }
                    answers[question.question] = chosen.joined(separator: ", ")
                }
                onAnswer(answers)
            } label: {
                Text("Send answers")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(allAnswered ? .black : .white.opacity(0.4))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(allAnswered ? Color.white.opacity(0.95) : Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!allAnswered)
        }
    }

    /// Single question: free-text answer instead of one of the options
    private var customAnswerField: some View {
        HStack(spacing: 8) {
            TextField("Or type your own answer…", text: $customAnswer)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                )
                .onSubmit(sendCustomAnswer)

            Button(action: sendCustomAnswer) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(customAnswer.isEmpty ? .white.opacity(0.2) : .white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .disabled(customAnswer.isEmpty)
        }
    }

    private func sendCustomAnswer() {
        let text = customAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let question = questions.first else { return }
        onAnswer([question.question: text])
    }
}

// MARK: - Turn Prompt Bar

/// Shown above the input when Claude's last turn ended by asking something.
/// Claude's suggested replies become one-click buttons (recommendation first).
struct TurnPromptBar: View {
    let prompt: TurnPrompt
    let canSend: Bool
    let onPick: (TurnPrompt.Suggestion) -> Void

    @State private var copiedId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(TerminalColors.red)
                    .padding(.top, 2)
                Text(prompt.question)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !prompt.suggestions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(prompt.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        suggestionButton(suggestion, isRecommended: index == 0)
                    }
                    Spacer(minLength: 0)
                }

                if !canSend {
                    Text("This session isn't in tmux — a click copies the reply to paste in Claude.")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func suggestionButton(_ suggestion: TurnPrompt.Suggestion, isRecommended: Bool) -> some View {
        Button {
            onPick(suggestion)
            if !canSend {
                copiedId = suggestion.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if copiedId == suggestion.id { copiedId = nil }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if isRecommended {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(copiedId == suggestion.id ? "Copied" : suggestion.label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(isRecommended ? .black : .white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isRecommended ? TerminalColors.yellow : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(suggestion.message)
    }
}
