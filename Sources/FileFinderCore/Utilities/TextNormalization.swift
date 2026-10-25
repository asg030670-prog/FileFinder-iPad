import Foundation

extension String {
    /// Lower-cased, diacritic-insensitive representation used for matching
    /// (so that "cancion" matches "Canción.mp3").
    public var searchNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
    }
}
