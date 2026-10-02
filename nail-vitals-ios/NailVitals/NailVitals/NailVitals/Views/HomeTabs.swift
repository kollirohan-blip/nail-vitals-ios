//
//  HomeTabs.swift
//  NailVitals
//
//  The app's home side: five tabs on a Liquid Glass tab bar. Home keeps
//  only the scan button, the finger choice and the last result; all
//  results, trends, the guides and the chat each have their own tab.
//  Neutral colors here: color only marks result states.
//

import SwiftUI

enum AppTab: Hashable {
    case home, results, trends, learn, chat
}

struct HomeTabs: View {
    @ObservedObject var history: ScanHistory
    /// The scan button zooms open into the camera.
    var transition: Namespace.ID? = nil
    let onStartScan: () -> Void

    @State private var tab: AppTab = .home

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeTab(history: history, transition: transition, onStartScan: onStartScan)
            }
            Tab("Results", systemImage: "list.bullet.rectangle.portrait.fill", value: AppTab.results) {
                ResultsListView(history: history)
            }
            Tab("Trends", systemImage: "chart.xyaxis.line", value: AppTab.trends) {
                TrendsView(history: history)
            }
            Tab("Learn", systemImage: "book.closed.fill", value: AppTab.learn) {
                LearnView()
            }
            Tab("Chat", systemImage: "bubble.left.and.text.bubble.right.fill", value: AppTab.chat) {
                // A fresh chat for each new result.
                AskAssistantView(context: AssistantContext(readings: history.latest?.signs ?? [],
                                                           hand: history.latest.flatMap { MeasuredHand(rawValue: $0.hand) } ?? .right),
                                 embedded: true)
                    .id(history.latest?.id)
            }
        }
        .tint(.primary)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// The scan button, the finger choice and the last result.
struct HomeTab: View {
    @ObservedObject var history: ScanHistory
    var transition: Namespace.ID? = nil
    let onStartScan: () -> Void

    @AppStorage("measuredHand") private var hand: MeasuredHand = .right
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .classic
    @State private var showStudy = false
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 20)
                    scanButton
                    Picker("Finger", selection: $hand) {
                        ForEach(MeasuredHand.allCases, id: \.self) { Text("\($0.label) index").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 230)
                    .padding(.top, 30)
                    Text("Checks for finger clubbing · 3 quick side photos")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .padding(.top, 10)
                    Spacer(minLength: 20)
                    lastResult
                    SafetyNote()
                        .padding(.top, 14)
                        .padding(.bottom, 10)
                }
                .padding(.horizontal, 20)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { SessionDetailView(history: history, id: $0) }
            .sheet(isPresented: $showStudy) { StudyPanelView() }
        }
    }

    /// The small logo in the top-left corner, and one menu on the right.
    private var header: some View {
        HStack(alignment: .center) {
            BrandMark()
            Spacer()
            Menu {
                Picker("Look", selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                if saveCapturesForTesting {
                    Button { showStudy = true } label: {
                        Label("Study", systemImage: "person.2.fill")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .roundSurface()
            }
            .accessibilityLabel("Options")
        }
        .padding(.leading, 6)
        .padding(.top, 14)
    }

    /// A big disc (glass in Dark, white in Classic) with a slow breathing ring.
    private var scanButton: some View {
        Button(action: onStartScan) {
            VStack(spacing: 10) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 46, weight: .light))
                Text("Scan")
                    .font(.system(size: 22, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(width: 196, height: 196)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .roundSurface()
        .background {
            Circle()
                .stroke(Color.primary.opacity(0.18), lineWidth: 1.5)
                .scaleEffect(breathe ? 1.16 : 1.02)
                .opacity(breathe ? 0 : 1)
        }
        .modifier(ScanTransitionSource(namespace: transition))
        .accessibilityLabel("Start scan")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false)) { breathe = true }
        }
    }

    @ViewBuilder
    private var lastResult: some View {
        if let latest = history.latest {
            NavigationLink(value: latest.id) {
                SessionRow(session: latest, caption: "Last result")
            }
            .buttonStyle(.plain)
        } else {
            Text("Your results show up here after your first scan.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(16)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 22)
        }
    }
}

/// The logo, small: a mini app icon (the finger with its cuticle angle on a
/// rounded tile, white in Classic and dark gray in Dark, like the real
/// icon) and the name.
struct BrandMark: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: 9, style: .continuous)
        HStack(spacing: 10) {
            ZStack {
                FingerProfileShape()
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                LovibondAngleMark()
                    .stroke(Theme.aligned, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .frame(width: 18, height: 22)
            .offset(x: -1, y: 1)
            .frame(width: 32, height: 32)
            .background(scheme == .dark ? Color(red: 0.13, green: 0.14, blue: 0.16) : .white, in: tile)
            .overlay(tile.stroke(Color.primary.opacity(0.1), lineWidth: 1))
            Text("Nail Vitals")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Marks the scan button as where the camera zooms open from.
struct ScanTransitionSource: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: "scan", in: namespace)
        } else {
            content
        }
    }
}
