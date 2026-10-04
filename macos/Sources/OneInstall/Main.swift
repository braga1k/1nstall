import AppKit
import OneInstallCore
import SwiftUI

@main enum Main {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
    withExtendedLifetime(delegate) {}
  }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  var window: NSWindow!
  var model: AppModel!
  func applicationDidFinishLaunching(_ notification: Notification) {
    let args = CommandLine.arguments
    model = AppModel(capture: args.contains("--capture") || args.contains("--ui-checks"))
    if args.contains("--ui-checks") {
      do {
        try PreviewChecks.run(model)
        exit(0)
      } catch {
        print(error)
        exit(1)
      }
    }
    if model.capture {
      window = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 1240, height: 840),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    } else {
      window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1240, height: 840),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false)
    }
    window.title = "1nstall · Mac Preview"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.minSize = NSSize(width: 1040, height: 640)
    window.delegate = self
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      window.standardWindowButton(type)?.isHidden = true
    }
    window.contentView = NSHostingView(rootView: ContentView(m: model))
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    createMenu()
    NotificationCenter.default.addObserver(
      self, selector: #selector(updateMenu), name: Notification.Name("1nstall.language"),
      object: nil)
    if let index = args.firstIndex(of: "--capture"), args.count > index + 1 {
      Task { await capture(to: URL(fileURLWithPath: args[index + 1])) }
    } else {
      model.refresh()
    }
  }
  func createMenu() {
    let menu = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appItem.submenu = appMenu
    menu.addItem(appItem)
    appMenu.addItem(
      withTitle: model.t("About 1nstall", "Sobre a 1nstall"), action: #selector(settings),
      keyEquivalent: "")
    appMenu.addItem(
      withTitle: model.t("Settings…", "Definições…"), action: #selector(settings),
      keyEquivalent: ",")
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: model.t("Hide 1nstall", "Ocultar a 1nstall"),
      action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(
      withTitle: model.t("Quit 1nstall", "Sair da 1nstall"),
      action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let editItem = NSMenuItem(title: model.t("Edit", "Editar"), action: nil, keyEquivalent: "")
    let edit = NSMenu(title: editItem.title)
    editItem.submenu = edit
    menu.addItem(editItem)
    edit.addItem(
      withTitle: model.t("Copy", "Copiar"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(
      withTitle: model.t("Paste", "Colar"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(
      withTitle: model.t("Select All", "Selecionar tudo"), action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a")
    edit.addItem(
      withTitle: model.t("Find apps", "Pesquisar apps"), action: #selector(search),
      keyEquivalent: "f")
    let viewItem = NSMenuItem(title: model.t("View", "Ver"), action: nil, keyEquivalent: "")
    let view = NSMenu(title: viewItem.title)
    viewItem.submenu = view
    menu.addItem(viewItem)
    for (title, action, key) in [
      (model.t("Install", "Instalar"), #selector(installPage), "1"),
      (model.t("Uninstall", "Desinstalar"), #selector(uninstallPage), "2"),
      (model.t("History", "Histórico"), #selector(historyPage), "3"),
      (model.t("Refresh inventory", "Atualizar inventário"), #selector(refreshInventory), "r"),
    ] {
      view.addItem(withTitle: title, action: action, keyEquivalent: key)
    }
    let winItem = NSMenuItem(title: model.t("Window", "Janela"), action: nil, keyEquivalent: "")
    let win = NSMenu(title: winItem.title)
    winItem.submenu = win
    menu.addItem(winItem)
    win.addItem(
      withTitle: model.t("Minimise", "Minimizar"), action: #selector(NSWindow.miniaturize(_:)),
      keyEquivalent: "m")
    win.addItem(
      withTitle: model.t("Close", "Fechar"), action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w")
    win.addItem(
      withTitle: model.t("Show 1nstall", "Mostrar a 1nstall"), action: #selector(showWindow),
      keyEquivalent: "")
    NSApp.mainMenu = menu
    NSApp.windowsMenu = win
  }
  @objc func installPage() { model.changePage("install") }
  @objc func uninstallPage() {
    model.changePage("uninstall")
    if !model.capture { model.refresh() }
  }
  @objc func historyPage() { model.changePage("history") }
  @objc func refreshInventory() { if !model.busy && !model.capture { model.refresh() } }
  @objc func updateMenu() { createMenu() }
  @objc func settings() { model.changePage("settings") }
  @objc func search() {
    if model.page != "install" && model.page != "uninstall" { model.changePage("install") }
    NotificationCenter.default.post(name: Notification.Name("1nstall.search"), object: nil)
  }
  @objc func showWindow() { window.makeKeyAndOrderFront(nil) }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showWindow()
    return true
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if model.busy {
      model.status = model.t(
        "Wait for the current operation or stop after this app.",
        "Aguarda a operação atual ou para após esta app.")
      return false
    }
    return true
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    model.busy ? .terminateCancel : .terminateNow
  }
  func capture(to directory: URL) async {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var count = 0
      for (theme, accent) in [("dark", true), ("light", true), ("dark", false), ("light", false)] {
        model.theme = theme
        model.accent = accent
        let suffix = "-\(theme)\(accent ? "":"-monochrome")"
        model.state = SavedState()
        model.state.installSelection = ["rectangle"]
        model.inventory = InventoryResult()
        model.page = "install"
        model.category = "all"
        model.expandedGroups = []
        model.status = ""
        window.setContentSize(NSSize(width: 1240, height: 840))
        try await captureFrame("install" + suffix, to: directory)
        count += 1
        model.page = "settings"
        try await captureFrame("settings" + suffix, to: directory)
        count += 1
        model.page = "uninstall"
        model.inventory.apps = model.apps.map { app in
          InstalledApp(
            name: app.name, bundleID: app.bundleID, path: "/Fixture Applications/" + app.appName,
            version: app.version, store: app.source == "appstore")
        }
        model.state.receipts["iina"] = "/Fixture Applications/IINA.app"
        model.state.removalSelection = ["iina"]
        try await captureFrame("uninstall" + suffix, to: directory)
        count += 1
        if accent {
          var entry = QueueEntry(app: model.apps.first { $0.id == "iina" }!, operation: "remove")
          entry.stage = .succeeded
          model.state.removalSelection = []
          model.state.queue = [entry]
          model.inventory.apps.removeAll { $0.bundleID == "com.colliderli.iina" }
          model.status = "Removal verified. Results stay in history."
          try await captureFrame("uninstall-queue" + suffix, to: directory)
          count += 1
          model.state = SavedState()
          model.inventory = InventoryResult()
          model.page = "install"
          model.status = ""
          model.expandedGroups = ["everyday"]
          model.category = "players"
          try await captureFrame("categories" + suffix, to: directory)
          count += 1
          model.expandedGroups = []
          model.category = "all"
          window.setContentSize(NSSize(width: 1040, height: 640))
          try await captureFrame("minimum" + suffix, to: directory)
          count += 1
        }
      }
      print(
        "Captured \(count) English appearances; uninstall uses explicit fixtures, without system inventory or operations"
      )
    } catch {
      print("Capture failed: \(error)")
      exit(1)
    }
    NSApp.terminate(nil)
  }
  func captureFrame(_ name: String, to directory: URL) async throws {
    try await Task.sleep(for: .milliseconds(450))
    guard let view = window.contentView,
      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    else { throw OperationError("Capture unavailable") }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      throw OperationError("PNG unavailable")
    }
    try data.write(to: directory.appendingPathComponent(name + ".png"))
  }
}
