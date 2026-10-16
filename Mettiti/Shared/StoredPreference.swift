import Foundation

/// One setting persisted under a `UserDefaults` key.
/// String-backed enums are stored as their raw value; anything else Codable is stored as JSON data.
struct StoredPreference<Value> {
    private let read: () -> Value?
    private let write: (Value) -> Void

    /// The stored value, or nil when nothing (or nothing readable) is stored.
    func load() -> Value? { read() }

    func save(_ value: Value) { write(value) }
}

extension StoredPreference where Value: RawRepresentable, Value.RawValue == String {
    static func rawValue(_ key: String, in defaults: UserDefaults) -> Self {
        Self(
            read: { defaults.string(forKey: key).flatMap(Value.init(rawValue:)) },
            write: { defaults.set($0.rawValue, forKey: key) }
        )
    }
}

extension StoredPreference where Value: Codable {
    static func json(_ key: String, in defaults: UserDefaults) -> Self {
        Self(
            read: { defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Value.self, from: $0) } },
            write: { value in
                guard let data = try? JSONEncoder().encode(value) else { return }
                defaults.set(data, forKey: key)
            }
        )
    }
}
