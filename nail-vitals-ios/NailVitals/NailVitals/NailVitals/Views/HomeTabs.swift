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
        .tint(.white)
        .tabBarMinimizeBehavior(.onScrollDown)
        .preferredColorScheme(.dark)
    }
}

/// The scan button, the finger choice and the last result.
struct HomeTab: View {
    @ObservedObject var history: ScanHistory
    var transition: Namespace.ID? = nil
    let onStartScan: () -> Void

    @AppStorage("measuredHand") private var hand: MeasuredHand = .right
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
                    Text("3 quick side photos · about a minute")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 10)
                    Spacer(minLength: 20)
                    lastResult
                    SafetyNote()
                        .padding(.top, 14)
                        .padding(.bottom, 10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { SessionDetailView(history: history, id: $0) }
            .sheet(isPresented: $showStudy) { StudyPanelView() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nail Vitals")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                Text("Finger clubbing check")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if saveCapturesForTesting {
                Button { showStudy = true } label: {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Study")
            }
        }
    }

    /// A big glass disc with a slow breathing ring.
    private var scanButton: some View {
        Button(action: onStartScan) {
            VStack(spacing: 10) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 46, weight: .light))
                Text("Scan")
                    .font(.system(size: 22, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 196, height: 196)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .background {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
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
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(16)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 22)
        }
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
