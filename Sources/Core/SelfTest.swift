import Foundation

/// Assertion suite for the pure data-layer rules, run with `--selftest`.
///
/// These are the rules that are easy to get subtly wrong and impossible to
/// notice by looking at the UI: lsof column location, dual-stack dedup,
/// exposure classification and the favorite-alert transition. Wire this into
/// CI so a regression fails the build instead of shipping.
enum SelfTest {
    private static var passed = 0
    private static var failures: [String] = []

    static func run() {
        parseColumnLocation()
        unescapeEscapedNames()
        dedupPrefersExposed()
        dedupKeepsDistinctPIDs()
        exposureClassification()
        browseTarget()
        favoriteAlertTransition()
        groupNameMigration()
        projectPathFiltering()
        projectNameExtraction()

        print("")
        if failures.isEmpty {
            print("\(passed) checks passed")
            exit(0)
        }
        print("\(failures.count) of \(passed + failures.count) checks FAILED:")
        for failure in failures { print("  ✗ \(failure)") }
        exit(1)
    }

    // MARK: - Assertions

    private static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passed += 1
        } else {
            failures.append(label)
        }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
        if actual == expected {
            passed += 1
        } else {
            failures.append("\(label): got \(actual), expected \(expected)")
        }
    }

    // MARK: - lsof parsing

    private static let header = "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME"

    private static func parseLine(_ line: String) -> PortEntry? {
        PortScanner.parse(line)
    }

    /// A command name containing spaces shifts every column; the parser must
    /// still find the PID by looking for "digits + letter-suffixed FD".
    private static func parseColumnLocation() {
        let entry = parseLine("Google Chrome 1718 volcanic 125u IPv4 0x62b68985e2987328 0t0 TCP 127.0.0.1:9222 (LISTEN)")
        expectEqual(entry?.port, 9222, "port after a spaced command name")
        expectEqual(entry?.pid, 1718, "pid after a spaced command name")
        expectEqual(entry?.processName, "Google Chrome", "spaced command name is preserved")
        expectEqual(entry?.isLanExposed, false, "127.0.0.1 is not exposed")

        let wildcard = parseLine("rapportd 637 volcanic 8u IPv4 0xaa45075e3007ba7f 0t0 TCP *:49157 (LISTEN)")
        expectEqual(wildcard?.port, 49157, "wildcard port parsed")
        expectEqual(wildcard?.isLanExposed, true, "* is exposed")

        expect(parseLine("garbage line") == nil, "short line is rejected")
        expect(parseLine(header) == nil, "header row is rejected")
    }

    private static func unescapeEscapedNames() {
        expectEqual(PortScanner.unescape("Google\\x20Chrome"), "Google Chrome", "\\x20 unescaped to a space")
        expectEqual(PortScanner.unescape("Code\\x20Helper\\x20(Plugin)"), "Code Helper (Plugin)", "multiple escapes")
        expectEqual(PortScanner.unescape("node"), "node", "plain name untouched")
        // A backslash that does not begin a known escape must survive with its
        // following character; consuming it silently truncated names.
        expectEqual(PortScanner.unescape("back\\slash"), "back\\slash", "an unknown escape keeps both characters")
        expectEqual(PortScanner.unescape("trailing\\"), "trailing\\", "a trailing backslash survives")
        expectEqual(PortScanner.unescape("a\\\\b"), "a\\b", "a doubled backslash collapses to one")
        expectEqual(PortScanner.unescape("\\xZZ"), "\\xZZ", "a malformed hex escape is left alone")
        expectEqual(PortScanner.unescape("\\x2"), "\\x2", "a truncated hex escape is left alone")
    }

    // MARK: - Dual-stack dedup

    /// The regression that mattered: one process listening on both 127.0.0.1
    /// and * for the same port. Whichever row lsof prints first must not decide
    /// the exposure verdict.
    private static func dedupPrefersExposed() {
        let loopbackFirst = """
        \(header)
        Python 55769 volcanic 3u IPv4 0xb8d0246d523a7084 0t0 TCP 127.0.0.1:34567 (LISTEN)
        Python 55769 volcanic 4u IPv4 0x7ca009afaec878b5 0t0 TCP *:34567 (LISTEN)
        """
        let entries = PortScanner.parseAll(loopbackFirst)
        expectEqual(entries.count, 1, "dual-stack collapses to one row")
        expectEqual(entries.first?.isLanExposed, true, "loopback-first ordering still reports LAN exposure")

        let wildcardFirst = """
        \(header)
        Python 55769 volcanic 4u IPv4 0x7ca009afaec878b5 0t0 TCP *:34567 (LISTEN)
        Python 55769 volcanic 3u IPv4 0xb8d0246d523a7084 0t0 TCP 127.0.0.1:34567 (LISTEN)
        """
        let reversed = PortScanner.parseAll(wildcardFirst)
        expectEqual(reversed.count, 1, "reverse ordering collapses too")
        expectEqual(reversed.first?.isLanExposed, true, "wildcard-first ordering reports LAN exposure")

        // Loopback-only on both stacks stays unexposed.
        let bothLoopback = """
        \(header)
        node 900 501 20u IPv4 0x1 0t0 TCP 127.0.0.1:3000 (LISTEN)
        node 900 501 21u IPv6 0x2 0t0 TCP [::1]:3000 (LISTEN)
        """
        let loopback = PortScanner.parseAll(bothLoopback)
        expectEqual(loopback.count, 1, "IPv4/IPv6 loopback collapses to one row")
        expectEqual(loopback.first?.isLanExposed, false, "loopback-only stays local")
    }

    /// Different PIDs on the same port are genuinely separate listeners.
    private static func dedupKeepsDistinctPIDs() {
        let input = """
        \(header)
        node 900 501 20u IPv4 0x1 0t0 TCP 127.0.0.1:3000 (LISTEN)
        node 901 501 20u IPv4 0x2 0t0 TCP 127.0.0.1:3000 (LISTEN)
        """
        expectEqual(PortScanner.parseAll(input).count, 2, "same port, different PIDs stay separate")
    }

    // MARK: - Exposure classification

    private static func exposureClassification() {
        expectEqual(PortScanner.isExposed(host: "*"), true, "* is exposed")
        expectEqual(PortScanner.isExposed(host: "0.0.0.0"), true, "0.0.0.0 is exposed")
        expectEqual(PortScanner.isExposed(host: "[::]"), true, "[::] is exposed")
        expectEqual(PortScanner.isExposed(host: "::"), true, ":: is exposed")
        expectEqual(PortScanner.isExposed(host: "127.0.0.1"), false, "127.0.0.1 is local")
        expectEqual(PortScanner.isExposed(host: "127.0.0.53"), false, "any 127.x is local")
        expectEqual(PortScanner.isExposed(host: "[::1]"), false, "[::1] is local")
        expectEqual(PortScanner.isExposed(host: "localhost"), false, "localhost is local")
        // A specific interface address is reachable from the LAN; whitelisting
        // only the wildcard forms used to mislabel this as local.
        expectEqual(PortScanner.isExposed(host: "192.168.1.5"), true, "a specific LAN address is exposed")
        expectEqual(PortScanner.isExposed(host: "10.0.0.7"), true, "a private LAN address is exposed")
    }

    // MARK: - Browser target

    private static func entry(port: Int, pid: pid_t = 100, host: String) -> PortEntry {
        PortEntry(port: port, pid: pid, processName: "node", host: host,
                  project: nil, projectPath: nil)
    }

    /// The URL handed to the browser has to be reachable from this machine. A
    /// wildcard bind is also on loopback; an interface-bound listener is only
    /// there, and an IPv6 literal must keep its brackets or the URL is invalid.
    private static func browseTarget() {
        expectEqual(entry(port: 8899, host: "127.0.0.1").browseURL?.absoluteString,
                    "http://127.0.0.1:8899/", "loopback listener opens on 127.0.0.1")
        expectEqual(entry(port: 8899, host: "*").browseURL?.absoluteString,
                    "http://127.0.0.1:8899/", "wildcard listener opens on loopback, which always works")
        expectEqual(entry(port: 8899, host: "0.0.0.0").browseURL?.absoluteString,
                    "http://127.0.0.1:8899/", "0.0.0.0 listener opens on loopback")
        expectEqual(entry(port: 8899, host: "[::]").browseURL?.absoluteString,
                    "http://127.0.0.1:8899/", "IPv6 wildcard opens on loopback")
        expectEqual(entry(port: 8899, host: "192.168.1.5").browseURL?.absoluteString,
                    "http://192.168.1.5:8899/", "interface-bound listener opens on that address")
        expectEqual(entry(port: 8899, host: "[::1]").browseURL?.absoluteString,
                    "http://[::1]:8899/", "IPv6 loopback keeps its brackets")
        expectEqual(entry(port: 8899, host: "fe80::1").browseURL?.absoluteString,
                    "http://[fe80::1]:8899/", "a bare IPv6 literal gets brackets")
        expectEqual(entry(port: 443, host: "127.0.0.1").browseURL?.absoluteString,
                    "https://127.0.0.1:443/", "443 opens over https")
        expectEqual(entry(port: 8443, host: "127.0.0.1").browseURL?.absoluteString,
                    "https://127.0.0.1:8443/", "8443 opens over https")
        expectEqual(entry(port: 3000, host: "127.0.0.1").browseURL?.absoluteString,
                    "http://127.0.0.1:3000/", "a dev port opens over http")
        // A favorite placeholder has no process, so there is nothing to open.
        expect(entry(port: 4747, pid: 0, host: "127.0.0.1").browseURL == nil,
               "a favorite placeholder has no browser target")
    }

    // MARK: - Favorite alert transition

    /// The shipped bug: `busyNow` was filtered to favorites before being stored
    /// as the previous snapshot, so `!wasBusy` was never true and the alert
    /// could not fire at all.
    private static func favoriteAlertTransition() {
        let favorites: Set<Int> = [3000]

        // Idle -> occupied must alert.
        expectEqual(
            AlertRules.newlyOccupiedFavorites(favorites: favorites, previousOccupied: [], currentOccupied: [3000]),
            [3000],
            "idle favorite becoming occupied alerts"
        )
        // Occupied -> still occupied must not re-alert.
        expectEqual(
            AlertRules.newlyOccupiedFavorites(favorites: favorites, previousOccupied: [3000], currentOccupied: [3000]),
            [],
            "staying occupied does not re-alert"
        )
        // Released -> occupied again alerts anew.
        expectEqual(
            AlertRules.newlyOccupiedFavorites(favorites: favorites, previousOccupied: [], currentOccupied: [3000]),
            [3000],
            "re-occupation after release alerts again"
        )
        // Non-favorited ports never alert.
        expectEqual(
            AlertRules.newlyOccupiedFavorites(favorites: favorites, previousOccupied: [], currentOccupied: [8080]),
            [],
            "non-favorited ports do not alert"
        )
        // With no favorites there is nothing to alert about.
        expectEqual(
            AlertRules.newlyOccupiedFavorites(favorites: [], previousOccupied: [], currentOccupied: [3000]),
            [],
            "no favorites means no alerts"
        )
        // Only the newly taken favorite is reported, not the one already busy.
        expectEqual(
            AlertRules.newlyOccupiedFavorites(
                favorites: [3000, 5173, 8080],
                previousOccupied: [8080, 1234],
                currentOccupied: [8080, 5173, 1234]
            ),
            [5173],
            "only the newly occupied favorite is reported"
        )
        // The first snapshot after launch has nothing to compare against, so an
        // already-occupied favorite must not be reported as "just taken".
        expectEqual(
            AlertRules.newlyOccupiedFavorites(
                favorites: [3000], previousOccupied: [], currentOccupied: [3000], hasBaseline: false
            ),
            [],
            "the first snapshot does not alert on already-occupied favorites"
        )
        expectEqual(
            AlertRules.newlyOccupiedFavorites(
                favorites: [3000], previousOccupied: [], currentOccupied: [3000], hasBaseline: true
            ),
            [3000],
            "with a baseline, the same transition does alert"
        )
    }

    // MARK: - Group name migration

    /// Collapsed group names are persisted, so the rename to English must carry
    /// the old values over or a user's collapsed groups spring back open.
    private static func groupNameMigration() {
        expectEqual(
            AlertRules.migrateGroupName("\u{7CFB}\u{7EDF}\u{4E0E}\u{5176}\u{4ED6}"),
            AlertRules.systemGroupName,
            "the former system group name migrates"
        )
        expectEqual(
            AlertRules.migrateGroupName("\u{6536}\u{85CF}"),
            AlertRules.favoritesGroupName,
            "the former favorites group name migrates"
        )
        expectEqual(
            AlertRules.migrateGroupName("my-project"),
            "my-project",
            "a real project name passes through unchanged"
        )
    }

    // MARK: - Project inference

    private static func projectPathFiltering() {
        expectEqual(PortScanner.isProjectPath("/Users/someone/code/my-app"), true, "a workspace directory is a project")
        expectEqual(PortScanner.isProjectPath("/System/Library/CoreServices"), false, "/System is not a project")
        expectEqual(PortScanner.isProjectPath("/usr/sbin"), false, "/usr is not a project")
        expectEqual(PortScanner.isProjectPath("/private/var/db"), false, "/private/var is not a project")
        expectEqual(PortScanner.isProjectPath("/Library/Apple"), false, "/Library is not a project")
        expectEqual(PortScanner.isProjectPath("/Applications"), false, "/Applications is not a project")
        expectEqual(PortScanner.isProjectPath("/"), false, "the root directory is not a project")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        expectEqual(PortScanner.isProjectPath(home), false, "the home directory itself is not a project")
    }

    private static func projectNameExtraction() {
        expectEqual(PortScanner.projectName("/Users/someone/code/my-app"), "my-app", "basename is the project name")
        expectEqual(PortScanner.projectName("/tmp/"), "tmp", "trailing slash handled")
        expectEqual(PortScanner.projectName(""), nil, "empty path yields nil")
    }
}
