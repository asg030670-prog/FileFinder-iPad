import Foundation

/// Small thread-safe LRU cache for search results.
///
/// Keys include the index generation, so results computed before the index changed are
/// never returned.
public final class SearchCache: @unchecked Sendable {
    public struct Key: Hashable, Sendable {
        public let query: SearchQuery
        public let generation: Int

        public init(query: SearchQuery, generation: Int) {
            self.query = query
            self.generation = generation
        }
    }

    private let lock = NSLock()
    private var storage: [Key: [SearchResult]] = [:]
    private var order: [Key] = []
    public let capacity: Int
    public private(set) var hits = 0
    public private(set) var misses = 0

    public init(capacity: Int = 50) {
        self.capacity = max(1, capacity)
    }

    public func results(for key: Key) -> [SearchResult]? {
        lock.lock(); defer { lock.unlock() }
        guard let value = storage[key] else {
            misses += 1
            return nil
        }
        hits += 1
        touch(key)
        return value
    }

    public func store(_ results: [SearchResult], for key: Key) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = results
        touch(key)
        while order.count > capacity {
            let evicted = order.removeFirst()
            storage.removeValue(forKey: evicted)
        }
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
        order.removeAll()
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return storage.count
    }

    private func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }
}
