import Foundation

public struct LibraryCategory: Identifiable, Sendable {
  public let id: String
  public let english: String
  public let portuguese: String
  public let group: String
}

public struct LibraryGroup: Identifiable, Sendable {
  public let id: String
  public let english: String
  public let portuguese: String
}

public struct LibraryProfile: Identifiable, Sendable {
  public let id: String
  public let english: String
  public let portuguese: String
  public let apps: [String]
}

/// Navigation metadata is independent of installation authority and app ownership.
public enum Library {
  public static func removableSelection(
    _ ids: Set<String>, catalog: [CatalogApp], installed: [InstalledApp], receipts: [String: String]
  ) -> Set<String> {
    // Migrate legacy catalog selections to exact installed paths; keep duplicate bundles separate.
    Set(
      ids.compactMap { id in
        if installed.contains(where: { $0.path == id && RemovalEngine.protection($0) == nil }) {
          return id
        }
        guard let catalogApp = catalog.first(where: { $0.id == id }), let path = receipts[id],
          installed.contains(where: { $0.path == path && $0.bundleID == catalogApp.bundleID })
        else { return nil }
        return path
      })
  }
  public static let groups: [LibraryGroup] = [
    .init(id: "everyday", english: "Everyday", portuguese: "Dia a dia"),
    .init(id: "create", english: "Create", portuguese: "Criar"),
    .init(id: "files", english: "Files & Storage", portuguese: "Ficheiros e armazenamento"),
    .init(id: "tools", english: "Mac & Tools", portuguese: "Mac e ferramentas"),
  ]
  public static let categories: [LibraryCategory] = [
    .init(id: "browsers", english: "Browsers", portuguese: "Navegadores", group: "everyday"),
    .init(
      id: "players", english: "Media Players", portuguese: "Leitores multimédia", group: "everyday"),
    .init(
      id: "notes", english: "Notes & Writing", portuguese: "Notas e escrita", group: "everyday"),
    .init(
      id: "office", english: "Office & Documents", portuguese: "Escritório e documentos",
      group: "everyday"),
    .init(
      id: "communication", english: "Communication", portuguese: "Comunicação", group: "everyday"),
    .init(
      id: "security", english: "Security & Privacy", portuguese: "Segurança e privacidade",
      group: "tools"),
    .init(id: "design", english: "3D & Design", portuguese: "3D e design", group: "create"),
    .init(id: "video", english: "Video & Motion", portuguese: "Vídeo e motion", group: "create"),
    .init(id: "audio", english: "Music & Audio", portuguese: "Música e áudio", group: "create"),
    .init(id: "archives", english: "Compression", portuguese: "Compressão", group: "files"),
    .init(
      id: "transfer", english: "File Transfer", portuguese: "Transferência de ficheiros",
      group: "files"),
    .init(id: "development", english: "Development", portuguese: "Programação", group: "tools"),
    .init(
      id: "productivity", english: "Mac Productivity", portuguese: "Produtividade no Mac",
      group: "tools"),
    .init(
      id: "documents", english: "PDF & Reading", portuguese: "PDF e leitura", group: "everyday"),
    .init(
      id: "mail", english: "Email & Calendars", portuguese: "Correio e calendários",
      group: "everyday"),
    .init(id: "photos", english: "Photography", portuguese: "Fotografia", group: "create"),
    .init(
      id: "cloud", english: "Cloud & Sync", portuguese: "Nuvem e sincronização", group: "files"),
    .init(
      id: "gaming", english: "Games & Launchers", portuguese: "Jogos e lançadores", group: "tools"),
    .init(
      id: "virtualization", english: "Virtual Machines", portuguese: "Máquinas virtuais",
      group: "tools"),
    .init(id: "terminals", english: "Terminals", portuguese: "Terminais", group: "tools"),
    .init(
      id: "git", english: "Git & Version Control", portuguese: "Git e controlo de versões",
      group: "tools"),
    .init(id: "databases", english: "Databases", portuguese: "Bases de dados", group: "tools"),
    .init(
      id: "ai", english: "AI & Local Models", portuguese: "IA e modelos locais", group: "tools"),
    .init(id: "network", english: "Network & VPN", portuguese: "Rede e VPN", group: "tools"),
    .init(
      id: "system", english: "System Utilities", portuguese: "Utilitários de sistema",
      group: "tools"),
  ]
  public static let profiles: [LibraryProfile] = [
    .init(
      id: "everyday", english: "Everyday", portuguese: "Dia a dia",
      apps: ["firefox", "iina", "rectangle", "localsend"]),
    .init(
      id: "create", english: "Creative studio", portuguese: "Estúdio criativo",
      apps: ["blender", "inkscape", "keka", "vlc"]),
    .init(
      id: "development", english: "Development", portuguese: "Programação",
      apps: ["visual-studio-code", "firefox", "rectangle", "keka"]),
    .init(
      id: "video", english: "Video & motion", portuguese: "Vídeo e motion",
      apps: ["iina", "blender", "final-cut-pro", "motion", "handbrake-app", "obs"]),
    .init(
      id: "music", english: "Music & audio", portuguese: "Música e áudio",
      apps: ["logic-pro", "audacity", "spotify", "keka"]),
    .init(
      id: "files", english: "Files between devices", portuguese: "Ficheiros entre dispositivos",
      apps: ["localsend", "keka"]),
    .init(
      id: "office", english: "Office & study", portuguese: "Trabalho e estudo",
      apps: ["libreoffice", "obsidian", "bitwarden", "localsend"]),
    .init(
      id: "communication", english: "Stay connected", portuguese: "Manter o contacto",
      apps: ["slack", "discord", "signal"]),
    .init(
      id: "writing", english: "Writing & research", portuguese: "Escrita e investigação",
      apps: ["obsidian", "bear", "skim", "calibre"]),
    .init(
      id: "photography", english: "Photography", portuguese: "Fotografia",
      apps: ["gimp", "affinity", "pixelmator-pro", "keka"]),
    .init(
      id: "podcast", english: "Podcast production", portuguese: "Produção de podcasts",
      apps: ["reaper", "audacity", "iina"]),
    .init(
      id: "streaming", english: "Streaming & recording", portuguese: "Transmissão e gravação",
      apps: ["obs", "discord", "handbrake-app", "vlc"]),
    .init(
      id: "web", english: "Web development", portuguese: "Programação Web",
      apps: ["visual-studio-code", "firefox", "github", "iterm2", "postman"]),
    .init(
      id: "ai", english: "Local AI", portuguese: "IA local",
      apps: ["ollama-app", "lm-studio", "zed"]),
    .init(
      id: "remote", english: "Remote collaboration", portuguese: "Colaboração à distância",
      apps: ["zoom", "slack", "notion", "dropbox"]),
    .init(
      id: "privacy", english: "Privacy & security", portuguese: "Privacidade e segurança",
      apps: ["brave-browser", "bitwarden", "signal", "cryptomator"]),
    .init(
      id: "gaming", english: "Mac gaming", portuguese: "Jogos no Mac",
      apps: ["steam", "heroic", "epic-games", "discord"]),
    .init(
      id: "productivity", english: "A focused Mac", portuguese: "Um Mac organizado",
      apps: ["raycast", "rectangle", "maccy", "jordanbaird-ice"]),
    .init(
      id: "cloud", english: "Cloud & backup", portuguese: "Nuvem e cópias",
      apps: ["syncthing-app", "cyberduck", "localsend", "keka"]),
    .init(
      id: "data", english: "Data & databases", portuguese: "Dados e bases de dados",
      apps: ["dbeaver-community", "tableplus", "microsoft-excel", "visual-studio-code"]),
  ]
  public static func matches(_ category: String, filter: String) -> Bool {
    filter == "all" || category == filter || categories.first { $0.id == category }?.group == filter
  }
  public static func selectable(_ ids: [String], catalog: [CatalogApp], installed: [InstalledApp])
    -> Set<String>
  {
    let installedIDs = Set(installed.map(\.bundleID))
    let requested = Set(ids)
    return Set(
      catalog.filter { requested.contains($0.id) && !installedIDs.contains($0.bundleID) }.map(\.id))
  }
}

public struct QueueSummary: Equatable {
  public let total: Int
  public let completed: Int
  public let verified: Int
  public let attention: Int
  public let guided: Int
  public init(_ entries: [QueueEntry]) {
    total = entries.count
    completed = entries.filter { $0.stage.terminal }.count
    verified = entries.filter { $0.stage == .succeeded }.count
    attention = entries.filter { [.failed, .interrupted].contains($0.stage) }.count
    guided = entries.filter { $0.stage == .guided }.count
  }
  public var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
}
