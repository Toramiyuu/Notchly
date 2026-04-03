import Foundation
import Combine

struct NewsItem: Identifiable {
    let id = UUID()
    let title: String
    let link: URL?
    let pubDate: Date?
    let source: String
}

struct NewsSource: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let feedURL: String

    static let presets: [NewsSource] = [
        NewsSource(id: "bbc",        name: "BBC News",      feedURL: "https://feeds.bbci.co.uk/news/rss.xml"),
        NewsSource(id: "hackernews", name: "Hacker News",   feedURL: "https://news.ycombinator.com/rss"),
        NewsSource(id: "theverge",   name: "The Verge",     feedURL: "https://www.theverge.com/rss/index.xml"),
        NewsSource(id: "techcrunch", name: "TechCrunch",    feedURL: "https://techcrunch.com/feed/"),
        NewsSource(id: "reuters",    name: "Reuters",       feedURL: "https://feeds.reuters.com/reuters/topNews"),
        NewsSource(id: "ars",        name: "Ars Technica",  feedURL: "https://feeds.arstechnica.com/arstechnica/index"),
    ]
}

class NewsSettings: ObservableObject {
    static let shared = NewsSettings()
    @Published var selectedSourceID: String {
        didSet { UserDefaults.standard.set(selectedSourceID, forKey: "news.sourceID") }
    }
    @Published var maxItems: Int {
        didSet { UserDefaults.standard.set(maxItems, forKey: "news.maxItems") }
    }

    var selectedSource: NewsSource {
        NewsSource.presets.first { $0.id == selectedSourceID } ?? NewsSource.presets[0]
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "news.sourceID") ?? ""
        selectedSourceID = NewsSource.presets.contains(where: { $0.id == saved }) ? saved : NewsSource.presets[0].id
        let savedMax = UserDefaults.standard.integer(forKey: "news.maxItems")
        maxItems = savedMax > 0 ? savedMax : 10
    }
}

class NewsManager: NSObject, ObservableObject, XMLParserDelegate {

    static let shared = NewsManager()

    @Published var items: [NewsItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var refreshTimer: Timer?
    private var parseItems: [NewsItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentPubDate = ""
    private var insideItem = false
    private var currentSource = ""

    private override init() {
        super.init()
        scheduleRefresh()
    }

    func fetch() {
        let source = NewsSettings.shared.selectedSource
        guard let url = URL(string: source.feedURL) else { return }
        currentSource = source.name
        isLoading = true
        errorMessage = nil

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async { self.isLoading = false }
            if let error {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                return
            }
            guard let data else { return }
            self.parseItems = []
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.parse()
        }.resume()
    }

    private func scheduleRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            self?.fetch()
        }
        fetch()
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" || elementName == "entry" {
            insideItem = true
            currentTitle = ""
            currentLink = ""
            currentPubDate = ""
        }
        // Atom <link> is self-closing with href attribute
        if elementName == "link", insideItem, let href = attributes["href"], !href.isEmpty {
            currentLink = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title":       currentTitle += string
        case "link":        currentLink += string
        case "pubDate", "published", "updated": currentPubDate += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName: String?) {
        if elementName == "item" || elementName == "entry" {
            insideItem = false
            let title = decodeHTMLEntities(currentTitle.trimmingCharacters(in: .whitespacesAndNewlines))
            let link  = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            let url = URL(string: link)
            let date = parseDate(currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))
            parseItems.append(NewsItem(title: title, link: url, pubDate: date, source: currentSource))
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        let maxItems = NewsSettings.shared.maxItems
        let result = Array(parseItems.prefix(maxItems))
        DispatchQueue.main.async { self.items = result }
    }

    /// Decodes HTML entities like &amp; &quot; &#39; &lt; &gt;
    private func decodeHTMLEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        // Use NSAttributedString's HTML parser — handles all named and numeric entities
        guard let data = string.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: NSUTF8StringEncoding],
                documentAttributes: nil
              ) else { return string }
        return attributed.string
    }

    private func parseDate(_ string: String) -> Date? {
        let formatters: [DateFormatter] = {
            let rfc822 = DateFormatter()
            rfc822.locale = Locale(identifier: "en_US_POSIX")
            rfc822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            let iso = DateFormatter()
            iso.locale = Locale(identifier: "en_US_POSIX")
            iso.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            return [rfc822, iso]
        }()
        for fmt in formatters {
            if let d = fmt.date(from: string) { return d }
        }
        return nil
    }
}
