import Foundation

/// Minimal persistence abstraction so stores can be backed by `UserDefaults` in the app
/// and by memory in unit tests.
public protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

extension UserDefaults: KeyValueStore {
    public func set(_ data: Data?, forKey key: String) {
        if let data {
            set(data as Any, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}

public final class InMemoryKeyValueStore: KeyValueStore {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func data(forKey key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ data: Data?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }
}

extension KeyValueStore {
    func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Log.persistence.error("Failed to decode \(key): \(error.localizedDescription)")
            return nil
        }
    }

    func encode<T: Encodable>(_ value: T, forKey key: String) {
        do {
            set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            Log.persistence.error("Failed to encode \(key): \(error.localizedDescription)")
        }
    }
}
