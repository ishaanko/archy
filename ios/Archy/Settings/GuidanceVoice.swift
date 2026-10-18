import SwiftUI
import AVFoundation
import Security

/// Proxy credentials are separate from the server-side xAI API key.
enum VoiceConnection {
    static let service = "com.dubhacks.archy.voice-proxy"
    static func token() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "proxy", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func saveToken(_ token: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "proxy"]
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess }
        return status == errSecSuccess
    }
    static func clearToken() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "proxy"] as CFDictionary)
    }
    static func validURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", let host = url.host, !host.isEmpty,
              host != "api.x.ai", url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.hasSuffix("/narrate") else { return nil }
        return url
    }
}

@MainActor @Observable
final class GuidanceVoice {
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?
    private var audioCache: [String: Data] = [:]
    private(set) var status = "On-device narration available"

    /// Personalized quiz/history text always stays on-device.
    func read(_ text: String) {
        stop(); status = "On-device narration"
        speakLocally(text)
    }
    /// Only a public, fixed script ID is sent to the optional proxy. Never user text.
    func readScript(_ script: String, fallback: String) {
        stop()
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "voice.grokEnabled"),
              let url = VoiceConnection.validURL(defaults.string(forKey: "voice.proxyURL") ?? ""),
              let token = VoiceConnection.token(), token.count >= 24 else { read(fallback); return }
        if let bytes = audioCache[script], play(bytes) { status = "Grok voice · cached instruction"; return }
        status = "Loading Grok instruction…"
        task = Task {
            do {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(["script_id": script])
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCache = nil
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                // Bound response memory even if a configured proxy is misbehaving.
                let (stream, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      http.mimeType == "audio/mpeg", response.expectedContentLength <= 2_097_152 else { throw VoiceError.unavailable }
                var bytes = Data()
                for try await byte in stream {
                    guard bytes.count < 2_097_152 else { throw VoiceError.unavailable }
                    bytes.append(byte)
                }
                try Task.checkCancellation()
                guard UserDefaults.standard.bool(forKey: "voice.grokEnabled"), play(bytes) else { throw VoiceError.unavailable }
                audioCache[script] = bytes
                status = "Grok voice instruction"
            } catch {
                guard !Task.isCancelled else { return }
                status = "Grok unavailable · using on-device narration"
                speakLocally(fallback)
            }
        }
    }
    private func play(_ bytes: Data) -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            let audio = try AVAudioPlayer(data: bytes)
            player = audio
            return audio.play()
        } catch { return false }
    }
    private func speakLocally(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US"); utterance.rate = 0.46
        synthesizer.speak(utterance)
    }
    func stop() { task?.cancel(); task = nil; player?.stop(); player = nil; synthesizer.stopSpeaking(at: .immediate) }
    private enum VoiceError: Error { case unavailable }
}

struct GuidanceSettingsView: View {
    @AppStorage("accessibility.voiceGuidance") private var automaticNarration = false
    @AppStorage("accessibility.readingFriendly") private var readingFriendly = false
    @AppStorage("accessibility.audioCues") private var audioCues = false
    @AppStorage("voice.grokEnabled") private var grokEnabled = false
    @AppStorage("voice.proxyURL") private var savedURL = ""
    private enum ConnectionField: Hashable { case url, token }
    @FocusState private var focusedField: ConnectionField?
    @State private var hasSavedToken = false
    @State private var proxyURL = ""
    @State private var proxyToken = ""
    @State private var error: String?
    @State private var voice = GuidanceVoice()
    @Environment(\.dismiss) private var dismiss
    private var configured: Bool { VoiceConnection.validURL(savedURL) != nil && hasSavedToken }
    var body: some View {
        NavigationStack {
            Form {
                Section("Accessibility") {
                    Toggle("Read each step aloud", isOn: $automaticNarration)
                    Toggle("Reading-friendly layout", isOn: $readingFriendly)
                    Text("Rounded type and extra spacing. Follows your text-size settings.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Audio cues", isOn: $audioCues)
                    Text("Sounds mark exercise changes. All accessibility features are free.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Voice guidance") {
                    Label("On-device narration available", systemImage: "speaker.wave.2.fill")
                    Label(configured ? "Grok connection configured" : "Grok voice is not connected", systemImage: configured ? "network" : "network.slash")
                    Toggle("Use Grok for public instructions", isOn: $grokEnabled).disabled(!configured).accessibilityIdentifier("settings.grok")
                    Text("Enabling Grok sends instruction IDs and connection metadata to your service and xAI. No quiz answers, measurements, photos or microphone audio are sent. Personal read-aloud and fallback narration stay on-device.").font(.footnote).foregroundStyle(.secondary)
                    Button("Try voice instructions") { voice.readScript("welcome", fallback: "Welcome to Archy. Let us take this one gentle step at a time.") }.accessibilityIdentifier("settings.testVoice")
                    Text(voice.status).font(.caption).foregroundStyle(.secondary)
                }
                Section("Grok connection") {
                    TextField("https://your-service/narrate", text: $proxyURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).accessibilityIdentifier("settings.proxyURL").focused($focusedField, equals: .url)
                    SecureField("Service access token", text: $proxyToken).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("settings.proxyToken").focused($focusedField, equals: .token)
                    Text("Use a separate access token from your narration service. The xAI API key belongs on the server, never in this app.").font(.footnote).foregroundStyle(.secondary)
                    Button("Save connection") {
                        let text = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard VoiceConnection.validURL(text) != nil, proxyToken.count >= 24 else { error = "Enter an HTTPS /narrate URL and a service token of at least 24 characters."; return }
                        guard VoiceConnection.saveToken(proxyToken) else { error = "The service token could not be saved in Keychain."; return }
                        savedURL = text; hasSavedToken = true; grokEnabled = false; error = nil
                    }
                    Button("Remove connection", role: .destructive) { voice.stop(); grokEnabled = false; savedURL = ""; proxyURL = ""; proxyToken = ""; VoiceConnection.clearToken(); hasSavedToken = false; error = nil }
                    if let error { Text(error).foregroundStyle(.red).font(.caption) }
                    Text("Save, then enable Grok above when ready.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Accessibility").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { voice.stop(); dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focusedField = nil }.accessibilityIdentifier("settings.keyboardDone") }
                }
                .onAppear { proxyURL = savedURL; proxyToken = VoiceConnection.token() ?? ""; hasSavedToken = proxyToken.count >= 24 }
                .onChange(of: grokEnabled) { _, _ in voice.stop() }
                .onDisappear { voice.stop() }
        }
    }
}
