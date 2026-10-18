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
    private(set) var status = "On-device voice"

    /// Personalized quiz/history text always stays on-device.
    func read(_ text: String) {
        stop(); status = "On-device voice"
        speakLocally(text)
    }
    /// Only a public, fixed script ID is sent to the optional proxy. Never user text.
    func readScript(_ script: String, fallback: String) {
        stop()
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "voice.grokEnabled"),
              let url = VoiceConnection.validURL(defaults.string(forKey: "voice.proxyURL") ?? ""),
              let token = VoiceConnection.token(), token.count >= 24 else { read(fallback); return }
        if let bytes = audioCache[script], play(bytes) { status = "Grok voice (cached)"; return }
        status = "Loading Grok voice"
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
                status = "Grok voice"
            } catch {
                guard !Task.isCancelled else { return }
                status = "Grok unavailable, using on-device voice"
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

/// Reading, narration and optional Grok voice proxy settings. Shown as a sheet from onboarding and the tabs.
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
                Section {
                    Toggle("Read steps aloud", isOn: $automaticNarration)
                    Toggle("Reading-friendly type", isOn: $readingFriendly)
                    Toggle("Audio cues", isOn: $audioCues)
                }
                .listRowBackground(Color.surface)

                Section {
                    Toggle("Grok voice", isOn: $grokEnabled)
                        .disabled(!configured)
                        .accessibilityIdentifier("settings.grok")
                    Button {
                        voice.readScript("welcome", fallback: "Welcome to archy. Let's take this one step at a time.")
                    } label: {
                        HStack {
                            Text("Test voice")
                            Spacer()
                            Text(voice.status).font(.footnote).foregroundStyle(.inkTertiary)
                        }
                    }
                    .accessibilityIdentifier("settings.testVoice")
                } header: {
                    sectionHeader("Voice")
                } footer: {
                    Text("Grok sends only fixed instruction IDs to your service. Your answers, photos and audio stay on this iPhone.")
                }
                .listRowBackground(Color.surface)

                Section {
                    TextField("https://your-service/narrate", text: $proxyURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focusedField, equals: .url)
                        .accessibilityIdentifier("settings.proxyURL")
                    SecureField("Access token", text: $proxyToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .token)
                        .accessibilityIdentifier("settings.proxyToken")
                    Button("Save", action: saveConnection)
                    Button("Remove", role: .destructive, action: removeConnection)
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.negative)
                    }
                } header: {
                    sectionHeader("Voice proxy")
                } footer: {
                    Text("The token is stored in Keychain. Keep the xAI key on your server.")
                }
                .listRowBackground(Color.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { voice.stop(); dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }.accessibilityIdentifier("settings.keyboardDone")
                }
            }
            .onAppear { proxyURL = savedURL; proxyToken = VoiceConnection.token() ?? ""; hasSavedToken = proxyToken.count >= 24 }
            .onChange(of: grokEnabled) { _, _ in voice.stop() }
            .onDisappear { voice.stop() }
        }
        .archyScreen()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.footnote.weight(.medium)).textCase(nil).foregroundStyle(.inkSecondary)
    }

    private func saveConnection() {
        let text = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard VoiceConnection.validURL(text) != nil, proxyToken.count >= 24 else {
            error = "Needs an HTTPS /narrate URL and a token of 24+ characters."
            return
        }
        guard VoiceConnection.saveToken(proxyToken) else { error = "Couldn't save the token to Keychain."; return }
        savedURL = text; hasSavedToken = true; grokEnabled = false; error = nil
    }

    private func removeConnection() {
        voice.stop()
        grokEnabled = false; savedURL = ""; proxyURL = ""; proxyToken = ""
        VoiceConnection.clearToken(); hasSavedToken = false; error = nil
    }
}
