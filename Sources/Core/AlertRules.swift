import Foundation

/// Pure snapshot-diff rules, kept free of UI and I/O so they can be exercised
/// directly by the `--selftest` suite.
enum AlertRules {
    /// Ports that just became occupied by a process, among the favorites.
    ///
    /// `previousOccupied` and `currentOccupied` are the full sets of occupied
    /// ports for the two snapshots — deliberately not pre-filtered to favorites.
    /// Filtering inside the caller is what made the alert unreachable: with only
    /// favorite ports retained, every remembered entry was occupied by
    /// construction, so the "was idle, now busy" transition could never fire.
    ///
    /// `hasBaseline` is false for the very first snapshot after launch. There is
    /// no earlier state to compare against, so nothing is reported: otherwise
    /// every already-occupied favorite would light the alert dot on startup, and
    /// the app would be claiming a port was "just taken" when it cannot know.
    static func newlyOccupiedFavorites(
        favorites: Set<Int>,
        previousOccupied: Set<Int>,
        currentOccupied: Set<Int>,
        hasBaseline: Bool = true
    ) -> Set<Int> {
        guard hasBaseline, !favorites.isEmpty else { return [] }
        let nowBusy = currentOccupied.intersection(favorites)
        let wasBusy = previousOccupied.intersection(favorites)
        return nowBusy.subtracting(wasBusy)
    }

    /// Group names are persisted, so a renamed group would otherwise lose its
    /// collapsed state on upgrade. Maps the former localized names (escaped so
    /// the source stays ASCII) onto the current ones; unknown names — real
    /// project names — pass through untouched.
    static func migrateGroupName(_ name: String) -> String {
        switch name {
        case "\u{7CFB}\u{7EDF}\u{4E0E}\u{5176}\u{4ED6}": return systemGroupName
        case "\u{6536}\u{85CF}": return favoritesGroupName
        default: return name
        }
    }

    /// Group name used for entries without an inferred project.
    static let systemGroupName = "System & Other"
    /// Group name holding favorited ports.
    static let favoritesGroupName = "Favorites"
}
