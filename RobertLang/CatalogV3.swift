import SwiftUI
import SafariServices
import PDFKit

// Catalog v3: native, category-aware presentation of the scraper's collections.
// Images and PDFs remain linked to their original publisher; no media is redistributed.

struct CatalogAsset: Identifiable, Hashable {
    let url: String
    let thumbnail: String
    let caption: String
    var id: String { url }
    var imageURL: URL? { URL(string: url) }
    init?(_ raw: [String: Any]) {
        let target = raw["url"] as? String ?? ""
        guard target.hasPrefix("https://"), !target.contains("1x1.trans"), !target.contains("no_cover_image") else { return nil }
        url = target
        thumbnail = raw["thumbnail"] as? String ?? target
        caption = raw["caption"] as? String ?? raw["alt"] as? String ?? ""
    }
}

struct CatalogReference: Identifiable {
    let url: String
    let label: String
    var id: String { url }
    init?(_ raw: [String: Any]) {
        guard let address = raw["url"] as? String, address.hasPrefix("https://") else { return nil }
        url = address
        label = raw["label"] as? String ?? raw["title"] as? String ?? ""
    }
}

struct CatalogEntry: Identifiable {
    let id: String
    let kind: String
    let title: String
    let url: String
    let opus: Int?
    let tags: [String]
    let metadata: [String: String]
    let description: String
    let bodyText: String
    let thumbnail: String?
    let cover: String?
    let gallery: [CatalogAsset]
    let pdfs: [CatalogReference]
    let links: [CatalogReference]
    let relatedURLs: [String]
    let searchKey: String

    init(_ raw: [String: Any], kind: String) {
        self.kind = kind
        id = raw["id"] as? String ?? raw["url"] as? String ?? UUID().uuidString
        title = raw["title"] as? String ?? "Untitled"
        url = raw["url"] as? String ?? ""
        opus = raw["opus"] as? Int
        let directTags = raw["tags"] as? [String] ?? []
        let taxonomy = raw["taxonomy_slugs"] as? [String] ?? []
        tags = Array(Set(directTags + taxonomy)).sorted()
        metadata = raw["metadata"] as? [String: String] ?? [:]
        description = raw["description"] as? String ?? ""
        bodyText = raw["body_text"] as? String ?? ""
        thumbnail = raw["thumbnail"] as? String
        cover = raw["cover_image"] as? String
        let rawGallery = raw["gallery"] as? [[String: Any]] ?? raw["images"] as? [[String: Any]] ?? []
        var seen: Set<String> = []
        gallery = rawGallery.compactMap(CatalogAsset.init).filter { seen.insert($0.url).inserted }
        pdfs = (raw["pdfs"] as? [[String: Any]] ?? []).compactMap(CatalogReference.init)
        var allLinks = raw["links"] as? [[String: Any]] ?? []
        if kind == "published_instructions" {
            allLinks += raw["publications"] as? [[String: Any]] ?? []
            allLinks += raw["examples"] as? [[String: Any]] ?? []
        }
        var used: Set<String> = []
        links = allLinks.compactMap(CatalogReference.init).filter { used.insert($0.url).inserted }
        relatedURLs = raw["related_urls"] as? [String] ?? []
        searchKey = ([title, description, bodyText.prefix(1200).description] + tags + Array(metadata.values)).joined(separator: " ").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    var coverURL: URL? {
        for candidate in [cover, thumbnail, gallery.first?.url] {
            if let s = candidate, s.hasPrefix("https://"), !s.contains("no_cover_image"),
               let address = URL(string: s) { return address }
        }
        return nil
    }
    var galleryImages: [CatalogAsset] {
        if !gallery.isEmpty { return gallery }
        if let cover, let asset = CatalogAsset(["url": cover]) { return [asset] }
        return []
    }
    var subtitle: String {
        if let opus { return "OPUS \(opus)" }
        if let year = metadata["Date Created"] { return year }
        return CatalogGroup.title(for: kind).uppercased()
    }
}

enum CatalogGroup {
    static let portfolio = ["artworks", "crease_patterns", "compositions", "published_instructions"]
    static let events = ["exhibitions", "lectures"]
    static let books = ["publications", "articles"]
    static let all = portfolio + events + books + ["artists"]
    static func title(for kind: String) -> String {
        ["artworks": "Artworks", "crease_patterns": "Crease Patterns",
         "compositions": "Compositions", "published_instructions": "Published Instructions",
         "exhibitions": "Exhibitions", "lectures": "Lectures & Workshops",
         "publications": "Books & Publications", "articles": "Articles & Posts",
         "artists": "Collaborators"][kind] ?? kind.capitalized
    }
    static func symbol(for kind: String) -> String {
        ["artworks": "square.grid.2x2", "crease_patterns": "square.on.square",
         "compositions": "circle.hexagongrid", "published_instructions": "text.book.closed",
         "exhibitions": "building.columns", "lectures": "person.2",
         "publications": "books.vertical", "articles": "doc.text", "artists": "person.crop.circle"][kind] ?? "square.grid.2x2"
    }
}

@MainActor final class CatalogStore: ObservableObject {
    @Published private(set) var collections: [String: [CatalogEntry]] = [:]
    @Published private(set) var issue: String?
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: String = ""
    private var byURL: [String: CatalogEntry] = [:]
    private let liveURL = URL(string: "https://raw.githubusercontent.com/airsoto/robert_lang_app/main/RobertLang/langorigami.json")!
    private let cacheFilename = "langorigami-v3-cache.json"

    var total: Int { collections.values.reduce(0) { $0 + $1.count } }
    func entries(_ kind: String) -> [CatalogEntry] { collections[kind] ?? [] }
    func entry(forURL url: String) -> CatalogEntry? { byURL[url] }

    func load() async {
        guard collections.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        if let bundled = Bundle.main.url(forResource: "langorigami", withExtension: "json"),
           let data = try? Data(contentsOf: bundled), decode(data) { return }
        if let cache = cacheURL, let data = try? Data(contentsOf: cache), decode(data) { return }
        issue = "The bundled catalog is missing. Add RobertLang/langorigami.json to the Xcode project."
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var request = URLRequest(url: liveURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 35
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            guard decode(data) else { throw NSError(domain: "Catalog", code: 1, userInfo: [NSLocalizedDescriptionKey: "The server returned an unsupported JSON format."]) }
            if let cache = cacheURL { try? data.write(to: cache, options: .atomic) }
        } catch {
            issue = "Update unavailable. Using the bundled catalog. \(error.localizedDescription)"
        }
    }

    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(cacheFilename)
    }

    @discardableResult private func decode(_ data: Data) -> Bool {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let groups = root["collections"] as? [String: [[String: Any]]] else { return false }
        var next: [String: [CatalogEntry]] = [:]
        for (kind, records) in groups { next[kind] = records.map { CatalogEntry($0, kind: kind) } }
        if let instructions = root["published_instructions"] as? [[String: Any]] {
            next["published_instructions"] = instructions.map { CatalogEntry($0, kind: "published_instructions") }
        }
        guard !next.isEmpty else { return false }
        collections = next
        byURL = Dictionary(uniqueKeysWithValues: next.values.flatMap { $0 }.filter { !$0.url.isEmpty }.map { ($0.url, $0) })
        lastUpdated = (root["generated_at"] as? String ?? "").components(separatedBy: "T").first ?? ""
        issue = nil
        return true
    }

    func search(_ text: String, kinds: [String] = CatalogGroup.all, tag: String? = nil) -> [CatalogEntry] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return kinds.flatMap { entries($0) }.filter { entry in
            (tag == nil || entry.tags.contains(tag!)) && (normalized.isEmpty || entry.searchKey.contains(normalized))
        }
    }
}

struct CatalogRootView: View {
    var body: some View {
        TabView {
            NavigationStack { CatalogHomeView() }.tabItem { Label("Explore", systemImage: "house") }
            NavigationStack { CatalogDirectoryView(title: "Portfolio", kinds: CatalogGroup.portfolio) }.tabItem { Label("Portfolio", systemImage: "square.grid.2x2") }
            NavigationStack { CatalogDirectoryView(title: "Events", kinds: CatalogGroup.events) }.tabItem { Label("Events", systemImage: "calendar") }
            NavigationStack { CatalogDirectoryView(title: "Library", kinds: CatalogGroup.books) }.tabItem { Label("Library", systemImage: "books.vertical") }
            NavigationStack { CatalogGlobalSearchView() }.tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .tint(Theme.gold)
    }
}

struct CatalogHomeView: View {
    @EnvironmentObject var store: CatalogStore
    private let highlights = ["artworks", "crease_patterns", "publications"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BrandHeader()
                Text("THE ART & SCIENCE OF FOLDING").font(.caption.weight(.medium)).tracking(2.5).foregroundStyle(Theme.gold)
                Text("The Origami of Robert J. Lang").font(.system(size: 32, weight: .light))
                Text("Artworks, crease patterns, compositions, books and scientific writing.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if store.isLoading { ProgressView("Loading catalog…") }
                if let issue = store.issue { Text(issue).font(.footnote).foregroundStyle(.orange) }
                HStack(spacing: 20) {
                    Label("\(store.total) records", systemImage: "square.stack")
                    if !store.lastUpdated.isEmpty { Label(store.lastUpdated, systemImage: "calendar") }
                }.font(.caption).foregroundStyle(.secondary)
                ForEach(highlights, id: \.self) { kind in
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink {
                            CatalogGridView(kind: kind)
                        } label: {
                            HStack {
                                Text(CatalogGroup.title(for: kind)).font(.title2.weight(.light))
                                Spacer()
                                Text("\(store.entries(kind).count)").font(.caption).foregroundStyle(Theme.gold)
                                Image(systemName: "chevron.right").font(.caption)
                            }
                        }.buttonStyle(.plain)
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 12) {
                                ForEach(Array(store.entries(kind).prefix(12))) { entry in
                                    NavigationLink { CatalogDetailView(entry: entry) } label: {
                                        CatalogCard(entry: entry).frame(width: 160)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.scrollIndicators(.hidden)
                    }
                }
                NavigationLink { CatalogAboutView() } label: { Label("About Robert J. Lang & App Updates", systemImage: "info.circle") }
                    .foregroundStyle(Theme.gold)
                CatalogCreditView()
            }.padding(18)
        }.background(.black).toolbar(.hidden, for: .navigationBar)
    }
}

struct CatalogDirectoryView: View {
    @EnvironmentObject var store: CatalogStore
    let title: String
    let kinds: [String]
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(kinds, id: \.self) { kind in
                    NavigationLink { CatalogGridView(kind: kind) } label: {
                        HStack(spacing: 15) {
                            Image(systemName: CatalogGroup.symbol(for: kind))
                                .font(.title2).foregroundStyle(Theme.gold).frame(width: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(CatalogGroup.title(for: kind)).font(.headline)
                                Text("\(store.entries(kind).count) entries").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                        }.padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            }.padding()
        }.navigationTitle(title).background(.black)
    }
}

struct CatalogGridView: View {
    @EnvironmentObject var store: CatalogStore
    let kind: String
    @State private var query = ""
    @State private var tag: String?
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    private var frequentTags: [String] {
        let counts = store.entries(kind).flatMap(\.tags).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(24).map { $0.key }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(store.search(query, kinds: [kind], tag: tag).count) results")
                    .font(.caption).foregroundStyle(.secondary)
                if !frequentTags.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            Button("All") { tag = nil }.buttonStyle(TagStyle(active: tag == nil))
                            ForEach(frequentTags, id: \.self) { option in
                                Button(option.replacingOccurrences(of: "-", with: " ").capitalized) {
                                    tag = tag == option ? nil : option
                                }.buttonStyle(TagStyle(active: tag == option))
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(store.search(query, kinds: [kind], tag: tag)) { entry in
                        NavigationLink { CatalogDetailView(entry: entry) } label: { CatalogCard(entry: entry) }
                            .buttonStyle(.plain)
                    }
                }
            }.padding()
        }.background(.black).navigationTitle(CatalogGroup.title(for: kind))
            .searchable(text: $query, prompt: "Search \(CatalogGroup.title(for: kind))")
    }
}

struct CatalogCard: View {
    let entry: CatalogEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                if let cover = entry.coverURL {
                    RemoteImage(url: cover).frame(height: 155).clipped()
                } else {
                    Image(systemName: CatalogGroup.symbol(for: entry.kind))
                        .font(.system(size: 36, weight: .ultraLight)).foregroundStyle(Theme.gold)
                }
            }.frame(height: 155).clipShape(RoundedRectangle(cornerRadius: 12))
            Text(entry.title).font(.subheadline.weight(.medium)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            Text(entry.subtitle).font(.system(size: 10, weight: .medium)).tracking(1).foregroundStyle(Theme.gold)
        }.foregroundStyle(.white)
    }
}

struct CatalogGlobalSearchView: View {
    @EnvironmentObject var store: CatalogStore
    @State private var query = ""
    @State private var selected = "all"
    private var kinds: [String] { selected == "all" ? CatalogGroup.all : [selected] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Category", selection: $selected) {
                    Text("All categories").tag("all")
                    ForEach(CatalogGroup.all, id: \.self) { kind in
                        Text(CatalogGroup.title(for: kind)).tag(kind)
                    }
                }.pickerStyle(.menu)
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("Search the catalog", systemImage: "magnifyingglass", description: Text("Search titles, opus numbers, materials, subjects and descriptions."))
                } else {
                    Text("\(store.search(query, kinds: kinds).count) matches").font(.caption).foregroundStyle(.secondary)
                    LazyVStack(spacing: 14) {
                        ForEach(store.search(query, kinds: kinds)) { entry in
                            NavigationLink { CatalogDetailView(entry: entry) } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Theme.surface
                                        if let url = entry.coverURL { RemoteImage(url: url) }
                                        else { Image(systemName: CatalogGroup.symbol(for: entry.kind)).foregroundStyle(Theme.gold) }
                                    }.frame(width: 82, height: 72).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title).font(.subheadline).lineLimit(2)
                                        Text(CatalogGroup.title(for: entry.kind)).font(.caption2).foregroundStyle(Theme.gold)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding()
        }.navigationTitle("Search").searchable(text: $query, prompt: "Title, opus, material, subject…").background(.black)
    }
}

struct CatalogDetailView: View {
    @EnvironmentObject var store: CatalogStore
    let entry: CatalogEntry
    @State private var openedURL: URL?
    @State private var selectedAsset: CatalogAsset?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let image = entry.galleryImages.first {
                    Button { selectedAsset = image } label: {
                        RemoteImage(url: image.imageURL).frame(height: 290).frame(maxWidth: .infinity)
                            .background(Theme.surface).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                } else if let cover = entry.coverURL {
                    RemoteImage(url: cover).frame(height: 260).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Text(entry.subtitle).font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.gold)
                Text(entry.title).font(.system(size: 31, weight: .light)).textSelection(.enabled)
                if !entry.tags.isEmpty { FlowTags(tags: entry.tags) }
                if !entry.description.isEmpty { Text(entry.description).font(.body) }
                if !entry.metadata.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Details").font(.title3)
                        ForEach(entry.metadata.keys.sorted(), id: \.self) { key in
                            HStack(alignment: .firstTextBaseline) {
                                Text(key).font(.caption).foregroundStyle(.secondary).frame(width: 112, alignment: .leading)
                                Text(entry.metadata[key] ?? "").font(.subheadline).textSelection(.enabled)
                            }
                        }
                    }.padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                if entry.galleryImages.count > 1 {
                    Text("Gallery · \(entry.galleryImages.count)").font(.title3)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 10) {
                            ForEach(entry.galleryImages) { asset in
                                Button { selectedAsset = asset } label: {
                                    RemoteImage(url: URL(string: asset.thumbnail))
                                        .frame(width: 154, height: 160).clipped().background(Theme.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                if !entry.bodyText.isEmpty {
                    Text("Description").font(.title3)
                    Text(entry.bodyText).font(.body).textSelection(.enabled)
                }
                if !entry.pdfs.isEmpty {
                    Text("Documents & crease patterns").font(.title3)
                    ForEach(entry.pdfs) { document in
                        Button { openedURL = URL(string: document.url) } label: {
                            Label(document.label.isEmpty ? "Open PDF" : document.label, systemImage: "doc.richtext")
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                let related = entry.links.filter { !$0.label.lowercased().hasPrefix("prev") && !$0.label.lowercased().hasPrefix("next") && $0.url != entry.url }
                if !related.isEmpty {
                    Text("Related work & references").font(.title3)
                    ForEach(Array(related.prefix(24))) { link in
                        if let record = store.entry(forURL: link.url) {
                            NavigationLink { CatalogDetailView(entry: record) } label: {
                                Label(link.label.isEmpty ? record.title : link.label, systemImage: "arrow.up.right")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if !link.url.contains("/wp-content/themes/") {
                            Button {
                                openedURL = URL(string: link.url)
                            } label: {
                                Label(link.label.isEmpty ? "Open reference" : link.label, systemImage: "link")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                if let url = URL(string: entry.url), !entry.url.isEmpty {
                    Button { openedURL = url } label: {
                        Label("View on langorigami.com", systemImage: "safari")
                    }.padding(.top, 6)
                }
                CatalogCreditView()
            }.tint(Theme.gold).padding(18)
        }.background(.black).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $openedURL) { url in
                if url.pathExtension.lowercased() == "pdf" { PDFReader(url: url) }
                else { SafariView(url: url) }
            }
            .sheet(item: $selectedAsset) { asset in CatalogFullImageView(asset: asset) }
    }
}

struct CatalogFullImageView: View {
    @Environment(\.dismiss) private var dismiss
    let asset: CatalogAsset
    @State private var scale: CGFloat = 1
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    RemoteImage(url: asset.imageURL)
                        .frame(width: geometry.size.width * scale, height: geometry.size.height * scale)
                        .gesture(MagnificationGesture().onChanged { scale = max(1, min($0, 5)) })
                }.background(.black)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Reset zoom") { scale = 1 } }
            }
        }
    }
}

struct CatalogAboutView: View {
    @EnvironmentObject var store: CatalogStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BrandHeader()
                Text("Robert J. Lang").font(.largeTitle.weight(.light))
                Text("Origami artist, physicist and mathematical origami pioneer.").foregroundStyle(.secondary)
                Link("About Robert J. Lang", destination: URL(string: "https://langorigami.com/about-robert-j-lang/")!)
                Link("Official website", destination: URL(string: "https://langorigami.com/")!)
                Link("Copyright information", destination: URL(string: "https://langorigami.com/copyright/")!)
                if !store.entries("artists").isEmpty {
                    NavigationLink { CatalogGridView(kind: "artists") } label: {
                        Label("Collaborators", systemImage: "person.2")
                    }
                }
                Button { Task { await store.refresh() } } label: {
                    Label(store.isLoading ? "Updating…" : "Check for catalog updates", systemImage: "arrow.clockwise")
                }.disabled(store.isLoading)
                if !store.lastUpdated.isEmpty { Text("Catalog snapshot: \(store.lastUpdated)").font(.caption).foregroundStyle(.secondary) }
                if let issue = store.issue { Text(issue).font(.footnote).foregroundStyle(.orange) }
                CatalogCreditView()
            }.tint(Theme.gold).padding()
        }.navigationTitle("About").background(.black)
    }
}

struct CatalogCreditView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("© Robert J. Lang. All artwork, photographs, texts and diagrams remain the property of their respective rights holders.")
            Text("iPhone app developed by Ángel Soto. Independent catalog viewer.")
            Link("Visit the official website", destination: URL(string: "https://langorigami.com/")!)
        }.font(.caption).foregroundStyle(.secondary).padding(.top, 16)
    }
}
