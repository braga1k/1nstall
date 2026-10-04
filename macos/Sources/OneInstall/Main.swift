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
    model = AppModel(capture: args.contains("--capture"))
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
      for (theme, accent) in [("dark", true), ("light", true), ("dark", false), ("light", false)] {
        model.theme = theme
        model.accent = accent
        window.setContentSize(NSSize(width: 1240, height: 840))
        try await Task.sleep(for: .milliseconds(700))
        guard let view = window.contentView,
          let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { throw OperationError("Capture unavailable") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(
          to: directory.appendingPathComponent("install-\(theme)\(accent ? "":"-monochrome").png"))
      }
      print("Captured four English appearances")
    } catch { print("Capture failed: \(error)") }
    NSApp.terminate(nil)
  }
}
