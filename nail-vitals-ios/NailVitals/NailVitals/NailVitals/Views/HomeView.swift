//
//  HomeView.swift
//  NailVitals
//
//  The Home tab: one big button to start a check-up, and nothing to
//  decide before it. Under it: what the app checks, the last result and a
//  small trend. Testing tools (study tags, the model finger) sit in the
//  options menu, out of the normal flow.
//

import SwiftUI
import Charts

struct HomeView: View {
    @ObservedObject var history: ScanHistory
    /// The start button zooms open into the camera.
    var transition: Namespace.ID? = nil
    let onStartScan: () -> Void
    /// Scans a printed model finger on a stand (no hand to detect).
    var onStartModelScan: () -> Void = {}
    /// Switches to the History tab.
    var onShowHistory: () -> Void = {}

    @AppStorage("measuredHand") private var hand: MeasuredHand = .right
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .classic
    @State private var showStudy = false
    @State private var showNailCheck = false
    @State private var showSchamroth = false
    @State private var showScience = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(CheckupWording.greeting(hour: Calendar.current.component(.hour, from: Date())))
                            .font(.title.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(CheckupWording.lastCheckupLine(date: history.latest?.date,
                                                            overall: history.latest?.report.overall))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 4) {
                        startButton
                        fingerMenu
                    }
                    checks
                    lastResult
                    if history.sessions.count >= 2 {
                        trend
                    }
                    SafetyNote()
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { SessionDetailView(history: history, id: $0) }
            .sheet(isPresented: $showStudy) { StudyPanelView() }
            .sheet(isPresented: $showScience) { AboutMeasurementsView() }
            .fullScreenCover(isPresented: $showNailCheck) { NailCheckView() }
            .fullScreenCover(isPresented: $showSchamroth) { SchamrothView() }
        }
    }

    /// The small logo, and one menu for the look and the testing tools.
    private var header: some View {
        HStack(alignment: .center) {
            BrandMark()
            Spacer()
            Menu {
                Picker("Look", selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                Button(action: onStartModelScan) {
                    Label("Scan a model finger", systemImage: "cube.transparent")
                }
                if saveCapturesForTesting {
                    Button { showStudy = true } label: {
                        Label("Study", systemImage: "person.2.fill")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    // Fixed size: the icon sits in a fixed 44-pt disc.
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .roundSurface()
            }
            .accessibilityLabel("Options")
        }
        .padding(.top, 10)
    }

    private var startButton: some View {
        Button(action: onStartScan) {
            VStack(spacing: 6) {
                Image(systemName: "viewfinder")
                    .font(.title.weight(.medium))
                Text("Start check-up")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("3 side photos of your index finger")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Theme.onAction)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .padding(.horizontal, 16)
            .background(Theme.action, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .modifier(ScanTransitionSource(namespace: transition))
        .accessibilityLabel("Start check-up. 3 side photos of your index finger.")
    }

    /// Which index finger the check-up measures.
    private var fingerMenu: some View {
        Menu {
            Picker("Finger", selection: $hand) {
                ForEach(MeasuredHand.allCases, id: \.self) { Text("\($0.label) index finger").tag($0) }
            }
        } label: {
            HStack(spacing: 6) {
                Text("\(hand.label) index finger")
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .accessibilityLabel("Finger to measure: \(hand.label) index finger")
    }

    // MARK: - What it checks

    private var checks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What it checks")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            // The main check, then the two beta tests side by side (stacked
            // at very large text sizes).
            Button { showScience = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "angle")
                        .font(.title3.weight(.medium))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Clubbing")
                            .font(.subheadline.weight(.semibold))
                        Text("Nail and fingertip shape: 3 signs from the side photos")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .foregroundStyle(.primary)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
                .glassCard(cornerRadius: 20)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Clubbing: nail and fingertip shape, 3 signs from the side photos. Opens the science.")

            let columns = typeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : [GridItem(.flexible(), spacing: 12), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 12) {
                betaTile("Nail colour", "Liver and kidney nail patterns", icon: "hand.raised.fingers.spread") { showNailCheck = true }
                betaTile("Schamroth window", "The gap between two nails", icon: "rhombus") { showSchamroth = true }
            }
        }
    }

    /// One of the beta tests, opened on its own.
    private func betaTile(_ title: String, _ detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Image(systemName: icon)
                        .font(.body.weight(.medium))
                    Spacer()
                    Text("Beta")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(minHeight: 24)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.primary)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .contentShape(.rect)
            .glassCard(cornerRadius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), beta test: \(detail)")
    }

    // MARK: - Last result and trend

    @ViewBuilder
    private var lastResult: some View {
        if let latest = history.latest {
            NavigationLink(value: latest.id) {
                SessionRow(session: latest, caption: "Last result")
            }
            .buttonStyle(.plain)
        } else {
            Text("Your results show up here after your first check-up.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(16)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 20)
        }
    }

    /// The nail angle across check-ups, small; opens History.
    private var trend: some View {
        let points = history.sessions.compactMap { session -> (date: Date, value: Double)? in
            session.report.assessment.values[.lovibond].map { (session.date, $0) }
        }
        return Button(action: onShowHistory) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your trend")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(history.sessions.count) check-ups")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                if points.count >= 2 {
                    Chart {
                        ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                            LineMark(x: .value("Check-up", index), y: .value("Nail angle", point.value))
                                .foregroundStyle(Theme.secondaryText)
                                .interpolationMethod(.monotone)
                        }
                        if let last = points.last {
                            PointMark(x: .value("Check-up", points.count - 1), y: .value("Nail angle", last.value))
                                .foregroundStyle(SignState(SignKind.lovibond.status(of: last.value)).color)
                                .symbolSize(40)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(width: 110, height: 36)
                    .accessibilityHidden(true)
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your trend: \(history.sessions.count) check-ups. Opens History.")
    }
}
