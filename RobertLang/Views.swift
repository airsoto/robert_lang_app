import SwiftUI
import SafariServices
import PDFKit

struct RootView: View {
    @EnvironmentObject var library: OrigamiLibrary
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("Home", systemImage: "house") }
            NavigationStack { SectionView(section: "portfolio", title: "Portfolio") }.tabItem { Label("Portfolio", systemImage: "square.grid.2x2") }
            NavigationStack { SectionView(section: "events", title: "Events") }.tabItem { Label("Events", systemImage: "calendar") }
            NavigationStack { SectionView(section: "books_articles", title: "Books") }.tabItem { Label("Books", systemImage: "books.vertical") }
            NavigationStack { SearchView() }.tabItem { Label("Search", systemImage: "magnifyingglass") }
            NavigationStack { AboutView() }.tabItem { Label("About", systemImage: "person.crop.circle") }
        }
        .tint(Theme.gold)
    }
}

struct BrandHeader: View {
    var body: some View {
        Image("Brand").resizable().scaledToFit().accessibilityLabel("Robert J. Lang Origami")
            .padding(.bottom, 12)
    }
}

struct HomeView: View {
    @EnvironmentObject var library: OrigamiLibrary
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BrandHeader()
                Text("THE ART AND SCIENCE OF FOLDING").font(.system(size: 12, weight: .medium, design: .rounded)).tracking(2).foregroundStyle(Theme.gold)
                Text("Discover the work of Robert J. Lang").font(.system(size: 29, weight: .thin, design: .default))
                if library.loading { ProgressView("Updating collection…") }
                if let error = library.error { Text(error).foregroundStyle(.secondary).font(.footnote) }
                ForEach(["portfolio", "events", "books_articles", "about"], id: \.self) { section in
                    let title = ["portfolio":"Portfolio", "events":"Events", "books_articles":"Books & Articles", "about":"About"][section] ?? section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text(title).font(.title2.weight(.light)); Spacer(); Text("\(library.section(section).count)").foregroundStyle(Theme.gold) }
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(Array(library.section(section).prefix(10))) { page in
                                    NavigationLink { PageView(page: page) } label: { PageCard(page: page).frame(width: 175) }
                                }
                            }
                        }.scrollIndicators(.hidden)
                    }
                }
                CreditsView()
            }.padding(18)
        }.background(.black).navigationBarTitleDisplayMode(.inline)
    }
}

struct PageCard: View {
    let page: OrigamiPage
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: page.hero).frame(height: 145).clipped().background(Theme.surface)
            Text(page.title).font(.system(size: 15, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading).foregroundStyle(.white)
            Text(page.section.replacingOccurrences(of: "_", with: " ").uppercased()).font(.caption2).foregroundStyle(Theme.gold)
        }
    }
}

struct RemoteImage: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            case .failure: Image(systemName: "photo").resizable().scaledToFit().padding(36).foregroundStyle(.gray)
            default: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct SectionView: View {
    @EnvironmentObject var library: OrigamiLibrary
    let section: String
    let title: String
    @State private var query = ""
    @State private var selectedTag: String?
    private var tags: [String] { Array(Set(library.section(section).flatMap(\.tags))).sorted() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !tags.isEmpty { TagPicker(tags: tags, selected: $selectedTag) }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(library.results(text: query, section: section, tag: selectedTag)) { page in
                        NavigationLink { PageView(page: page) } label: { PageCard(page: page) }
                    }
                }
                if library.section(section).isEmpty { ContentUnavailableView("No pages loaded", systemImage: "doc.text.magnifyingglass", description: Text("Load langorigami.json to display the collection.")) }
            }.padding()
        }.background(.black).navigationTitle(title).searchable(text: $query, prompt: "Search \(title)")
    }
}

struct TagPicker: View {
    let tags: [String]
    @Binding var selected: String?
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                Button("All") { selected = nil }.buttonStyle(TagStyle(active: selected == nil))
                ForEach(tags, id: \.self) { tag in Button(tag) { selected = tag == selected ? nil : tag }.buttonStyle(TagStyle(active: selected == tag)) }
            }
        }.scrollIndicators(.hidden)
    }
}
struct TagStyle: ButtonStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.caption).padding(.horizontal, 12).padding(.vertical, 8)
            .background(active ? Theme.gold : Theme.surface, in: Capsule()).foregroundStyle(active ? .black : .white)
    }
}

struct SearchView: View {
    @EnvironmentObject var library: OrigamiLibrary
    @State private var query = ""
    @State private var section = "all"
    @State private var selectedTag: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Section", selection: $section) {
                    Text("All").tag("all"); Text("Portfolio").tag("portfolio"); Text("Events").tag("events"); Text("Books").tag("books_articles"); Text("About").tag("about")
                }.pickerStyle(.menu)
                if !library.tags.isEmpty { TagPicker(tags: library.tags, selected: $selectedTag) }
                Text("\(library.results(text: query, section: section == "all" ? nil : section, tag: selectedTag).count) results").font(.caption).foregroundStyle(.secondary)
                ForEach(library.results(text: query, section: section == "all" ? nil : section, tag: selectedTag)) { page in
                    NavigationLink { PageView(page: page) } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: page.hero).frame(width: 90, height: 80).clipped()
                            VStack(alignment: .leading) { Text(page.title).foregroundStyle(.white); Text(page.section).font(.caption).foregroundStyle(Theme.gold) }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                    Divider().overlay(Theme.surface)
                }
            }.padding()
        }.background(.black).navigationTitle("Search").searchable(text: $query, prompt: "Title, text, tags…")
    }
}

struct PageView: View {
    @EnvironmentObject var library: OrigamiLibrary
    let page: OrigamiPage
    @State private var externalURL: URL?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let hero = page.hero { RemoteImage(url: hero).frame(height: 270).clipped() }
                Text(page.title).font(.system(size: 32, weight: .thin))
                if !page.description.isEmpty { Text(page.description).foregroundStyle(Theme.gold) }
                if !page.tags.isEmpty { FlowTags(tags: page.tags) }
                if !page.images.isEmpty {
                    Text("Gallery").font(.title3)
                    ScrollView(.horizontal) {
                        HStack { ForEach(Array(page.images.dropFirst())) { image in
                            VStack(alignment: .leading) {
                                RemoteImage(url: image.bestURL).frame(width: 230, height: 230).clipped()
                                if !image.caption.isEmpty { Text(image.caption).font(.caption).lineLimit(3) }
                            }.frame(width: 230)
                        } }
                    }.scrollIndicators(.hidden)
                }
                if !page.text.isEmpty { Text(page.text).font(.body).textSelection(.enabled) }
                if !page.resources.isEmpty {
                    Text("Documents & downloads").font(.title3)
                    ForEach(page.resources) { link in
                        Button { externalURL = URL(string: link.url) } label: {
                            Label(link.text.isEmpty ? (URL(string: link.url)?.lastPathComponent ?? "Resource") : link.text, systemImage: link.url.lowercased().contains(".pdf") ? "doc.richtext" : "arrow.down.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if !page.links.isEmpty {
                    Text("Related links").font(.title3)
                    ForEach(page.links.filter { !$0.url.contains("instagram.com") && !$0.url.contains("facebook.com") && !$0.url.contains("/wp-content/themes/") }.prefix(45)) { link in
                        if let related = library.page(for: link.url) {
                            NavigationLink(link.text.isEmpty ? related.title : link.text) { PageView(page: related) }
                        } else {
                            Button(link.text.isEmpty ? link.url : link.text) { externalURL = URL(string: link.url) }
                        }
                    }
                }
                Button("View original page") { externalURL = URL(string: page.url) }
                    .foregroundStyle(Theme.gold)
                CreditsView()
            }.tint(Theme.gold).padding(18)
        }.background(.black).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $externalURL) { url in
                if url.pathExtension.lowercased() == "pdf" { PDFReader(url: url) }
                else { SafariView(url: url) }
            }
    }
}

extension URL: Identifiable { public var id: String { absoluteString } }

struct FlowTags: View {
    let tags: [String]
    var body: some View {
        ScrollView(.horizontal) { HStack { ForEach(tags, id: \.self) { Text("#\($0)").font(.caption).padding(7).background(Theme.surface, in: Capsule()) } } }.scrollIndicators(.hidden)
    }
}
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
struct PDFReader: View {
    let url: URL
    @State private var document: PDFDocument?
    var body: some View {
        NavigationStack {
            Group {
                if let document { PDFKitView(document: document) }
                else { ProgressView("Loading PDF…") }
            }
            .navigationTitle("Document").navigationBarTitleDisplayMode(.inline)
            .task { if let (data, _) = try? await URLSession.shared.data(from: url) { document = PDFDocument(data: data) } }
        }
    }
}
struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; return view }
    func updateUIView(_ uiView: PDFView, context: Context) { uiView.document = document }
}
struct AboutView: View {
    @EnvironmentObject var library: OrigamiLibrary
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BrandHeader()
                Text("About Robert J. Lang").font(.title.weight(.light))
                ForEach(library.section("about")) { page in
                    NavigationLink { PageView(page: page) } label: { HStack { Text(page.title); Spacer(); Image(systemName: "chevron.right") } }
                }
                CreditsView()
            }.padding()
        }.background(.black).tint(Theme.gold).navigationTitle("About")
    }
}
struct CreditsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("© 2004–2026 Robert J. Lang").font(.caption)
            Text("iPhone app developed by Ángel Soto. Independent catalog viewer.").font(.caption)
            Link("Copyright and usage", destination: URL(string: "https://langorigami.com/copyright/")!)
                .font(.caption).foregroundStyle(Theme.gold)
        }.foregroundStyle(.secondary).padding(.top, 22)
    }
}
