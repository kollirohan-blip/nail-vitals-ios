//
//  AssistantService.swift
//  NailVitals
//
//  Seam for the post-result Q&A assistant. AskAssistantView only talks to
//  an AnswerProvider; the real AI plugs in by replacing `assistantProvider`.
//  Planned constraints for that provider: explain, never diagnose; keep
//  the "not a diagnosis" framing; send only the question, the reading and
//  recent chat -- never the finger photo; keep any API key off the device
//  (behind a small server).
//

import Foundation

struct AssistantContext {
    /// The readings behind the result on screen, oldest first.
    let readings: [FingerSigns]

    var assessment: ClubbingAssessment? {
        readings.isEmpty ? nil : ClubbingAssessment(readings: readings)
    }

    /// Plain-text summary a real provider would include with each question:
    /// numbers only, never the photo.
    var summary: String {
        guard let assessment, !assessment.values.isEmpty else { return "" }
        var parts: [String] = []
        for kind in SignKind.allCases {
            guard let value = assessment.values[kind] else { continue }
            var part = "\(kind.title): \(kind.formatted(value)) (clubbing is considered above \(kind.formattedThreshold))"
            if let count = assessment.readingCounts[kind], count > 1 { part += ", middle of \(count) readings" }
            parts.append(part + ".")
        }
        parts.append("Overall result: \(assessment.verdict.label).")
        return parts.joined(separator: " ")
    }
}

struct AssistantMessage: Identifiable, Equatable {
    enum Role { case user, assistant, notice }
    let id = UUID()
    let role: Role
    let text: String
}

protocol AnswerProvider {
    func answer(_ question: String, history: [AssistantMessage], context: AssistantContext) async throws -> String
}

/// Placeholder until the AI backend exists: says so plainly instead of
/// pretending to answer medical questions.
struct NotConnectedAnswerProvider: AnswerProvider {
    func answer(_ question: String, history: [AssistantMessage], context: AssistantContext) async throws -> String {
        try await Task.sleep(for: .milliseconds(600))
        return "The AI assistant isn't connected yet — this screen is ready for it. Until then, please bring any questions about your result to a doctor."
    }
}

/// Swap for the real provider once it exists.
let assistantProvider: AnswerProvider = NotConnectedAnswerProvider()
