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
