//
//  HistoryView.swift
//  NailVitals
//
//  The History tab: every check-up on this phone, newest first, and a
//  trend chart for each sign. Only the numbers are kept, never photos.
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: ScanHistory

    private enum Mode: String, CaseIterable {
        case checkups = "Check-ups"
        case trends = "Trends"
    }

    @State private var mode: Mode = .checkups
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Picker("Show", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 4)

                    switch mode {
                    case .checkups: checkups
                    case .trends: trends
                    }

                    SafetyNote()
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .background(AppBackground())
            .navigationTitle("History")
            .navigationDestination(for: UUID.self) { SessionDetailView(history: history, id: $0) }
            .confirmationDialog("Delete all saved results from this phone?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all results", role: .destructive) { history.deleteAll() }
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    @ViewBuilder
    private var checkups: some View {
        if history.sessions.isEmpty {
            EmptyStateCard(icon: "clock.arrow.circlepath",
                           title: "No check-ups yet",
                           text: "Each finished check-up shows up here, newest first. Only the numbers are saved, on this phone.")
                .padding(.top, 24)
        } else {
            ForEach(history.sessions.reversed()) { session in
                NavigationLink(value: session.id) {
                    SessionRow(session: session)
                }
                .buttonStyle(.plain)
            }
            Button("Delete all results on this phone", role: .destructive) { confirmDelete = true }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.attention)
                .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private var trends: some View {
        if history.sessions.count < 2 {
            EmptyStateCard(icon: "chart.xyaxis.line",
                           title: "Trends start at two check-ups",
                           text: "Each sign gets its own chart after your second check-up. Checking every few weeks shows whether anything changes.")
                .padding(.top, 24)
        } else {
            ForEach(SignKind.allCases, id: \.self) { kind in
                SignTrendCard(kind: kind, sessions: history.sessions)
            }
            Text("Dashed line: the published cut-off. Each point is one check-up.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }
}
