//
//  AskAssistantView.swift
//  NailVitals
//
//  Chat screen for questions after a result. Shows the reading as context,
//  suggested questions, and a standing "general information, not medical
//  advice" note; answers come from `assistantProvider`.
//

import SwiftUI

struct AskAssistantView: View {
    let context: AssistantContext
    /// The Chat tab: no close button, the home backdrop.
    var embedded = false
    var provider: AnswerProvider = assistantProvider

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [AssistantMessage] = []
    @State private var draft = ""
    @State private var waiting = false
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "What does my reading mean?",
        "What is finger clubbing?",
        "What conditions is clubbing linked to?",
        "How accurate is this measurement?",
        "When should I see a doctor?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        disclaimer
                        if let assessment = context.assessment, let angle = assessment.values[.lovibond] {
                            contextChip(angle, assessment.verdict)
                        }
                        if messages.isEmpty {
                            suggestionList
                        }
                        ForEach(messages) { message in
                            bubble(message).id(message.id)
                        }
                        if waiting {
                            TypingIndicator().id("typing")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages) { _, newValue in
                    if let last = newValue.last {
                        withAnimation { scroller.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            inputBar
        }
        .background { if embedded { AppBackground() } else { Color.black.ignoresSafeArea() } }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Text(context.readings.isEmpty ? "Ask about finger clubbing" : "Ask about your result")
                .font(.system(size: embedded ? 22 : 17, weight: .semibold))
            Spacer()
            if !embedded {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }
        }
        .padding(16)
    }

    private var disclaimer: some View {
        var text = "Answers are general information, not medical advice. This app doesn't diagnose any condition — talk to a doctor about any concerns."
        if let answeredBy = provider.answeredBy {
            text = "Answers come from \(answeredBy). Your questions and result numbers are sent to it, never your photo. " + text
        }
        return Label(text, systemImage: "info.circle")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .padding(12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func contextChip(_ angle: Double, _ verdict: ClubbingAssessment.Verdict) -> some View {
        Text(String(format: "Your reading: %.1f° · %@", angle, verdict.label))
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1), in: Capsule())
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            ForEach(suggestions, id: \.self) { question in
                Button { send(question) } label: {
                    Text(question)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func bubble(_ message: AssistantMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .padding(12)
                    .foregroundColor(.black)
                    .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
            }
        case .assistant:
            HStack {
                Text(message.text)
                    .padding(12)
                    .foregroundColor(.white)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                Spacer(minLength: 48)
            }
        case .notice:
            Text(message.text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask a question…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                .submitLabel(.send)
                .onSubmit { send(draft) }
            Button { send(draft) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(canSend ? .white : .gray)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var canSend: Bool {
        !waiting && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Sending

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !waiting else { return }
        draft = ""
        messages.append(AssistantMessage(role: .user, text: question))
        waiting = true
        let history = messages
        Task {
            do {
                let reply = try await provider.answer(question, history: history, context: context)
                messages.append(AssistantMessage(role: .assistant, text: reply))
            } catch {
                messages.append(AssistantMessage(role: .notice, text: "Couldn't get an answer right now. Please try again."))
            }
            waiting = false
        }
    }
}

/// Three dots that pulse while an answer is on its way.
private struct TypingIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 7, height: 7)
                    .phaseAnimator([0.3, 1.0]) { dot, phase in
                        dot.opacity(phase)
                    } animation: { _ in .easeInOut(duration: 0.5).delay(Double(i) * 0.15) }
            }
        }
        .foregroundColor(.white.opacity(0.7))
        .padding(12)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    AskAssistantView(context: AssistantContext(readings: [
        FingerSigns(lovibond: 167.2, hyponychial: 179.5, depthRatio: 0.86),
        FingerSigns(lovibond: 169.4, hyponychial: 181.0, depthRatio: 0.84),
        FingerSigns(lovibond: 165.9, hyponychial: 178.2, depthRatio: 0.85),
    ]))
}
