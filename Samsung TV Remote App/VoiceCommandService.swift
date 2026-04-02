//
//  VoiceCommandService.swift
//  Samsung TV Remote
//
//  Voice control for Samsung TV — uses on-device Speech Recognition
//  Say things like "volume up", "open Netflix", "channel down", "mute", "go home"
//

import Foundation
import Speech
import AVFoundation
import Combine

// MARK: - Voice Command Result

enum VoiceCommandResult: Equatable {
    case key(String)                  // sendKey(_:)
    case launchApp(String)            // launchApp(appId:)
    case unknown(String)              // recognized text but no match
}

// MARK: - Voice Listening State

enum VoiceState: Equatable {
    case idle
    case listening
    case processing
    case unauthorized
    case error(String)
}

// MARK: - VoiceCommandService

@MainActor
class VoiceCommandService: ObservableObject {

    @Published var state: VoiceState = .idle
    @Published var lastTranscript: String = ""
    @Published var lastResult: VoiceCommandResult?
    @Published var feedbackMessage: String = ""

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Auto-stop after silence (seconds)
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 2.0

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            state = .unauthorized
            return false
        }

        let micGranted = await AVAudioApplication.requestRecordPermission()
        return micGranted
    }

    // MARK: - Start / Stop Listening

    func startListening() {
        guard audioEngine.isRunning == false else { return }

        Task {
            let allowed = await requestPermissions()
            guard allowed else {
                state = .unauthorized
                feedbackMessage = "Microphone or speech access denied"
                return
            }
            beginRecognition()
        }
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        if case .listening = state {
            state = .idle
        }
    }

    // MARK: - Recognition Engine

    private func beginRecognition() {
        // Reset any previous session
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .error("Audio session error: \(error.localizedDescription)")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            state = .error("Audio engine error: \(error.localizedDescription)")
            return
        }

        state = .listening
        feedbackMessage = "Listening..."
        resetSilenceTimer()

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            Task { @MainActor in
                if let result {
                    let transcript = result.bestTranscription.formattedString
                    self.lastTranscript = transcript
                    self.feedbackMessage = "\"\(transcript)\""
                    self.resetSilenceTimer()

                    if result.isFinal {
                        self.handleTranscript(transcript)
                        self.stopListening()
                        self.state = .idle
                    }
                }

                if let error = error {
                    // Ignore cancellation errors
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        // No speech detected
                        self.feedbackMessage = "No speech detected"
                    } else if nsError.code != 301 {
                        self.state = .error(error.localizedDescription)
                    }
                    self.stopListening()
                    self.state = .idle
                }
            }
        }
    }

    // MARK: - Silence Timer

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopListening()
                if let transcript = self?.lastTranscript, !transcript.isEmpty {
                    self?.handleTranscript(transcript)
                }
                self?.state = .idle
            }
        }
    }

    // MARK: - Command Parsing

    func handleTranscript(_ raw: String) {
        let text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let result = parseCommand(text) {
            lastResult = result
            switch result {
            case .key(let k):
                feedbackMessage = keyLabel(k)
            case .launchApp(let id):
                feedbackMessage = "Opening \(appNameForId(id))..."
            case .unknown(let t):
                feedbackMessage = "\"\(t)\" — not recognized"
            }
        }
    }

    private func parseCommand(_ text: String) -> VoiceCommandResult? {

        // ── Volume ──────────────────────────────────────────────────
        if matches(text, ["volume up", "turn it up", "louder"]) {
            return .key("KEY_VOLUP")
        }
        if matches(text, ["volume down", "turn it down", "quieter", "lower volume"]) {
            return .key("KEY_VOLDOWN")
        }
        if matches(text, ["mute", "silence", "shut up", "quiet"]) {
            return .key("KEY_MUTE")
        }

        // ── Power ───────────────────────────────────────────────────
        if matches(text, ["power off", "turn off", "turn off the tv", "shut down", "sleep"]) {
            return .key("KEY_POWER")
        }
        if matches(text, ["power on", "turn on", "wake up"]) {
            return .key("KEY_POWER")
        }

        // ── Navigation ──────────────────────────────────────────────
        if matches(text, ["up", "go up", "move up", "scroll up"]) {
            return .key("KEY_UP")
        }
        if matches(text, ["down", "go down", "move down", "scroll down"]) {
            return .key("KEY_DOWN")
        }
        if matches(text, ["left", "go left", "move left"]) {
            return .key("KEY_LEFT")
        }
        if matches(text, ["right", "go right", "move right"]) {
            return .key("KEY_RIGHT")
        }
        if matches(text, ["ok", "okay", "select", "enter", "confirm", "press ok"]) {
            return .key("KEY_ENTER")
        }

        // ── Channels ────────────────────────────────────────────────
        if matches(text, ["channel up", "next channel", "channel plus"]) {
            return .key("KEY_CHUP")
        }
        if matches(text, ["channel down", "previous channel", "channel minus", "last channel"]) {
            return .key("KEY_CHDOWN")
        }

        // ── Playback ────────────────────────────────────────────────
        if matches(text, ["play", "resume", "unpause", "start"]) {
            return .key("KEY_PLAY")
        }
        if matches(text, ["pause", "stop", "freeze", "hold"]) {
            return .key("KEY_PAUSE")
        }
        if matches(text, ["fast forward", "skip ahead", "forward"]) {
            return .key("KEY_FF")
        }
        if matches(text, ["rewind", "skip back", "backwards"]) {
            return .key("KEY_REWIND")
        }

        // ── Navigation extras ───────────────────────────────────────
        if matches(text, ["back", "go back", "return", "previous"]) {
            return .key("KEY_RETURN")
        }
        if matches(text, ["home", "go home", "main menu", "home screen"]) {
            return .key("KEY_HOME")
        }
        if matches(text, ["menu", "settings", "open menu"]) {
            return .key("KEY_MENU")
        }
        if matches(text, ["info", "information", "details"]) {
            return .key("KEY_INFO")
        }
        if matches(text, ["guide", "tv guide", "program guide"]) {
            return .key("KEY_GUIDE")
        }
        if matches(text, ["exit", "close", "dismiss"]) {
            return .key("KEY_EXIT")
        }

        // ── Number pad ──────────────────────────────────────────────
        for (word, key) in numberWords {
            if text == word || text == "press \(word)" || text == "channel \(word)" {
                return .key(key)
            }
        }

        // ── App Launches ────────────────────────────────────────────
        if let appResult = parseAppLaunch(text) {
            return appResult
        }

        return .unknown(text)
    }

    private func parseAppLaunch(_ text: String) -> VoiceCommandResult? {
        // "open Netflix", "launch YouTube", "play Netflix", "go to Hulu", "Netflix"
        let prefixes = ["open ", "launch ", "play ", "go to ", "start ", "watch "]
        var query = text
        for prefix in prefixes {
            if text.hasPrefix(prefix) {
                query = String(text.dropFirst(prefix.count))
                break
            }
        }

        for (names, appId) in appAliases {
            if names.contains(where: { query.contains($0) }) {
                return .launchApp(appId)
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func matches(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text == $0 || text.contains($0) }
    }

    private func keyLabel(_ key: String) -> String {
        keyLabels[key] ?? key
    }

    private func appNameForId(_ id: String) -> String {
        appAliases.first(where: { $0.1 == id })?.0.first?.capitalized ?? id
    }

    // MARK: - App Alias Table

    private let appAliases: [([String], String)] = [
        (["netflix"],               "3201907018807"),
        (["youtube", "you tube"],   "111299001912"),
        (["prime video", "amazon prime", "prime"], "3201910019365"),
        (["hulu"],                  "3201601007625"),
        (["apple tv", "apple tv+"], "3201807016597"),
        (["max", "hbo max", "hbo"], "3202301029760"),
        (["disney+", "disney plus", "disney"], "3201901017640"),
        (["peacock"],               "3202006020991"),
        (["paramount+", "paramount plus", "paramount"], "3202110025305"),
        (["espn"],                  "3201708014618"),
        (["spotify"],               "3201606009684"),
        (["apple music"],           "3201908019041"),
        (["pluto", "pluto tv"],     "3201808016802"),
        (["plex"],                  "3201512006963"),
        (["twitch"],                "3202203026841"),
        (["youtube tv"],            "3201707014489"),
        (["tubi"],                  "3201504001965"),
    ]

    private let numberWords: [(String, String)] = [
        ("zero", "KEY_0"), ("one", "KEY_1"), ("two", "KEY_2"),
        ("three", "KEY_3"), ("four", "KEY_4"), ("five", "KEY_5"),
        ("six", "KEY_6"), ("seven", "KEY_7"), ("eight", "KEY_8"),
        ("nine", "KEY_9"),
    ]

    private let keyLabels: [String: String] = [
        "KEY_VOLUP":   "🔊 Volume Up",
        "KEY_VOLDOWN": "🔉 Volume Down",
        "KEY_MUTE":    "🔇 Mute",
        "KEY_POWER":   "⏻ Power",
        "KEY_UP":      "⬆️ Up",
        "KEY_DOWN":    "⬇️ Down",
        "KEY_LEFT":    "⬅️ Left",
        "KEY_RIGHT":   "➡️ Right",
        "KEY_ENTER":   "✅ Select",
        "KEY_CHUP":    "📺 Channel Up",
        "KEY_CHDOWN":  "📺 Channel Down",
        "KEY_PLAY":    "▶️ Play",
        "KEY_PAUSE":   "⏸ Pause",
        "KEY_FF":      "⏩ Fast Forward",
        "KEY_REWIND":  "⏪ Rewind",
        "KEY_RETURN":  "↩️ Back",
        "KEY_HOME":    "🏠 Home",
        "KEY_MENU":    "☰ Menu",
        "KEY_INFO":    "ℹ️ Info",
        "KEY_GUIDE":   "📋 Guide",
        "KEY_EXIT":    "✖️ Exit",
    ]
}
