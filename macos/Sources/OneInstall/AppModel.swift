import AppKit
import OneInstallCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class AppModel: ObservableObject {
  @Published var apps: [CatalogApp] = []
  @Published var inventory = InventoryResult()
  @Published var scanning = false
  @Published var page = "install"
  @Published var search = ""
  @Published var category = "all"
  @Published var installedOnly = false
  @Published var state = SavedState()
  @Published var busy = false
  @Published var stopRequested = false
  @Published var status = ""
  @Published var logText = ""
  @Published var successPulse = false
  @Published var theme: String { didSet { preference("theme", theme) } }
  @Published var accent: Bool { didSet { preference("accent", accent) } }
  @Published var language: String { didSet { preference("language", language) } }
  @Published var lessMotion: Bool { didSet { preference("lessMotion", lessMotion) } }
  @Published var detailApp: CatalogApp?
  @Published var installedDetail: InstalledApp?
  @Published var profilePicker = false
  @Published var expandedGroups: Set<String> = []
  @Published var selectionEvent: SelectionEvent?
  @Published var displayAccessibilityRevision = 0
  private var accessibilityObserver: NSObjectProtocol?
  private var inventoryRefreshedAt: Date?
  private var pageFilters: [String: (String, String, Bool)] = [:]
  @Published var review = false
  private var removalReviewID = UUID()
  @Published var preparingRemoval = false
  @Published var removalPlans: [RemovalPlan] = []
  @Published var removalIssues: [String: String] = [:]
  @Published var caskOwners: [String: Set<String>] = [:]
  @Published var leftoverApp: RemovalIdentity?
  @Published var leftoverReport = LeftoverReport()
  @Published var leftoverScanning = false
  @Published var leftoverSelection: Set<String> = []
  @Published var leftoverResult = ""
  @Published var cleanupConfirm = false
  var persistenceBlocked = false
  let capture: Bool
  let storage: URL
  let brew = BrewEngine()
  var stateURL: URL { storage.appendingPathComponent("state.json") }
  var logURL: URL { storage.appendingPathComponent("operations.log") }
  var pt: Bool { language == "pt-PT" }
  func t(_ en: String, _ pt: String) -> String { self.pt ? pt : en }
  var reduced: Bool { lessMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  init(capture: Bool = false) {
    self.capture = capture
    storage = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/1nstall-mac-preview")
    let d = UserDefaults.standard
    theme = capture ? "dark" : (d.string(forKey: "theme") ?? "system")
    accent = capture ? true : (d.object(forKey: "accent") as? Bool ?? true)
    language = capture ? "en" : (d.string(forKey: "language") ?? "pt-PT")
    lessMotion = capture ? true : d.bool(forKey: "lessMotion")
    do { apps = try Catalog.load() } catch { status = "Catalog: \(error.localizedDescription)" }
    if !capture, FileManager.default.fileExists(atPath: stateURL.path) {
      do { state = try Persistence.read(stateURL) } catch {
        let backup = storage.appendingPathComponent("state-unreadable-\(UUID().uuidString).json")
        do { try FileManager.default.copyItem(at: stateURL, to: backup) } catch {
          persistenceBlocked = true
        }
        status = t(
          "Saved state could not be read. The original was preserved.",
          "Não foi possível ler o estado guardado. O original foi preservado.")
      }
    }
    if capture { state.installSelection = ["rectangle"] }
    accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.displayAccessibilityRevision += 1
        if self?.reduced == true {
          self?.successPulse = false
          self?.selectionEvent = nil
        }
      }
    }
  }
  func preference(_ key: String, _ value: Any) {
    if !capture { UserDefaults.standard.set(value, forKey: key) }
    if key == "language" {
      NotificationCenter.default.post(name: Notification.Name("1nstall.language"), object: nil)
    }
  }
  func save() {
    guard !capture, !persistenceBlocked else { return }
    do { try Persistence.save(state, to: stateURL) } catch {
      status = t("Unable to save results.", "Não foi possível guardar os resultados.")
    }
  }
  func appendLog(_ text: String) {
    logText += text
    if logText.count > 30_000 { logText = String(logText.suffix(30_000)) }
    guard !capture else { return }
    do {
      try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
      if !FileManager.default.fileExists(atPath: logURL.path) {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
      }
      let handle = try FileHandle(forWritingTo: logURL)
      try handle.seekToEnd()
      try handle.write(contentsOf: Data(text.utf8))
      try handle.close()
    } catch {
      status = t(
        "Unable to save the operation log.", "Não foi possível guardar o registo da operação.")
    }
  }
  // Page navigation uses the current snapshot immediately. Explicit refresh and
  // operation verification still scan unconditionally; returning after 30s refreshes.
  func refreshIfStale() {
    guard !capture, inventoryRefreshedAt.map({ Date().timeIntervalSince($0) < 30 }) != true else {
      return
    }
    refresh()
  }
  func refresh() {
    guard !scanning else { return }
    scanning = true
    Task {
      let result = await Task.detached(priority: .utility) { Inventory.scan() }.value
      inventory = result
      caskOwners = await Task.detached(priority: .utility) { CaskIndex().owners }.value
      inventoryRefreshedAt = Date()
      scanning = false
      if result.warnings.isEmpty && !busy {
        state.installSelection = Library.selectable(
          Array(state.installSelection), catalog: apps, installed: result.apps)
        state.removalSelection = Library.removableSelection(
          state.removalSelection, catalog: apps, installed: result.apps, receipts: state.receipts)
        save()
      }
      if !result.warnings.isEmpty {
        status = t(
          "Inventory is partial. See diagnostics.",
          "O inventário está incompleto. Consulta o diagnóstico.")
      }
    }
  }
  func installed(_ app: CatalogApp) -> Bool {
    inventory.apps.contains { $0.bundleID == app.bundleID }
  }
  var selection: Set<String> {
    page == "uninstall" ? state.removalSelection : state.installSelection
  }
  func installed(_ identity: RemovalIdentity) -> Bool {
    inventory.apps.contains { $0.bundleID == identity.bundleID || $0.path == identity.app.path }
  }
  var selectedInstalledApps: [InstalledApp] {
    inventory.apps.filter { state.removalSelection.contains($0.path) }
  }
  var selectedApps: [CatalogApp] {
    page == "uninstall"
      ? selectedInstalledApps.map(presentationApp) : apps.filter { selection.contains($0.id) }
  }
  // Visual selection tokens carry the exact installed path; they are never installation catalog entries.
  func presentationApp(_ app: InstalledApp) -> CatalogApp {
    CatalogApp(
      id: app.path, name: app.name,
      category: apps.first { $0.bundleID == app.bundleID }?.category ?? "all",
      summaryEN: "", summaryPT: "", bundleID: app.bundleID,
      appName: URL(fileURLWithPath: app.path).lastPathComponent, website: "", source: "installed",
      version: app.version, minimumOS: "", architecture: "", sha256: nil, verified: "",
      supportNames: [])
  }
  func removalName(_ app: InstalledApp) -> String {
    if let reason = RemovalEngine.protection(app) {
      return reason == "self"
        ? t("1nstall is running", "A 1nstall está em execução")
        : t("Protected by macOS", "Protegida pelo macOS")
    }
    if caskOwners[app.path]?.isEmpty == false {
      return "Homebrew · " + t("uninstall", "desinstalação")
    }
    return app.store
      ? t("App Store · move to Trash", "App Store · mover para o Lixo")
      : t("App · move to Trash", "App · mover para o Lixo")
  }
  func toggleRemoval(_ app: InstalledApp) {
    guard RemovalEngine.protection(app) == nil else {
      installedDetail = app
      return
    }
    toggle(presentationApp(app))
  }
  func identity(for entry: QueueEntry) -> RemovalIdentity? {
    entry.removedApp ?? apps.first { $0.id == entry.appID }.map(RemovalIdentity.init(catalog:))
  }
  func toggle(_ app: CatalogApp) {
    guard !busy else { return }
    if page == "uninstall" {
      if !state.removalSelection.insert(app.id).inserted { state.removalSelection.remove(app.id) }
    } else {
      if installed(app) && !state.installSelection.contains(app.id) { return }
      if !state.installSelection.insert(app.id).inserted { state.installSelection.remove(app.id) }
    }
    selectionEvent = SelectionEvent(app: app, adding: selection.contains(app.id))
    status = t(
      "Selection updated. Review before continuing.", "Seleção atualizada. Revê antes de continuar."
    )
    save()
  }
  func clear() {
    guard !busy else { return }
    if page == "uninstall" { state.removalSelection = [] } else { state.installSelection = [] }
    save()
  }
  func profile(_ ids: [String]) {
    guard !busy else { return }
    state.installSelection = Library.selectable(ids, catalog: apps, installed: inventory.apps)
    save()
  }
  func categoryName(_ id: String) -> String {
    if let category = Library.categories.first(where: { $0.id == id }) {
      return t(category.english, category.portuguese)
    }
    if let group = Library.groups.first(where: { $0.id == id }) {
      return t(group.english, group.portuguese)
    }
    return t("All apps", "Todas as apps")
  }
  func applyProfile(_ profile: LibraryProfile, adding: Bool) {
    guard !busy else { return }
    let eligible = Library.selectable(profile.apps, catalog: apps, installed: inventory.apps)
    if adding {
      state.installSelection.formUnion(eligible)
    } else {
      state.installSelection = eligible
    }
    status = t("Profile applied. Review your selection.", "Perfil aplicado. Revê a seleção.")
    profilePicker = false
    save()
  }
  func clearResults() {
    guard !busy, state.queue.allSatisfy({ $0.stage.terminal }) else { return }
    state.queue = []
    status = t("Results kept in history.", "Resultados guardados no histórico.")
    save()
  }
  func prepareRetry() {
    guard !busy else { return }
    let failed = state.queue.filter { [.failed, .stopped, .interrupted].contains($0.stage) }
    guard let operation = failed.first?.operation else { return }
    changePage(operation == "remove" ? "uninstall" : "install")
    let ids = failed.filter { $0.operation == operation }.map(\.appID)
    if operation == "remove" {
      state.removalSelection = Library.removableSelection(
        Set(ids), catalog: apps,
        installed: inventory.apps, receipts: state.receipts)
    } else {
      state.installSelection = Library.selectable(ids, catalog: apps, installed: inventory.apps)
    }
    status = t(
      "Retry prepared. Review before continuing.",
      "Nova tentativa preparada. Revê antes de continuar.")
    save()
  }
  func sourceName(_ app: CatalogApp) -> String {
    if page == "uninstall", let installed = inventory.apps.first(where: { $0.path == app.id }) {
      return removalName(installed)
    }
    return app.automatic
      ? t("Homebrew · automatic", "Homebrew · automática")
      : app.source == "appstore"
        ? t("App Store · guided", "App Store · guiada")
        : t("Website · guided", "Site oficial · guiada")
  }
  func stageName(_ stage: QueueStage) -> String {
    switch stage {
    case .waiting: return t("Waiting", "Em espera")
    case .preparing: return t("Preparing", "A preparar")
    case .installing: return t("Installing", "A instalar")
    case .removing: return t("Removing", "A desinstalar")
    case .verifying: return t("Verifying", "A verificar")
    case .succeeded: return t("Verified", "Confirmado")
    case .failed: return t("Needs attention", "Precisa de atenção")
    case .guided: return t("Continue on website", "Continua no site")
    case .stopped: return t("Stopped", "Parado")
    case .interrupted:
      return t("Interrupted · refresh to verify", "Interrompido · atualiza para verificar")
    }
  }
  func resultLabel(_ entry: QueueEntry) -> String {
    (entry.operation == "cleanup"
      ? t("Data cleanup", "Limpeza de dados")
      : entry.operation == "remove" ? t("Removal", "Remoção") : t("Installation", "Instalação"))
      + " · " + stageName(entry.stage)
  }
  func celebrate() {
    guard !reduced else { return }
    withAnimation(.easeOut(duration: 0.45)) { successPulse = true }
    Task {
      try? await Task.sleep(for: .seconds(1))
      withAnimation(.easeOut(duration: 0.9)) { successPulse = false }
    }
  }
  func changePage(_ value: String) {
    guard value != page else { return }
    PerformanceHarness.navigation(value)
    pageFilters[page] = (search, category, installedOnly)
    page = value
    let remembered = pageFilters[value] ?? ("", "all", false)
    search = remembered.0
    category = remembered.1
    installedOnly = remembered.2
  }
  func saveProfile() {
    let snapshot = Array(selection).sorted()
    DispatchQueue.main.async { [weak self] in self?.presentSaveProfile(snapshot) }
  }
  private func presentSaveProfile(_ snapshot: [String]) {
    guard !busy else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "1nstall-profile.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
      status =
        t("Profile saved: ", "Perfil guardado: ") + String(snapshot.count)
        + (snapshot.count == 1 ? t(" app.", " app.") : t(" apps.", " apps."))
    } catch { status = error.localizedDescription }
  }
  func loadProfile() {
    DispatchQueue.main.async { [weak self] in self?.presentLoadProfile() }
  }
  private func presentLoadProfile() {
    guard !busy else { return }
    let panel = NSOpenPanel()
    // Some creative tools register .json as their own UTI. Validate the extension,
    // size and JSON schema ourselves instead of hiding valid profiles in the picker.
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      guard url.pathExtension.lowercased() == "json",
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 100_000
      else { throw OperationError("Invalid or oversized profile") }
      let data = try Data(contentsOf: url)
      let ids = try JSONDecoder().decode([String].self, from: data)
      profile(ids)
      status = t("Profile loaded. Review your selection.", "Perfil carregado. Revê a seleção.")
    } catch {
      status = t("This profile could not be loaded.", "Não foi possível carregar este perfil.")
    }
  }
  func openOfficial(_ app: CatalogApp) {
    if let url = URL(string: app.website), url.scheme == "https" { NSWorkspace.shared.open(url) }
  }
  func beginReview() {
    guard !busy, !selectedApps.isEmpty else { return }
    review = true
    guard page == "uninstall" else { return }
    preparingRemoval = true
    removalPlans = []
    removalIssues = [:]
    let selected = selectedInstalledApps
    let revision = UUID()
    removalReviewID = revision
    let catalog = apps
    Task {
      let result = await Task.detached(priority: .userInitiated) {
        () -> ([RemovalPlan], [String: String]) in
        var plans: [RemovalPlan] = []
        var issues: [String: String] = [:]
        let engine = RemovalEngine()
        for app in selected {
          do {
            plans.append(try engine.prepare(RemovalIdentity.inspect(app, catalog: catalog)))
          } catch { issues[app.path] = error.localizedDescription }
        }
        return (plans, issues)
      }.value
      guard removalReviewID == revision else { return }
      removalPlans = result.0
      removalIssues = result.1
      preparingRemoval = false
    }
  }
  func runRemovalQueue() {
    guard !capture, !busy, !preparingRemoval, removalIssues.isEmpty, !removalPlans.isEmpty,
      Set(removalPlans.map(\.id)) == Set(selectedInstalledApps.map(\.id))
    else { return }
    let plans = removalPlans
    state.queue = plans.map { QueueEntry(plan: $0) }
    busy = true
    stopRequested = false
    review = false
    save()
    status = t(
      "Removing selected apps. Data is kept for review.",
      "A remover as apps selecionadas. Os dados ficam para revisão.")
    Task {
      for (i, plan) in plans.enumerated() {
        if stopRequested {
          state.queue[i].stage = .stopped
          save()
          continue
        }
        let entryID = state.queue[i].id
        appendLog("\nREMOVE \(plan.identity.app.path) · \(plan.method.rawValue)\n")
        do {
          let result = try await Task.detached(priority: .userInitiated) { [weak self] in
            try RemovalEngine().remove(
              plan,
              onStage: { stage in
                DispatchQueue.main.async {
                  guard let self, self.state.queue.indices.contains(i),
                    self.state.queue[i].id == entryID,
                    !self.state.queue[i].stage.terminal
                  else { return }
                  self.state.queue[i].stage = stage
                  self.save()
                }
              }, log: { text in DispatchQueue.main.async { self?.appendLog(text) } })
          }.value
          state.queue[i].stage = .succeeded
          state.queue[i].trashPath = result.trashPath
          state.queue[i].detail =
            result.trashPath == nil
            ? t(
              "App and Homebrew record removed. Personal data kept for review.",
              "App e registo Homebrew removidos. Dados pessoais preservados para revisão.")
            : t(
              "App moved to Trash and verified. Data kept for review; disk space is not yet freed.",
              "App movida para o Lixo e verificada. Dados preservados para revisão; o espaço ainda não foi libertado."
            )
          if result.remainingCopies > 0 {
            state.queue[i].detail += t(
              " Another copy remains installed; data cleanup is blocked.",
              " Continua instalada outra cópia; a limpeza de dados está bloqueada.")
          }
          state.receipts = state.receipts.filter { $0.value != plan.identity.app.path }
          state.removalSelection.remove(plan.id)
          appendLog(state.queue[i].detail + "\n")
        } catch {
          state.queue[i].stage = .failed
          state.queue[i].detail = error.localizedDescription
          appendLog(error.localizedDescription + "\n")
        }
        save()
      }
      state.history.append(contentsOf: state.queue)
      state.history = Array(state.history.suffix(200))
      busy = false
      save()
      refresh()
      let succeeded = state.queue.filter { $0.stage == .succeeded }.count
      status =
        "\(succeeded)/\(state.queue.count) "
        + t(
          "removals verified. Review associated data below.",
          "remoções confirmadas. Revê os dados associados abaixo.")
      if succeeded == state.queue.count { celebrate() }
    }
  }
  func runQueue() {
    if page == "uninstall" {
      runRemovalQueue()
      return
    }
    guard !busy, !selectedApps.isEmpty, !capture else { return }
    let batch = selectedApps
    state.queue = batch.map { QueueEntry(app: $0, operation: "install") }
    save()
    busy = true
    status = t(
      "Processing your selection. Results are verified app by app.",
      "A processar a seleção. Os resultados são verificados app a app.")
    stopRequested = false
    review = false
    Task {
      for (i, app) in batch.enumerated() {
        if stopRequested {
          state.queue[i].stage = .stopped
          save()
          continue
        }
        appendLog(
          "\n\(ISO8601DateFormatter().string(from:Date())) INSTALL \(app.id)\n"
        )
        if !app.automatic {
          openOfficial(app)
          state.queue[i].stage = .guided
          save()
          continue
        }
        do {
          let engine = brew
          let entryID = state.queue[i].id
          let path = try await Task.detached(priority: .userInitiated) { [weak self] () -> String in
            let stage: (QueueStage) -> Void = { s in
              DispatchQueue.main.async {
                guard let self, self.state.queue.indices.contains(i),
                  self.state.queue[i].id == entryID, !self.state.queue[i].stage.terminal
                else { return }
                self.state.queue[i].stage = s
                self.save()
              }
            }
            let log: (String) -> Void = { s in DispatchQueue.main.async { self?.appendLog(s) } }
            return try engine.install(app, onStage: stage, log: log)
          }.value
          state.queue[i].stage = .succeeded
          state.receipts[app.id] = path
          state.installSelection.remove(app.id)
        } catch {
          state.queue[i].stage = .failed
          state.queue[i].detail = error.localizedDescription
          appendLog(error.localizedDescription + "\n")
        }
        save()
      }
      state.history.append(contentsOf: state.queue)
      state.history = Array(state.history.suffix(200))
      save()
      busy = false
      refresh()
      if state.queue.allSatisfy({ $0.stage == .succeeded }) {
        status = t(
          "All operations verified. You're all set.",
          "Todas as operações foram confirmadas. Tudo pronto.")
        celebrate()
      } else {
        status = t(
          "Queue finished. Review the results below.", "Fila terminada. Revê os resultados abaixo.")
      }
    }
  }
  func scanLeftovers(_ app: CatalogApp) { scanLeftovers(RemovalIdentity(catalog: app)) }
  func scanLeftovers(_ installed: InstalledApp) {
    guard !busy else { return }
    let catalog = apps
    Task {
      let identity = await Task.detached(priority: .utility) {
        RemovalIdentity.inspect(installed, catalog: catalog)
      }.value
      scanLeftovers(identity)
    }
  }
  func scanLeftovers(_ app: RemovalIdentity) {
    guard !busy else { return }
    leftoverSelection = []
    leftoverResult = ""
    leftoverReport = LeftoverReport()
    leftoverScanning = true
    cleanupConfirm = false
    leftoverApp = app
    Task {
      let installed = inventory.apps
      let report = await Task.detached(priority: .utility) {
        LeftoverScanner().scan(app, installed: installed)
      }.value
      if leftoverApp?.id == app.id {
        leftoverReport = report
        leftoverScanning = false
      }
    }
  }
  func cleanup() {
    guard let app = leftoverApp, !busy, !capture else { return }
    let items = leftoverReport.items.filter { leftoverSelection.contains($0.id) }
    guard !items.isEmpty else { return }
    busy = true
    cleanupConfirm = false
    Task {
      let result = await Task.detached(priority: .utility) { () -> (Int, Int64, [String]) in
        let scanner = LeftoverScanner()
        var count = 0
        var bytes: Int64 = 0
        var errors: [String] = []
        for item in items {
          let inventory = Inventory.scan()
          guard inventory.warnings.isEmpty else {
            errors.append("Inventory incomplete")
            break
          }
          do {
            let destination = try scanner.trash(item, for: app, installed: inventory.apps)
            count += 1
            bytes += item.bytes
            errors.append("Trash: \(destination.path)")
          } catch { errors.append(error.localizedDescription) }
        }
        return (count, bytes, errors)
      }.value
      busy = false
      leftoverSelection = []
      if result.0 == items.count { celebrate() }
      leftoverResult =
        "\(result.0)/\(items.count) · \(ByteCountFormatter.string(fromByteCount:result.1,countStyle:.file)) "
        + t(
          "moved to Trash. Disk space is not yet freed.",
          "movidos para o Lixo. O espaço em disco ainda não foi libertado.")
      appendLog(leftoverResult + "\n" + result.2.joined(separator: "\n") + "\n")
      state.history.append(
        QueueEntry(cleanup: app, detail: leftoverResult, succeeded: result.0 == items.count))
      state.history = Array(state.history.suffix(200))
      save()
      let installed = inventory.apps
      leftoverReport = await Task.detached(priority: .utility) {
        LeftoverScanner().scan(app, installed: installed)
      }.value
    }
  }
}

struct SelectionEvent: Equatable {
  let id = UUID()
  let app: CatalogApp
  let adding: Bool
}
