import Foundation

struct LinkItem: Identifiable, Hashable {
    var url: String
    var text: String
    var title: String
    var id: String { url }
    init(_ object: [String: Any]) {
        url = object["url"] as? String ?? ""
        let rawText = object["text"] as? String ?? ""
        let navEnd = "Contact | Search "
        let bodyText = rawText.components(separatedBy: navEnd).dropFirst().joined(separator: navEnd)
        text = (bodyText.isEmpty ? rawText : bodyText).components(separatedBy: "© 2004—2026").first ?? rawText
        title = object["title"] as? String ?? ""
    }
}

struct ImageItem: Identifiable {
    let urls: [String]
    let alt: String
    let caption: String
    var id: String { urls.first ?? UUID().uuidString }
    var bestURL: URL? { urls.filter { $0.contains("/uploads/") && !$0.contains("1x1.trans") }.reversed().compactMap(URL.init(string:)).first }
    init(_ object: [String: Any]) {
        urls = object["urls"] as? [String] ?? []
        alt = object["alt"] as? String ?? ""
        caption = object["caption"] as? String ?? ""
    }
}

struct OrigamiPage: Identifiable {
    let url: String
    let title: String
    let description: String
    let text: String
    let section: String
    let images: [ImageItem]
    let links: [LinkItem]
    let resources: [LinkItem]
    let headings: [String]
    let tags: [String]
    var id: String { url }
    var hero: URL? { images.compactMap(\.bestURL).first }
    init(_ object: [String: Any], fallbackURL: String) {
        url = object["url"] as? String ?? fallbackURL
        title = object["title"] as? String ?? "Untitled"
        description = object["description"] as? String ?? ""
        let rawText = object["text"] as? String ?? ""
        let navEnd = "Contact | Search "
        let bodyText = rawText.components(separatedBy: navEnd).dropFirst().joined(separator: navEnd)
        text = (bodyText.isEmpty ? rawText : bodyText).components(separatedBy: "© 2004—2026").first ?? rawText
        let path = URL(string: url)?.path ?? ""
        if path.hasPrefix("/artwork/") || path.hasPrefix("/composition/") || path.hasPrefix("/artworks/") || path.hasPrefix("/crease-patterns/") || path.hasPrefix("/crease-pattern/") || path.hasPrefix("/compositions/") || path.hasPrefix("/published-instructions/") { section = "portfolio" }
        else if path.hasPrefix("/event/") || path.hasPrefix("/events/") || path.hasPrefix("/exhibition/") || path.hasPrefix("/exhibitions/") || path.hasPrefix("/lectures-workshops/") || path.hasPrefix("/lecture/") { section = "events" }
        else if path.hasPrefix("/book/") || path.hasPrefix("/publication/") || path.hasPrefix("/publications/") || path.hasPrefix("/article/") || path.hasPrefix("/articles/") || path.hasPrefix("/books-articles/") || path.hasPrefix("/math-science-posts/") || path.hasPrefix("/other-posts/") { section = "books_articles" }
        else if path.hasPrefix("/about-robert-j-lang/") || path.hasPrefix("/collaborators/") || path.hasPrefix("/presses/") || path.hasPrefix("/faq/") || path.hasPrefix("/contact/") { section = "about" }
        else { section = object["section"] as? String ?? "other" }
        images = (object["images"] as? [[String:Any]] ?? []).map(ImageItem.init).filter { $0.bestURL != nil }
        links = (object["links"] as? [[String:Any]] ?? []).map(LinkItem.init)
        let direct = (object["resources"] as? [[String:Any]] ?? []).map(LinkItem.init)
        let files = links.filter { $0.url.lowercased().contains(".pdf") || $0.url.lowercased().contains(".zip") }
        resources = Array(Dictionary(grouping: direct + files, by: \.url).compactMap { $0.value.first }).sorted { $0.url < $1.url }
        headings = (object["headings"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
        // Tags in later crawler versions are supported; for the current schema use only explicit tag links.
        let explicit = object["tags"] as? [String] ?? []
        let tagLinks = links.filter { $0.url.contains("/tag/") || $0.url.contains("/category/") || ($0.url.contains("/artworks/") && $0.url != "https://langorigami.com/artworks/") }.map { $0.text.isEmpty ? (URL(string: $0.url)?.lastPathComponent ?? "") : $0.text }
        // Original website embeds tag names in the flattened page text: "Tags mammals animals subject Date Created".
        var textTags: [String] = []
        if let range = rawText.range(of: " Tags "), let end = rawText[range.upperBound...].range(of: " Date Created ") {
            textTags = rawText[range.upperBound..<end.lowerBound].split(separator: " ").map(String.init)
        }
        tags = Array(Set((explicit + tagLinks + textTags).filter { !$0.isEmpty })).sorted()
    }
}

@MainActor final class OrigamiLibrary: ObservableObject {
    @Published private(set) var pages: [OrigamiPage] = []
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    @Published var search = ""
    private let liveURL = URL(string: "https://raw.githubusercontent.com/airsoto/robert_lang_app/main/langorigami.json")!
    private let cacheName = "langorigami-cache.json"

    func load() async {
        loading = true
        defer { loading = false }
        // Load bundled data first so the app also works offline.
        if let bundled = Bundle.main.url(forResource: "langorigami", withExtension: "json"),
           let data = try? Data(contentsOf: bundled) { decode(data) }
        else if let cache = cacheURL, let data = try? Data(contentsOf: cache) { decode(data) }
        do {
            var req = URLRequest(url: liveURL)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            if decode(data), let cache = cacheURL { try? data.write(to: cache, options: .atomic) }
        } catch {
            if pages.isEmpty { self.error = "Add langorigami.json to the project or publish it in the GitHub repository. \(error.localizedDescription)" }
        }
    }

    @discardableResult private func decode(_ data: Data) -> Bool {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any],
              let raw = root["pages"] as? [String: [String:Any]] else { return false }
        pages = raw.map { OrigamiPage($0.value, fallbackURL: $0.key) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        error = nil
        return true
    }
    private var cacheURL: URL? { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(cacheName) }
    func section(_ name: String) -> [OrigamiPage] { pages.filter { $0.section == name } }
    var tags: [String] { Array(Set(pages.flatMap(\.tags))).sorted() }
    func page(for url: String) -> OrigamiPage? { pages.first { $0.url == url } }
    func results(text: String, section: String? = nil, tag: String? = nil) -> [OrigamiPage] {
        pages.filter { page in
            (section == nil || page.section == section) &&
            (tag == nil || page.tags.contains(tag!)) &&
            (text.isEmpty || [page.title, page.description, page.text, page.url, page.tags.joined(separator: " ")].joined(separator: " ").localizedStandardContains(text))
        }
    }
}
