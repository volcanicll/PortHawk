import SwiftUI

/// Process brand catalog: well-known dev-tool process names -> (label, brand
/// ink color). Adapted from Pulse's dev-tool brand table (recovered from binary
/// strings) to suit the ledger look: colors are darkened so they stay legible
/// on the off-white paper, and anything too pale gets deepened.
enum DevBrand {
    struct Brand {
        let label: String
        let color: Color
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    // Longer keys are matched first: pythonw before python, next-server before next.
    private static let table: [(key: String, brand: Brand)] = [
        // JS / Node ecosystem
        ("next-server", Brand(label: "Next.js", color: color(0x1F1F1F))),
        ("next", Brand(label: "Next.js", color: color(0x1F1F1F))),
        ("nuxt", Brand(label: "Nuxt", color: color(0x12A66F))),
        ("vite", Brand(label: "Vite", color: color(0x5B63D6))),
        ("webpack", Brand(label: "Webpack", color: color(0x4B93A8))),
        ("esbuild", Brand(label: "esbuild", color: color(0xB8912A))),
        ("rollup", Brand(label: "Rollup", color: color(0xC94F4F))),
        ("turbo", Brand(label: "Turborepo", color: color(0xB44A3A))),
        ("ts-node", Brand(label: "TypeScript", color: color(0x3178C6))),
        ("ts-node-dev", Brand(label: "TypeScript", color: color(0x3178C6))),
        ("tsx", Brand(label: "TypeScript", color: color(0x3178C6))),
        ("tsc", Brand(label: "TypeScript", color: color(0x3178C6))),
        ("pyright", Brand(label: "Pyright", color: color(0x3178C6))),
        ("basedpyright", Brand(label: "Pyright", color: color(0x3178C6))),
        ("node", Brand(label: "Node.js", color: color(0x4C8A45))),
        ("nodemon", Brand(label: "Node.js", color: color(0x4C8A45))),
        ("npm", Brand(label: "npm", color: color(0xB5382C))),
        ("pnpm", Brand(label: "pnpm", color: color(0xC8862A))),
        ("yarn", Brand(label: "Yarn", color: color(0x2C8EBB))),
        ("bun", Brand(label: "Bun", color: color(0xC99A5B))),
        ("deno", Brand(label: "Deno", color: color(0x22A06B))),

        // Python
        ("python3", Brand(label: "Python", color: color(0x3776AB))),
        ("python", Brand(label: "Python", color: color(0x3776AB))),
        ("pythonw", Brand(label: "Python", color: color(0x3776AB))),
        ("python3.", Brand(label: "Python", color: color(0x3776AB))),
        ("uvicorn", Brand(label: "Uvicorn", color: color(0x3776AB))),
        ("gunicorn", Brand(label: "Gunicorn", color: color(0x4A6C6F))),
        ("jupyter", Brand(label: "Jupyter", color: color(0xE87D1E))),
        ("pytest", Brand(label: "Pytest", color: color(0x0A9EDC))),

        // JVM / systems languages
        ("java", Brand(label: "Java", color: color(0x5382A1))),
        ("javac", Brand(label: "Java", color: color(0x5382A1))),
        ("gradle", Brand(label: "Gradle", color: color(0x02303A))),
        ("kotlin", Brand(label: "Kotlin", color: color(0x7F52FF))),
        ("maven", Brand(label: "Maven", color: color(0xC71A36))),

        // Go / Rust / others
        ("go", Brand(label: "Go", color: color(0x00ADD8))),
        ("gopls", Brand(label: "Go", color: color(0x00ADD8))),
        ("rustc", Brand(label: "Rust", color: color(0xB7410E))),
        ("rust-analyzer", Brand(label: "Rust", color: color(0xB7410E))),
        ("cargo", Brand(label: "Cargo", color: color(0x8A4A2B))),
        ("ruby", Brand(label: "Ruby", color: color(0xCC342D))),
        ("rails", Brand(label: "Rails", color: color(0xCE4B2B))),
        ("php", Brand(label: "PHP", color: color(0x777BB4))),
        ("php-fpm", Brand(label: "PHP", color: color(0x777BB4))),
        ("swift", Brand(label: "Swift", color: color(0xE0642F))),
        ("sourcekit-lsp", Brand(label: "Swift", color: color(0xE0642F))),
        ("dart", Brand(label: "Dart", color: color(0x0175C2))),
        ("flutter", Brand(label: "Flutter", color: color(0x02569B))),
        ("dotnet", Brand(label: ".NET", color: color(0x512BD4))),
        ("elixir", Brand(label: "Elixir", color: color(0x4B275F))),
        ("erlang", Brand(label: "Erlang", color: color(0xA90533))),
        ("haskell", Brand(label: "Haskell", color: color(0x5E5086))),
        ("lua", Brand(label: "Lua", color: color(0x2C2D72))),
        ("perl", Brand(label: "Perl", color: color(0x39457E))),
        ("Rscript", Brand(label: "R", color: color(0x276DC3))),
        ("julia", Brand(label: "Julia", color: color(0x9558B2))),

        // Databases / middleware
        ("redis-server", Brand(label: "Redis", color: color(0xC9382B))),
        ("redis-cli", Brand(label: "Redis", color: color(0xC9382B))),
        ("postgres", Brand(label: "PostgreSQL", color: color(0x336791))),
        ("postmaster", Brand(label: "PostgreSQL", color: color(0x336791))),
        ("mysql", Brand(label: "MySQL", color: color(0x4479A1))),
        ("mariadbd", Brand(label: "MariaDB", color: color(0x7A4E2E))),
        ("mongod", Brand(label: "MongoDB", color: color(0x47A248))),
        ("mongosh", Brand(label: "MongoDB", color: color(0x47A248))),
        ("mongo", Brand(label: "MongoDB", color: color(0x47A248))),
        ("sqlite3", Brand(label: "SQLite", color: color(0x0F5F82))),
        ("clickhouse", Brand(label: "ClickHouse", color: color(0xC79A00))),
        ("elasticsearch", Brand(label: "Elasticsearch", color: color(0x1BA9A0))),
        ("rabbitmq", Brand(label: "RabbitMQ", color: color(0xD96C1F))),

        // Services / infrastructure
        ("nginx", Brand(label: "NGINX", color: color(0x009639))),
        ("caddy", Brand(label: "Caddy", color: color(0x2E9E8F))),
        ("traefik", Brand(label: "Traefik", color: color(0x24A1C1))),
        ("consul", Brand(label: "Consul", color: color(0xD94654))),
        ("vault", Brand(label: "Vault", color: color(0xB8912A))),
        ("nomad", Brand(label: "Nomad", color: color(0x0BA57E))),
        ("prometheus", Brand(label: "Prometheus", color: color(0xE6522C))),
        ("grafana", Brand(label: "Grafana", color: color(0xE05E00))),
        ("kubectl", Brand(label: "Kubernetes", color: color(0x326CE5))),
        ("kubelet", Brand(label: "Kubernetes", color: color(0x326CE5))),
        ("helm", Brand(label: "Helm", color: color(0x2A3B8F))),
        ("docker", Brand(label: "Docker", color: color(0x1D7FD4))),
        ("dockerd", Brand(label: "Docker", color: color(0x1D7FD4))),
        ("containerd", Brand(label: "containerd", color: color(0x6E6E6E))),
        ("podman", Brand(label: "Podman", color: color(0x892CA0))),
        ("cloudflared", Brand(label: "Cloudflare", color: color(0xE0701B))),
        ("tailscaled", Brand(label: "Tailscale", color: color(0x4B70CC))),
        ("wireguard-go", Brand(label: "WireGuard", color: color(0x88171A))),
        ("openvpn", Brand(label: "OpenVPN", color: color(0x1E5A8A))),
        ("mihomo", Brand(label: "mihomo", color: color(0x2A6FB0))),
        ("rclone", Brand(label: "Rclone", color: color(0x2E6E8E))),

        // Editors / AI tools
        ("Code Helper", Brand(label: "VS Code", color: color(0x22A6F1))),
        ("Cursor", Brand(label: "Cursor", color: color(0x0175C2))),
        ("claude", Brand(label: "Claude", color: color(0xC96A4B))),
        ("gemini", Brand(label: "Gemini", color: color(0x8E75B2))),
        ("ollama", Brand(label: "Ollama", color: color(0xB8912A))),
        ("copilot", Brand(label: "Copilot", color: color(0x3E3E44))),

        // Browsers / system
        ("Google Chrome", Brand(label: "Chrome", color: color(0x4285F4))),
        ("Google Chrome for Testing", Brand(label: "Chrome for Testing", color: color(0x4285F4))),
        ("chromium", Brand(label: "Chromium", color: color(0x4285F4))),
        ("firefox", Brand(label: "Firefox", color: color(0xE05A2B))),
        ("adb", Brand(label: "Android", color: color(0x2FAC5E))),
        ("fastboot", Brand(label: "Android", color: color(0x2FAC5E))),
    ]

    /// Match a process name to a brand: exact match first, then the longest
    /// prefix match, case-insensitively.
    ///
    /// Memoized: the row body asks for this on every evaluation pass, and the
    /// same handful of process names repeat across hundreds of listeners — a
    /// lsof table of 300 Chrome/node helpers is still one table lookup.
    static func match(processName: String) -> Brand? {
        if let hit = cache[processName] { return hit }
        let result = lookup(processName)
        cache[processName] = result
        return result
    }

    private static func lookup(_ processName: String) -> Brand? {
        let name = processName.lowercased()
        guard !name.isEmpty else { return nil }
        if let exact = table.first(where: { $0.key == name }) {
            return exact.brand
        }
        return table
            .filter { name.hasPrefix($0.key.lowercased()) }
            .max { $0.key.count < $1.key.count }?
            .brand
    }

    /// Wrapped in a class so the mutable memo is safe to touch from the render
    /// path; `nil` results are stored as an explicit `.none` so unknown process
    /// names are not re-scanned either.
    private static let memo = Memo()
    private final class Memo {
        private let lock = NSLock()
        private var storage: [String: Brand?] = [:]
        subscript(_ key: String) -> Brand?? {
            get { lock.lock(); defer { lock.unlock() }; return storage[key] }
            set { lock.lock(); defer { lock.unlock() }; storage[key] = newValue }
        }
    }
    private static var cache: Memo { memo }
}
