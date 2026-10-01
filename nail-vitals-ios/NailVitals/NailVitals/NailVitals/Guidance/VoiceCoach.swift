//
//  VoiceCoach.swift
//  NailVitals
//
//  Short spoken cues while framing, so nobody has to read the screen with
//  a finger held up: "Move closer", "Turn your finger fully sideways", "Hold
//  still", "Got it". Speaks only when the advice changes, at most one cue
//  every 2.5 seconds (the "hold your finger up" reminder every 6), and can be
//  muted from the camera screen's menu.
//

import AVFoundation

final class VoiceCoach {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastPhrase: String?
    private var lastSpokenAt = Date.distantPast
    private var audioReady = false

    private let minGap: TimeInterval = 2.5
    private let reminderGap: TimeInterval = 6

    /// Speaks the cue for the current advice if it's new and enough time
    /// has passed.
    func update(_ direction: GuidanceDirection?) {
        guard let direction, let phrase = Self.phrase(for: direction) else { return }
        let now = Date()
        let gap = direction == .noFingerDetected ? reminderGap : minGap
        guard now.timeIntervalSince(lastSpokenAt) >= gap,
              phrase != lastPhrase || direction == .noFingerDetected else { return }
        speak(phrase)
    }

    /// Speaks right away, cutting off anything in progress.
    func speak(_ phrase: String) {
        prepareAudio()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synthesizer.speak(utterance)
        lastPhrase = phrase
        lastSpokenAt = Date()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Plays over other audio briefly (ducking it), even with the ringer
    /// switch on silent, since the cues are the point of turning this on.
    private func prepareAudio() {
        guard !audioReady else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        audioReady = true
    }

    static func phrase(for direction: GuidanceDirection) -> String? {
        switch direction {
        case .noFingerDetected: return "Hold your index finger up, side on, inside the frame."
        case .moveCloser: return "Move closer."
        case .moveBack: return "Move back."
        case .moveLeft: return "Move left."
        case .moveRight: return "Move right."
        case .moveUp: return "Move up."
        case .moveHandDown: return "Move down."
        case .straighten: return "Straighten your finger."
        case .turnToSide: return "Turn your finger fully sideways."
        case .looksGood: return "Hold still."
        }
    }
}
