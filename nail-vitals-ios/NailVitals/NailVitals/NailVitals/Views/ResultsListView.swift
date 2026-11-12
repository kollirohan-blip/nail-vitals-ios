//
//  ResultsListView.swift
//  NailVitals
//
//  A check-up in a list (SessionRow) and one check-up's page: its report
//  card, a question to the assistant, sending it to a doctor, and
//  deleting it.
//

import SwiftUI

struct ResultsListView: View {
    @ObservedObject var history: ScanHistory
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if history.sessions.isEmpty {
                        EmptyStateCard(icon: "list.bullet.rectangle.portrait",
                                       title: "No results yet",
                                       text: "Each finished scan shows up here, newest first. Only the numbers are saved, on this phone.")
                            .padding(.top, 40)
                    } else {
                        ForEach(history.sessions.reversed()) { session in
                            NavigationLink(value: session.id) {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                        Button("Delete all results on this phone", role: .destructive) { confirmDelete = true }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.attention.opacity(0.85))
                            .padding(.top, 10)
                    }
                    SafetyNote()
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .background(AppBackground())
            .navigationTitle("Results")
            .navigationDestination(for: UUID.self) { SessionDetailView(history: history, id: $0) }
            .confirmationDialog("Delete all saved results from this phone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all results", role: .destructive) { history.deleteAll() }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}

/// One check-up in a list: when it was, the finger and its value, and the
/// overall state as a pill.
struct SessionRow: View {
    let session: ScanSession
    /// A small heading above the date ("Last result" on Home).
    var caption: String? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let report = session.report
        let value = report.results.first { $0.sign == .clubbing }?.valueText
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let caption {
                    Text(caption)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(ReportCardView.dayText(session.date))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text([session.handLabel + " index", value.map { "nail angle " + $0 }].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
                if typeSize.isAccessibilitySize {
                    StatePill(state: report.overall)
                }
            }
            Spacer(minLength: 8)
            if !typeSize.isAccessibilitySize {
                StatePill(state: report.overall)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(minHeight: 44)
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

    /// Most readings found no cuticle dip (the profile counts as ≥180°).
    var mostlyNoDip: Bool { readings.filter(\.noCuticleDip).count * 2 > readings.count }

    /// "168.0° · 179.0°\nratio 0.84": the two angles, then the depth ratio.
    func valuesSummary(_ assessment: ClubbingAssessment) -> String {
        let profile = mostlyNoDip ? "≥180°" : SignKind.lovibond.formattedOrDash(assessment.values[.lovibond])
        let hyponychial = SignKind.hyponychial.formattedOrDash(assessment.values[.hyponychial])
        return "\(profile) · \(hyponychial)\nratio \(SignKind.depthRatio.formattedOrDash(assessment.values[.depthRatio]))"
    }
}

extension SignKind {
    func formattedOrDash(_ value: Double?) -> String {
        value.map(formatted) ?? "—"
    }
}
