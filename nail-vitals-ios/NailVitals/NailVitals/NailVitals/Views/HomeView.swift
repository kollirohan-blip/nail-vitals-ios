//
//  HomeView.swift
//  NailVitals
//
//  The Home tab, as little as possible: one status line, one picture (your
//  latest nail angle on the app's arc, or the pose for someone new), one
//  button to start an assessment, one row for the other tests, and one
//  line on privacy and what the app is. Everything else (look, finger,
//  reminder, data, research tools) is in Settings behind the gear.
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var history: ScanHistory
    /// The start button zooms open into the camera.
    var transition: Namespace.ID? = nil
    let onStartScan: () -> Void
    /// Scans a printed model finger on a stand (no hand to detect).
    var onStartModelScan: () -> Void = {}

    @AppStorage("measuredHand") private var hand: MeasuredHand = .right
    @State private var showSettings = false
    @State private var showMoreTests = false
    @State private var showNailCheck = false
    @State private var showSchamroth = false
    @State private var openLatest: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.component) {
                    header
                    statusLine
                    hero
                    VStack(spacing: Spacing.tight) {
                        startButton
                        Text("3 guided side photos · about a minute")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                        fingerPicker
                            .padding(.top, Spacing.tight)
                    }
                    moreTests
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.bottom, Spacing.component)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $openLatest) { SessionDetailView(history: history, id: $0) }
            .sheet(isPresented: $showSettings) {
                SettingsView(history: history, onStartModelScan: onStartModelScan)
            }
            .sheet(isPresented: $showMoreTests) { moreTestsSheet }
            .fullScreenCover(isPresented: $showNailCheck) { NailCheckView().dynamicTypeSize(...DynamicTypeSize.accessibility1) }
            .fullScreenCover(isPresented: $showSchamroth) { SchamrothView().dynamicTypeSize(...DynamicTypeSize.accessibility1) }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            BrandMark()
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    // Fixed size: the icon sits in a fixed 44-pt disc.
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .roundSurface()
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 10)
    }

    private var statusLine: some View {
        Text(CheckupWording.statusLine(hand: history.latest.flatMap { MeasuredHand(rawValue: $0.hand) },
                                       overall: history.latest?.report.overall,
                                       date: history.latest?.date))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The latest nail angle on the arc (tap to open it), or the pose to
    /// hold for someone who hasn't assessed yet.
    @ViewBuilder
    private var hero: some View {
        if let latest = history.latest, let angle = latest.report.assessment.values[.lovibond] {
            let report = latest.report
            Button { openLatest = latest.id } label: {
                VStack(spacing: Spacing.tight) {
                    ResultGauge(angle: angle, uncertainty: report.noDip ? 0 : (Repeatability.range95[.lovibond] ?? 0))
                        .frame(width: 280, height: 170)
                        .accessibilityHidden(true)
                    Text(report.noDip ? "≥180°" : SignKind.lovibond.formatted(angle))
                        .heroNumber()
                        .foregroundStyle(Theme.text)
                    HStack(spacing: Spacing.tight) {
                        StatePill(state: report.overall)
                        Text("Latest nail angle")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.pressableCard)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Latest nail angle \(report.noDip ? "180 degrees or more" : SignKind.lovibond.formatted(angle)), \(report.overall.label). Opens the result.")
        } else {
            VStack(spacing: Spacing.normal) {
                ZStack {
                    FingerProfileShape()
                        .stroke(Theme.text, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    LovibondAngleMark()
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
                .frame(width: 96, height: 170)
                Text("Point your index finger up, side-on. The photo takes itself.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.tight)
            .accessibilityElement(children: .combine)
        }
    }

    private var startButton: some View {
        Button(action: onStartScan) {
            Label("Start assessment", systemImage: "viewfinder")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.pressableCard)
        .modifier(ScanTransitionSource(namespace: transition))
        .accessibilityHint("3 guided side photos of your \(hand.label.lowercased()) index finger")
    }

    /// Which index finger the assessment measures.
    private var fingerPicker: some View {
        Picker("Finger", selection: $hand) {
            ForEach(MeasuredHand.allCases, id: \.self) { Text("\($0.label) index").tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
        .accessibilityLabel("Finger to measure")
    }

    private var moreTests: some View {
        Button { showMoreTests = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("More tests")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("Nail appearance · Schamroth window")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.normal)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
            .glassCard(cornerRadius: 20)
        }
        .buttonStyle(.pressableCard)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Label("Photos never leave this phone", systemImage: "lock.fill")
                .font(.footnote.weight(.medium))
            Text("A screening aid, not a diagnosis.")
                .font(.footnote)
        }
        .foregroundStyle(Theme.secondaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - More tests

    private var moreTestsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.normal) {
                    Text("These tests are still being checked for accuracy. They don't affect your assessment result.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    testRow("Nail appearance", "Pale nails with a darker band at the tip, the pattern of Terry's and half-and-half nails. From a photo of your nails from above.", icon: "hand.raised.fingers.spread") {
                        showMoreTests = false
                        showNailCheck = true
                    }
                    testRow("Schamroth window", "Press the backs of your two index fingertips together, nail to nail. A small diamond-shaped gap normally shows between them.", icon: "rhombus") {
                        showMoreTests = false
                        showSchamroth = true
                    }
                }
                .padding(20)
            }
            .background(AppBackground())
            .navigationTitle("More tests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showMoreTests = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .tint(Theme.accent)
    }

    private func testRow(_ title: String, _ detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { testTitle(title); validationTag }
                        VStack(alignment: .leading, spacing: 2) { testTitle(title); validationTag }
                    }
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.normal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .glassCard(cornerRadius: 20)
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel("\(title), validation in progress: \(detail)")
    }

    private func testTitle(_ title: String) -> some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.text)
    }

    private var validationTag: some View {
        Text("Validation in progress")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
    }
}
