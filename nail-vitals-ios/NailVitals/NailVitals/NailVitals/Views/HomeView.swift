//
//  HomeView.swift
//  NailVitals
//
//  The start screen: one big Start scan button, the last result, the trend
//  across past scans, and the guide, sources and assistant. History lives
//  only on this phone (ScanHistory) and holds numbers, not photos.
//

import SwiftUI
import Charts

struct HomeView: View {
    @ObservedObject var history: ScanHistory
    /// The Start scan button zooms open into the camera.
    var transition: Namespace.ID? = nil
    let onStartScan: () -> Void

    @AppStorage("measuredHand") private var hand: MeasuredHand = .right
    @State private var showGuide = false
    @State private var showAbout = false
    @State private var showAssistant = false
    @State private var showStudy = false
    @State private var confirmDelete = false
    @State private var glow = false

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(spacing: 22) {
                    header
                    startCard
                    if let latest = history.latest {
                        lastResultCard(latest)
                        trendCard
                    } else {
                        emptyCard
                    }
                    links
                    if !history.sessions.isEmpty {
                        Button("Delete history on this phone", role: .destructive) { confirmDelete = true }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.attention.opacity(0.8))
                    }
                    Text("This tool flags a pattern that may be worth discussing with a doctor. It does not diagnose any condition.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showGuide) { PoseGuideView() }
        .sheet(isPresented: $showAbout) { AboutMeasurementsView() }
        .sheet(isPresented: $showStudy) { StudyPanelView() }
        .sheet(isPresented: $showAssistant) {
            if let latest = history.latest {
                AskAssistantView(context: AssistantContext(readings: latest.signs, hand: MeasuredHand(rawValue: latest.hand) ?? .right))
            }
        }
        .confirmationDialog("Delete all saved results from this phone?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete history", role: .destructive) { history.deleteAll() }
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: - Pieces

    private var background: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Theme.searching.opacity(0.18), .clear], center: .top, startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Theme.aligned.opacity(0.08), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                FingerProfileShape()
                    .stroke(Theme.searching, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .shadow(color: Theme.searching.opacity(glow ? 0.9 : 0.4), radius: glow ? 10 : 5)
            }
            .frame(width: 34, height: 44)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glow = true }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Nail Vitals")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text("Finger clubbing check")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
            if saveCapturesForTesting {
                Button { showStudy = true } label: {
                    Label("Study", systemImage: "person.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
    }

    private var startCard: some View {
        VStack(spacing: 14) {
            Button(action: onStartScan) {
                HStack(spacing: 10) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 20, weight: .bold))
                    Text("Start scan")
                        .font(.system(size: 20, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(GlowButtonStyle(color: Theme.searching))
            .modifier(ScanTransitionSource(namespace: transition))
            HStack(spacing: 6) {
                Picker("Finger", selection: $hand) {
                    ForEach(MeasuredHand.allCases, id: \.self) { Text("\($0.label) index").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
            Text("3 quick photos of the side of your finger. About a minute.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .glassPanel(cornerRadius: 24)
    }

    private func lastResultCard(_ session: ScanSession) -> some View {
        let assessment = ClubbingAssessment(readings: session.signs)
        let noDip = session.signs.filter(\.noCuticleDip).count * 2 > session.signs.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last result")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .textCase(.uppercase)
                Spacer()
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
            HStack(spacing: 10) {
                Circle()
                    .fill(ResultView.color(for: assessment.verdict))
                    .frame(width: 12, height: 12)
                    .shadow(color: ResultView.color(for: assessment.verdict), radius: 6)
                Text(assessment.verdict.label)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(ResultView.color(for: assessment.verdict))
            }
            HStack(spacing: 8) {
                ForEach(SignKind.allCases, id: \.self) { kind in
                    SignChip(kind: kind, value: assessment.values[kind],
                             valueText: kind == .lovibond && noDip ? "≥180°" : nil)
                }
            }
            Text("\(session.readings.count) reading\(session.readings.count == 1 ? "" : "s") · \(MeasuredHand(rawValue: session.hand)?.label ?? "Right") index")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            Button { showAssistant = true } label: {
                Label("Ask about this result", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.searching)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .glassPanel(cornerRadius: 24)
    }

    /// Profile and hyponychial angles (middle of each session's readings)
    /// over time, with the published cut-offs.
    private var trendCard: some View {
        let points: [(Date, String, Double)] = history.sessions.flatMap { session -> [(Date, String, Double)] in
            let a = ClubbingAssessment(readings: session.signs)
            var out: [(Date, String, Double)] = []
            if let p = a.values[.lovibond] { out.append((session.date, "Profile", p)) }
            if let h = a.values[.hyponychial] { out.append((session.date, "Hyponychial", h)) }
            return out
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Your trend")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .textCase(.uppercase)
            if history.sessions.count < 2 {
                Text("Your trend shows up after two scans. Scanning every few weeks shows whether anything changes.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                Chart {
                    RuleMark(y: .value("Profile cut-off", SignKind.lovibond.threshold))
                        .foregroundStyle(Theme.searching.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("176°").font(.system(size: 10)).foregroundColor(Theme.searching.opacity(0.8))
                        }
                    RuleMark(y: .value("Hyponychial cut-off", SignKind.hyponychial.threshold))
                        .foregroundStyle(Theme.aligned.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("192°").font(.system(size: 10)).foregroundColor(Theme.aligned.opacity(0.8))
                        }
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Date", point.0), y: .value("Angle", point.2))
                            .foregroundStyle(by: .value("Sign", point.1))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", point.0), y: .value("Angle", point.2))
                            .foregroundStyle(by: .value("Sign", point.1))
                    }
                }
                .chartForegroundStyleScale(["Profile": Theme.searching, "Hyponychial": Theme.aligned])
                .chartYScale(domain: 150...205)
                .chartLegend(position: .bottom)
                .frame(height: 180)
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 24)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No scans yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            Text("Your results and how they change over time will show up here. Only the numbers are saved, on this phone.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPanel(cornerRadius: 24)
    }

    private var links: some View {
        HStack(spacing: 12) {
            linkButton("How to scan", icon: "hand.point.up.left.fill") { showGuide = true }
            linkButton("The science", icon: "book.closed.fill") { showAbout = true }
        }
    }

    private func linkButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.searching)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .glassPanel(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }
}

/// Marks the Start scan button as where the camera zooms open from.
private struct ScanTransitionSource: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: "scan", in: namespace)
        } else {
            content
        }
    }
}
