//
//  PendingQuestion.swift
//  ClaudeIsland
//
//  A question Claude is asking via AskUserQuestion, parsed from the pending
//  permission's tool input so it can be answered straight from the notch.
//

import Foundation

/// A finished turn that ended by asking the user something — e.g. the Claude
/// desktop app's next-step prompt (a `wrap_up` tool call with an `ask`), or a
/// reply that ends with a question. Hooks only see a normal Stop for these.
struct TurnPrompt: Equatable, Sendable {
    struct Suggestion: Identifiable, Equatable, Sendable {
        let label: String
        /// Text to send as the reply
        let message: String

        var id: String { label }
    }

    let question: String
    /// Suggested replies, Claude's recommendation first
    let suggestions: [Suggestion]
}

extension SessionState {
    /// The question the last turn ended on, if Claude is waiting on the user's answer
    var turnPrompt: TurnPrompt? {
        // .idle covers sessions picked up from the registry at launch
        guard phase == .waitingForInput || phase == .idle else { return nil }

        var lastAssistantText: String?
        for item in chatItems.reversed() {
            switch item.type {
            case .user:
                // Only look at the latest turn
                return lastAssistantText.flatMap(Self.trailingQuestion).map {
                    TurnPrompt(question: $0, suggestions: [])
                }
            case .toolCall(let tool) where tool.name.hasSuffix("wrap_up"):
                if let ask = tool.input["ask"]?.trimmingCharacters(in: .whitespacesAndNewlines), !ask.isEmpty {
                    return TurnPrompt(question: ask, suggestions: Self.parseSuggestions(tool.input["actions"]))
                }
            case .assistant(let text):
                if lastAssistantText == nil { lastAssistantText = text }
            default:
                break
            }
        }
        return lastAssistantText.flatMap(Self.trailingQuestion).map {
            TurnPrompt(question: $0, suggestions: [])
        }
    }

    /// Last line of a reply, if it's a question
    private static func trailingQuestion(_ text: String) -> String? {
        let lastLine = text
            .split(whereSeparator: \.isNewline)
            .last
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let line = lastLine, line.hasSuffix("?") else { return nil }
        return line
    }

    /// `actions` is a JSON array of {label, message} or {action} buttons
    private static func parseSuggestions(_ json: String?) -> [TurnPrompt.Suggestion] {
        guard let data = json?.data(using: .utf8),
              let actions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return actions.compactMap { action in
            let appAction = (action["action"] as? String)?
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            guard let label = action["label"] as? String ?? appAction else { return nil }
            return TurnPrompt.Suggestion(label: label, message: action["message"] as? String ?? label)
        }
    }
}

struct PendingQuestion: Identifiable, Equatable, Sendable {
    struct Option: Identifiable, Equatable, Sendable {
        /// Label as Claude wrote it (sent back verbatim as the answer)
        let label: String
        let description: String?

        var id: String { label }

        /// Claude marks its suggested option with a "(Recommended)" suffix
        var isRecommended: Bool {
            label.localizedCaseInsensitiveContains("(recommended)")
        }

        /// Label without the "(Recommended)" marker, for display
        var displayLabel: String {
            label
                .replacingOccurrences(of: "(Recommended)", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
        }
    }

    let question: String
    let header: String?
    let multiSelect: Bool
    let options: [Option]

    var id: String { question }

    var recommended: Option? {
        options.first(where: \.isRecommended)
    }

    /// Parse the `questions` array of an AskUserQuestion tool input
    static func parse(_ toolInput: [String: AnyCodable]?) -> [PendingQuestion] {
        guard let raw = toolInput?["questions"]?.value as? [Any] else { return [] }

        return raw.compactMap { item in
            guard let dict = item as? [String: Any],
                  let question = dict["question"] as? String else { return nil }

            let options = (dict["options"] as? [Any] ?? []).compactMap { option -> Option? in
                guard let optionDict = option as? [String: Any],
                      let label = optionDict["label"] as? String else { return nil }
                return Option(label: label, description: optionDict["description"] as? String)
            }

            return PendingQuestion(
                question: question,
                header: dict["header"] as? String,
                multiSelect: dict["multiSelect"] as? Bool ?? false,
                options: options
            )
        }
    }
}
