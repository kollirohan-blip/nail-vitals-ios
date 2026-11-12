//
//  ResultsListView.swift
//  NailVitals
//
//  A check-up in a list (SessionRow) and one check-up's page: its report
//  card, a question to the assistant, sending it to a doctor, and
//  deleting it.
//

import SwiftUI

/// One check-up in a list: when it was, the finger and its value, and the
/// overall state as a pill.
struct SessionRow: View {
    let session: ScanSession
    /// A small heading above the date ("Last result" on Home).
    var caption: String? = nil

    var body: some View {
        let report = session.report
        let value = report.results.first { $0.sign == .clubbing }?.valueText
        let detail = Text([session.handLabel + " index", value].compactMap { $0 }.joined(separator: " · "))
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(Theme.secondaryText)
        VStack(alignment: .leading, spacing: 6) {
            if let caption {
                Text(caption)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(ReportCardView.dayText(session.date))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            // Side by side when both fit on one line; stacked otherwise
            // (long state names, very large text).
            ViewThatFits(in: .horizontal) {
                HStack {
                    detail
                    Spacer(minLength: 8)
                    StatePill(state: report.overall)
                }
                VStack(alignment: .leading, spacing: 6) {
                    detail
                    StatePill(state: report.overall)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
        .glassCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }
}

struct SessionDetailView: View {
    @ObservedObject var history: ScanHistory
    let id: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var showAssistant = false
    @State private var confirmDelete = false
    @State private var exportFile: ShareFile?
    @State private var exportError: String?
    /// The sign whose page is open.
    @State private var openSign: NailSign?

    var body: some View {
        ScrollView {
            if let session = history.session(id) {
                content(session)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
        }
        .background(AppBackground())
        .navigationTitle(history.session(id)?.date.formatted(date: .abbreviated, time: .omitted) ?? "Result")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAssistant) {
            if let session = history.session(id) {
                AskAssistantView(context: AssistantContext(readings: session.signs,
                                                           hand: MeasuredHand(rawValue: session.hand) ?? .right))
            }
        }
        .sheet(item: $exportFile) { file in
            ActivityView(items: [file.url])
        }
        .navigationDestination(item: $openSign) { sign in
            if let session = history.session(id) {
                SignDetailView(sign: sign, readings: session.signs, extra: session.extraSigns ?? [],
                               recent: history.sessions.filter { $0.id != id && $0.date < session.date }.reversed())
            }
        }
        .confirmationDialog("Delete this result?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete result", role: .destructive) {
                dismiss()
                history.delete(id)
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func content(_ session: ScanSession) -> some View {
        VStack(spacing: 16) {
            ReportCardView(readings: session.signs, extra: session.extraSigns ?? [],
                           hand: MeasuredHand(rawValue: session.hand) ?? .right, date: session.date,
                           onOpen: { openSign = $0 })

            Button { showAssistant = true } label: {
                Label("Ask about this result", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .glassCard(cornerRadius: 20)

            // For a doctor's record system: the result as structured data.
            Button {
                do {
                    exportFile = ShareFile(url: try FHIRExport.file(for: session))
                } catch {
                    exportError = "Couldn't create the file. Try again."
                }
            } label: {
                Label("Send to doctor (FHIR file)", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .glassCard(cornerRadius: 20)
            if let exportError {
                Text(exportError).font(.footnote).foregroundStyle(Theme.attention)
            }

            Button("Delete this result", role: .destructive) { confirmDelete = true }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.attention)
                .frame(minHeight: 44)

            SafetyNote()
        }
    }
}

extension ScanSession {
    var handLabel: String { MeasuredHand(rawValue: hand)?.label ?? "Right" }
}

extension SignKind {
    func formattedOrDash(_ value: Double?) -> String {
        value.map(formatted) ?? "—"
    }
}
