//
//  ResultsListView.swift
//  NailVitals
//
//  The Results tab: every finished scan on this phone, newest first, and
//  one scan's detail -- the verdict, each sign, each reading, a question
//  to the assistant, and deleting it.
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

/// One scan in a list: verdict dot and label, date and finger, the values.
struct SessionRow: View {
    let session: ScanSession
    /// A small heading above the verdict ("Last result" on Home).
    var caption: String? = nil

    var body: some View {
        let assessment = ClubbingAssessment(readings: session.signs)
        let color = ResultView.color(for: assessment.verdict)
        HStack(spacing: 14) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.7), radius: 5)
            VStack(alignment: .leading, spacing: 3) {
                if let caption {
                    Text(caption)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .textCase(.uppercase)
                }
                Text(assessment.verdict.label)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
                Text("\(session.date.formatted(.dateTime.month(.abbreviated).day())) · \(session.handLabel) index")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
            Spacer(minLength: 8)
            Text(session.valuesSummary(assessment))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.primary.opacity(0.75))
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
        }
        .padding(16)
        .contentShape(.rect)
        .glassCard(cornerRadius: 22)
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
        let readings = session.signs
        let assessment = ClubbingAssessment(readings: readings)
        let steady = readings.count >= ClubbingAssessment.readingsForSteadyResult
        let noDip = session.mostlyNoDip
        let color = ResultView.color(for: assessment.verdict)
        return VStack(spacing: 16) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(color)
                        .frame(width: 12, height: 12)
                        .shadow(color: color.opacity(0.7), radius: 6)
                    Text(assessment.verdict.label)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(ResultView.verdictDetail(assessment, steady: steady, noDip: noDip))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(readings.count) reading\(readings.count == 1 ? "" : "s") · \(session.handLabel) index · \(session.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 26)

            HStack(spacing: 8) {
                ForEach(SignKind.allCases, id: \.self) { kind in
                    SignChip(kind: kind, value: assessment.values[kind],
                             valueText: kind == .lovibond && noDip ? "≥180°" : nil)
                }
            }

            readingsTable(readings)

            Button { showAssistant = true } label: {
                Label("Ask about this result", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)

            // For a doctor's record system: the result as structured data.
            Button {
                do {
                    exportFile = ShareFile(url: try FHIRExport.file(for: session))
                } catch {
                    exportError = "Couldn't create the file. Try again."
                }
            } label: {
                Label("Export for a doctor (FHIR)", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Color.primary.opacity(0.75))
            if let exportError {
                Text(exportError).font(.system(size: 13)).foregroundStyle(Theme.attention)
            }

            Button("Delete this result", role: .destructive) { confirmDelete = true }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.attention.opacity(0.85))

            SafetyNote()
        }
    }

    /// Each reading's three values; the result uses each sign's middle one.
    private func readingsTable(_ readings: [FingerSigns]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Readings")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
                .textCase(.uppercase)
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("#").gridColumnAlignment(.leading)
                    Text("Nail")
                    Text("Fingertip")
                    Text("Thickness")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.6))
                ForEach(Array(readings.enumerated()), id: \.offset) { index, reading in
                    GridRow {
                        Text("\(index + 1)")
                            .foregroundStyle(Color.primary.opacity(0.6))
                        Text(reading.noCuticleDip ? "≥180°" : SignKind.lovibond.formattedOrDash(reading.lovibond))
                        Text(SignKind.hyponychial.formattedOrDash(reading.hyponychial))
                        Text(SignKind.depthRatio.formattedOrDash(reading.depthRatio))
                    }
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity)
            if readings.count >= ClubbingAssessment.readingsForSteadyResult {
                Text("The result uses the middle value of each sign.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
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
