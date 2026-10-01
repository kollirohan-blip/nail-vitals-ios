//
//  AssistantService.swift
//  NailVitals
//
//  The post-result Q&A assistant. AskAssistantView only talks to an
//  AnswerProvider. The real one, ProxyAnswerProvider, asks Google Gemini
//  through a small server (server/gemini-proxy) that holds the API key, so
//  no key is ever in the app and no user ever enters one. It sends only the
//  question, the result numbers and recent chat -- never the finger photo.
//  The server's instructions keep answers educational: explain, never
//  diagnose.
//
//  The server address and app token come from AssistantConfig.plist, which
//  server/gemini-proxy/setup.sh writes and git ignores. Without it the
//  screen says the assistant isn't connected.
//

import Foundation

struct AssistantContext {
    /// The readings behind the result on screen, oldest first.
    let readings: [FingerSigns]
    var hand: MeasuredHand = .right

    var assessment: ClubbingAssessment? {
        readings.isEmpty ? nil : ClubbingAssessment(readings: readings)
    }

    /// Plain-text summary sent with each question: numbers only, never the
    /// photo.
    var summary: String {
        guard let assessment, !assessment.values.isEmpty else { return "" }
        var parts = ["Measured finger: \(hand.rawValue) index."]
        for kind in SignKind.allCases {
            guard let value = assessment.values[kind] else { continue }
            let noDip = kind == .lovibond && readings.last?.noCuticleDip == true
            var part = noDip
                ? "\(kind.title): no cuticle dip found, i.e. Lovibond's angle is obliterated (180 or more); a finger turned toward the camera can also hide the dip"
                : "\(kind.title): \(kind.formatted(value)) (clubbing is considered above \(kind.formattedThreshold))"
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
    /// Who answers, for the screen's note about where questions go; nil
    /// when nothing leaves the phone.
    var answeredBy: String? { get }
    /// - Parameter history: the chat so far, ending with this question.
    func answer(_ question: String, history: [AssistantMessage], context: AssistantContext) async throws -> String
}

/// Used when the app has no server settings: says so plainly instead of
/// pretending to answer medical questions.
struct NotConnectedAnswerProvider: AnswerProvider {
    var answeredBy: String? { nil }

    func answer(_ question: String, history: [AssistantMessage], context: AssistantContext) async throws -> String {
        try await Task.sleep(for: .milliseconds(600))
        return "The AI assistant isn't connected yet — this screen is ready for it. Until then, please bring any questions about your result to a doctor."
    }
}

/// Asks Gemini through the proxy server's POST /ask.
struct ProxyAnswerProvider: AnswerProvider {
    let endpoint: URL
    let appToken: String

    var answeredBy: String? { "Google's Gemini AI" }

    private struct Turn: Encodable {
        let role: String
        let text: String
    }

    private struct AskRequest: Encodable {
        let question: String
        let context: String
        let history: [Turn]
    }

    private struct AskResponse: Decodable {
        let answer: String
    }

    enum ProxyError: Error {
        case status(Int)
    }

    func answer(_ question: String, history: [AssistantMessage], context: AssistantContext) async throws -> String {
        // Earlier questions and answers, without this question (the last
        // message) or on-screen notices.
        let turns: [Turn] = history.dropLast().compactMap { message in
            switch message.role {
            case .user: return Turn(role: "user", text: message.text)
            case .assistant: return Turn(role: "assistant", text: message.text)
            case .notice: return nil
            }
        }
        var request = URLRequest(url: endpoint.appendingPathComponent("ask"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appToken, forHTTPHeaderField: "x-app-token")
        request.httpBody = try JSONEncoder().encode(
            AskRequest(question: question, context: context.summary, history: Array(turns.suffix(8)))
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ProxyError.status(status) }
        return try JSONDecoder().decode(AskResponse.self, from: data).answer
    }
}

/// Server settings from the bundled AssistantConfig.plist (Endpoint,
/// AppToken), if present.
enum AssistantConfig {
    static func makeProvider() -> AnswerProvider {
        guard let url = Bundle.main.url(forResource: "AssistantConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let endpoint = plist["Endpoint"].flatMap(URL.init(string:)),
              let token = plist["AppToken"], !token.isEmpty
        else { return NotConnectedAnswerProvider() }
        return ProxyAnswerProvider(endpoint: endpoint, appToken: token)
    }
}

let assistantProvider: AnswerProvider = AssistantConfig.makeProvider()
