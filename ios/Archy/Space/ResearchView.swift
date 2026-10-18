import SwiftUI

/// A source behind the studio's gravity story. `year` is nil for living web pages.
struct ResearchSource: Identifiable {
    let title: String
    let source: String
    let year: Int?
    let url: URL
    var id: URL { url }

    static let all: [ResearchSource] = [
        .init(title: "Counteracting bone and muscle loss in microgravity", source: "NASA", year: nil, url: URL(string: "https://www.nasa.gov/humans-in-space/counteracting-bone-and-muscle-loss-in-microgravity/")!),
        .init(title: "Musculoskeletal modeling", source: "NASA Glenn", year: nil, url: URL(string: "https://www.nasa.gov/glenn/glenn-expertise-space-exploration/human-health-performance/computational-modeling/musculoskeletal/")!),
        .init(title: "Exercise physiology and countermeasures", source: "NASA", year: nil, url: URL(string: "https://www.nasa.gov/directorates/esdmd/hhp/exercise-physiology-and-countermeasures/")!),
        .init(title: "Arch height index measurement system: establishment of reliability and normative values", source: "Butler et al., JAPMA", year: 2008, url: URL(string: "https://doi.org/10.7547/0980102")!)
    ]
}

/// Dense list of sources; each row opens the original.
struct ResearchView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("The science").display(.title).reveal(0)
                VStack(spacing: 0) {
                    Hairline()
                    ForEach(Array(ResearchSource.all.enumerated()), id: \.element.id) { index, source in
                        Link(destination: source.url) {
                            VStack(spacing: 0) {
                                HStack(alignment: .top, spacing: Space.md) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(source.title).font(.body.weight(.medium)).multilineTextAlignment(.leading)
                                        Text(source.source).font(.footnote).foregroundStyle(.inkSecondary)
                                    }
                                    Spacer(minLength: Space.sm)
                                    if let year = source.year {
                                        Text(String(year)).font(.footnote).foregroundStyle(.inkTertiary).monospacedDigit()
                                    }
                                    Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.inkTertiary)
                                }
                                .padding(.vertical, Space.md)
                                Hairline()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.archyPressable)
                        .reveal(index + 1)
                    }
                }
                Text("Educational concept. These sources don't validate the insole designs. NASA pages checked October 2026. No NASA affiliation.")
                    .font(.footnote).foregroundStyle(.inkTertiary)
            }
            .padding(.horizontal, Space.page)
            .padding(.vertical, Space.sm)
        }
        .scrollIndicators(.hidden)
        .archyScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}
