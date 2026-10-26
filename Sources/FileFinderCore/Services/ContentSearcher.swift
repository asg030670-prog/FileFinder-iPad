import Foundation

/// Searches inside text-based files and extracts snippets/previews.
public struct ContentSearcher: Sendable {
    /// Files larger than this are not searched (keeps memory and IO bounded).
    public var maximumFileSize: Int64
    /// Number of bytes read from the beginning of the file.
    public var maximumBytesRead: Int
    /// Characters of context on each side of a match in snippets.
    public var snippetContext: Int

    public init(maximumFileSize: Int64 = 10_000_000, maximumBytesRead: Int = 1_000_000, snippetContext: Int = 40) {
        self.maximumFileSize = maximumFileSize
        self.maximumBytesRead = maximumBytesRead
        self.snippetContext = snippetContext
    }

    public func canSearch(_ item: FileItem) -> Bool {
        item.isTextReadable && item.size <= maximumFileSize
    }

    /// Reads up to `maximumBytesRead` bytes of text from the file.
    public func readText(at url: URL, maximumBytes: Int? = nil) throws -> String {
        let limit = maximumBytes ?? maximumBytesRead
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw FileFinderError.wrap(error, operation: "Read", path: url.path)
        }
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit) ?? Data()
        return ContentSearcher.decode(data)
    }

    /// Decodes data as UTF-8, falling back to other common encodings and finally to lossy UTF-8.
    static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        // A read limit may cut a multi-byte UTF-8 sequence; drop up to 3 trailing bytes and retry.
        for trim in 1...3 where data.count > trim {
            if let text = String(data: data.dropLast(trim), encoding: .utf8) { return text }
        }
        if let text = String(data: data, encoding: .utf16), data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    /// Returns a snippet around the first location where all `terms` appear, or `nil` if a term is missing.
    public func match(terms: [String], in item: FileItem) -> String? {
        guard !terms.isEmpty, canSearch(item) else { return nil }
        let text: String
        do {
            text = try readText(at: item.url)
        } catch {
            Log.search.debug("Content search skipped for \(item.name): \(error.localizedDescription)")
            return nil
        }
        return snippet(for: terms, in: text)
    }

    /// Returns a snippet around the first term if every term is contained in `text`.
    public func snippet(for terms: [String], in text: String) -> String? {
        guard let firstTerm = terms.first else { return nil }
        for term in terms.dropFirst() where text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
            return nil
        }
        guard let range = text.range(of: firstTerm, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }

        var start = text.index(range.lowerBound, offsetBy: -snippetContext, limitedBy: text.startIndex) ?? text.startIndex
        var end = text.index(range.upperBound, offsetBy: snippetContext, limitedBy: text.endIndex) ?? text.endIndex
        // Extend to word boundaries (by at most 15 characters) so words are not cut in half.
        var extra = 0
        while start > text.startIndex, extra < 15, !text[text.index(before: start)].isWhitespace {
            start = text.index(before: start)
            extra += 1
        }
        extra = 0
        while end < text.endIndex, extra < 15, !text[end].isWhitespace {
            end = text.index(after: end)
            extra += 1
        }
        var snippet = String(text[start..<end])
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if start > text.startIndex { snippet = "…" + snippet }
        if end < text.endIndex { snippet += "…" }
        return snippet
    }
}
