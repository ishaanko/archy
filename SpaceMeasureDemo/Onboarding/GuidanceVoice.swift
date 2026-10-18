import SwiftUI
import AVFoundation

/// Local narration. A Grok connection requires a separately configured service;
/// no API key, microphone recording, or outbound measurement transfer is included.
@MainActor @Observable
final class GuidanceVoice {
    private let synthesizer = AVSpeechSynthesizer()

    func read(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.46
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

struct GuidanceSettingsView: View {
    @AppStorage("accessibility.voiceGuidance") private var automaticNarration = false
    @AppStorage("accessibility.readingFriendly") private var readingFriendly = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Make this feel right for you") {
                    Toggle("Read each step aloud", isOn: $automaticNarration)
                    Toggle("Reading-friendly layout", isOn: $readingFriendly)
                    Text("Adds line spacing and a rounded typeface. Uses your iPhone’s text-size settings.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Voice guidance") {
                    Label("On-device narration available", systemImage: "speaker.wave.2.fill")
                    Label("Grok voice is not connected", systemImage: "network.slash")
                    Text("Read-aloud works on this device. A live Grok conversation needs a configured service and an explicit choice to share voice data. This prototype does not record or send audio.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Accessibility").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
