import SwiftUI

struct ResearchSource: Identifiable {
    let id: Int
    let topic: String
    let title: String
    let summary: String
    let publisher: String
    let url: URL
    let symbol: String
    static let all: [ResearchSource] = [
        .init(id: 1, topic: "Musculoskeletal adaptation", title: "The body adapts to unloading", summary: "NASA describes how reduced loading in microgravity affects bone and muscle, and why researchers study ways to preserve them.", publisher: "NASA · Counteracting Bone and Muscle Loss in Microgravity", url: URL(string: "https://www.nasa.gov/humans-in-space/counteracting-bone-and-muscle-loss-in-microgravity/")!, symbol: "figure.stand"),
        .init(id: 2, topic: "Reduced-gravity loading", title: "Model the load. Ask better questions.", summary: "NASA Glenn combines human and device models to study musculoskeletal loading and exercise. Simulation depends on assumptions and validation; a gravity selector alone cannot predict a person’s foot response.", publisher: "NASA Glenn · Musculoskeletal", url: URL(string: "https://www.nasa.gov/glenn/glenn-expertise-space-exploration/human-health-performance/computational-modeling/musculoskeletal/")!, symbol: "globe.americas"),
        .init(id: 3, topic: "Exercise countermeasures", title: "Movement is mission equipment", summary: "NASA’s exercise physiology team evaluates exercise hardware, protocols and conditioning to help maintain crew health and performance during spaceflight.", publisher: "NASA · Exercise Physiology and Countermeasures", url: URL(string: "https://www.nasa.gov/directorates/esdmd/hhp/exercise-physiology-and-countermeasures/")!, symbol: "figure.run"),
        .init(id: 4, topic: "Foot biomechanics", title: "A repeatable way to describe an arch", summary: "Butler and colleagues examine an Arch Height Index measurement system. AHI uses dorsum height at half of full foot length divided by truncated foot length. Instrument-based reliability does not establish the accuracy of a home tape protocol.", publisher: "Butler et al. · JAPMA, 2008 · 98(2):102–106", url: URL(string: "https://doi.org/10.7547/0980102")!, symbol: "shoeprints.fill")
    ]
}
struct ResearchView: View {
    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Eyebrow(text: "Research log / Evidence before imagination")
                    Text("Human bodies.\nNew frontiers.").font(.system(.largeTitle, weight: .medium))
                    Text("A reading room for the science behind the questions.").font(.title3).foregroundStyle(.secondary)
                    ForEach(ResearchSource.all) { source in
                        Panel(dark: true) {
                            HStack { Image(systemName: source.symbol).font(.title).foregroundStyle(Color.lunar); Spacer(); Text(String(format: "%02d", source.id)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
                            Eyebrow(text: source.topic)
                            Text(source.title).font(.title2.weight(.medium))
                            Text(source.summary).font(.callout).foregroundStyle(Color.archySecondary)
                            Text(source.publisher).font(.caption).foregroundStyle(.secondary)
                            if source.id == 4 { Text("Publication metadata confirmed; DOI destination availability unverified.").font(.caption2).foregroundStyle(.secondary) }
                            Link(destination: source.url) { Label("Read original source", systemImage: "arrow.up.right").font(.headline).foregroundStyle(Color.lunar) }
                        }
                    }
                    Text("NASA pages verified October 17, 2026. Journal reference checked against publication metadata. These sources support education; they do not validate this app’s illustrative simulation or insole concepts. No NASA affiliation.").font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
        }.foregroundStyle(Color.archyForeground).navigationTitle("Space Medicine").navigationBarTitleDisplayMode(.inline)
    }
}
