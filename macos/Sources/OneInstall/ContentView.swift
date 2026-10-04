import AppKit
import OneInstallCore
import SwiftUI

struct ContentView: View {
  @ObservedObject var m: AppModel
  @Environment(\.colorScheme) var systemScheme
  @FocusState var searchFocused: Bool
  @State var activity = false
  var p: Palette {
    Palette(
      dark: m.theme == "dark" || (m.theme == "system" && systemScheme == .dark), accent: m.accent,
      demo: m.capture)
  }
  var body: some View {
    ZStack {
      p.background
      RadialGradient(
        colors: [p.action.opacity(p.dark ? 0.1 : 0.12), .clear], center: .topLeading,
        startRadius: 10, endRadius: 850)
      HStack(spacing: 20) {
        navigation.frame(width: 244)
        Group {
          if m.page == "settings" {
            settings
          } else if m.page == "history" {
            history
          } else {
            library
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        if m.page == "install" || m.page == "uninstall" { selection.frame(width: 244) }
      }.padding(12)
      if m.successPulse {
        RoundedRectangle(cornerRadius: 26).stroke(p.action.opacity(0.65), lineWidth: 5).blur(
          radius: 18
        ).padding(12).allowsHitTesting(false)
      }
    }
    .ignoresSafeArea()
    .foregroundStyle(p.ink).font(.system(size: 13))
    .environment(\.palette, p).environmentObject(m)
    .preferredColorScheme(m.theme == "system" ? nil : (m.theme == "dark" ? .dark : .light))
    .tint(p.action)
    .saturation(m.accent ? 1 : 0)
    .frame(minWidth: 1040, minHeight: 640)
    .animation(m.reduced ? nil : .easeInOut(duration: 0.2), value: m.page)
    .animation(
      m.reduced ? nil : .spring(response: 0.32, dampingFraction: 0.86),
      value: m.state.installSelection
    )
    .animation(m.reduced ? nil : .easeInOut(duration: 0.2), value: m.category)
    .sheet(item: $m.detailApp) { app in details(app).environment(\.palette, p).environmentObject(m)
    }
    .sheet(isPresented: $m.review) { review.environment(\.palette, p).environmentObject(m) }
    .sheet(item: $m.leftoverApp) { app in
      leftovers(app).environment(\.palette, p).environmentObject(m)
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("1nstall.search"))) {
      _ in searchFocused = true
    }
  }
  func button(
    _ label: String, selected: Bool = false, prominent: Bool = false, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) { Text(label).frame(maxWidth: .infinity) }.buttonStyle(
      GlassButtonStyle(prominent: prominent, selected: selected))
  }
  var navigation: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .topLeading) {
        Mark().fill(p.ink).frame(width: 32, height: 32).frame(maxWidth: .infinity).padding(.top, 7)
        HStack(spacing: 6) {
          windowButton("xmark", m.t("Close", "Fechar")) { NSApp.keyWindow?.performClose(nil) }
          windowButton("minus", m.t("Minimise", "Minimizar")) { NSApp.keyWindow?.miniaturize(nil) }
          windowButton("arrow.up.left.and.arrow.down.right", m.t("Full screen", "Ecrã completo")) {
            NSApp.keyWindow?.toggleFullScreen(nil)
          }
        }.padding(.top, 1)
      }.frame(height: 60)
      VStack(spacing: 5) {
        button(m.t("Install", "Instalar"), selected: m.page == "install") {
          m.changePage("install")
        }
        button(m.t("Uninstall", "Desinstalar"), selected: m.page == "uninstall") {
          m.changePage("uninstall")
          m.refresh()
        }
        button(
          m.t("History & diagnostics", "Histórico e diagnóstico"), selected: m.page == "history"
        ) { m.changePage("history") }
      }
      VStack(alignment: .leading, spacing: 8) {
        Text(m.page == "uninstall" ? m.t("INSTALLED", "INSTALADAS") : m.t("LIBRARY", "BIBLIOTECA"))
          .font(.system(size: 11, weight: .medium))
        Text(
          m.page == "uninstall"
            ? "\(m.inventory.apps.count) " + m.t("apps found", "apps encontradas")
            : "\(m.apps.count) " + m.t("apps · Mac preview", "apps · prévia Mac")
        ).font(.system(size: 11))
      }.foregroundStyle(p.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(
        .horizontal, 8
      ).padding(.top, 22).padding(.bottom, 12)
      ScrollView {
        VStack(spacing: 9) {
          button(m.t("All apps", "Todas as apps"), selected: m.category == "all") {
            m.category = "all"
          }
          ForEach(["everyday", "create", "files", "tools"], id: \.self) { id in
            Button {
              m.category = m.category == id ? "all" : id
            } label: {
              HStack {
                Text(m.categoryName(id))
                Spacer()
                Image(systemName: m.category == id ? "chevron.down" : "chevron.right").font(
                  .system(size: 10, weight: .semibold))
              }.padding(.horizontal, 10).frame(height: 43)
            }
            .buttonStyle(.plain).glass(radius: 13, selected: m.category == id)
          }
        }.padding(.vertical, 4)
      }.scrollIndicators(.hidden)
      Spacer(minLength: 8)
      button(m.t("Settings", "Definições"), selected: m.page == "settings") {
        m.changePage("settings")
      }
      button(m.t("Buy me a beer", "Paga-me uma cerveja"), prominent: true) {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/braga1k")!)
      }.padding(.top, 12)
    }.padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 16).glass(radius: 26, panel: true)
  }
  func windowButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 7, weight: .medium)).frame(width: 13, height: 13)
        .background(Circle().fill(p.secondary.opacity(0.14))).overlay(
          Circle().stroke(p.secondary.opacity(0.4), lineWidth: 0.6))
    }.buttonStyle(.plain).accessibilityLabel(label).help(label)
  }
  var library: some View {
    VStack(spacing: 14) {
      HStack(spacing: 8) {
        Button(m.t("All apps", "Todas as apps")) { m.installedOnly = false }.buttonStyle(
          GlassButtonStyle(selected: !m.installedOnly, compact: true))
        Button(
          m.page == "uninstall"
            ? m.t("Managed by 1nstall", "Geridas pela 1nstall") : m.t("Installed", "Instaladas")
        ) { m.installedOnly = true }.buttonStyle(
          GlassButtonStyle(selected: m.installedOnly, compact: true))
        Button(m.scanning ? m.t("Scanning…", "A analisar…") : m.t("Refresh", "Atualizar")) {
          m.refresh()
        }.buttonStyle(GlassButtonStyle(compact: true)).disabled(m.scanning || m.busy)
        Spacer()
        if m.page == "uninstall" {
          Text(m.t("Review before removal", "Rever antes de remover")).foregroundStyle(p.secondary)
            .font(.system(size: 11))
        }
      }.padding(.top, 20).padding(.bottom, 5)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 9) {
          searchField.frame(minWidth: 230)
          profileTools
        }
        VStack(spacing: 8) {
          searchField
          HStack(spacing: 9) {
            profileTools
            Spacer(minLength: 0)
          }
        }
      }
      if m.page == "install" { installGrid } else { uninstallList }
      VStack(spacing: 0) {
        Button {
          activity.toggle()
        } label: {
          HStack {
            Text(m.t("Activity & details", "Atividade e detalhes"))
            Spacer()
            Image(systemName: activity ? "chevron.down" : "chevron.right")
          }.foregroundStyle(p.secondary).padding(12).frame(height: 44)
        }.buttonStyle(.plain)
        if activity {
          ScrollView {
            Text(
              m.logText.isEmpty
                ? m.t(
                  "Ready. Results stay visible after the queue finishes.",
                  "Tudo pronto. Os resultados permanecem visíveis após a conclusão da fila.")
                : m.logText
            ).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(
              maxWidth: .infinity, alignment: .leading
            ).padding(12)
          }.frame(height: 130)
        }
      }.glass(radius: 14).padding(.bottom, 5)
    }
  }
  var searchField: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass").foregroundStyle(p.secondary)
      TextField(m.t("Search apps · ⌘F", "Pesquisar apps · ⌘F"), text: $m.search).textFieldStyle(
        .plain
      ).focused($searchFocused).accessibilityLabel(m.t("Search apps", "Pesquisar apps"))
      Button {
        m.search = ""
      } label: {
        Image(systemName: "xmark").font(.system(size: 10))
      }.buttonStyle(.plain).accessibilityLabel(m.t("Clear search", "Limpar pesquisa"))
    }.padding(.horizontal, 13).frame(height: 42).glass(radius: 22, control: true)
  }
  @ViewBuilder var profileTools: some View {
    if m.page == "install" {
      Menu {
        Button(
          m.t("Everyday · IINA, Rectangle, LocalSend", "Dia a dia · IINA, Rectangle, LocalSend")
        ) { m.profile(["iina", "rectangle", "localsend"]) }
        Button(m.t("Create · Blender, Keka, VLC", "Criar · Blender, Keka, VLC")) {
          m.profile(["blender", "keka", "vlc"])
        }
        Button(
          m.t(
            "Development · VS Code, Firefox, Rectangle", "Programação · VS Code, Firefox, Rectangle"
          )
        ) { m.profile(["visual-studio-code", "firefox", "rectangle"]) }
      } label: {
        Text(m.t("All profiles", "Perfis")).foregroundStyle(p.ink)
      }.menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 11).frame(height: 35).glass(
        control: true
      ).disabled(m.busy)
      Menu {
        Button(m.t("Save selection…", "Guardar seleção…")) { m.saveProfile() }
        Button(m.t("Load profile…", "Carregar perfil…")) { m.loadProfile() }
      } label: {
        Text(m.t("User profiles", "Os meus perfis")).foregroundStyle(p.ink)
      }.menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 10).frame(height: 35).glass(
        control: true
      ).disabled(m.busy)
    }
    Button(m.t("Clear selection", "Limpar seleção")) { m.clear() }.buttonStyle(
      GlassButtonStyle(compact: true)
    ).fixedSize().disabled(m.busy)
  }
  var filtered: [CatalogApp] {
    m.apps.filter {
      (m.category == "all" || $0.category == m.category) && (!m.installedOnly || m.installed($0))
        && (m.search.isEmpty
          || "\($0.name) \(m.categoryName($0.category)) \($0.summaryEN) \($0.summaryPT)"
            .localizedCaseInsensitiveContains(m.search))
    }
  }
  var installGrid: some View {
    GeometryReader { geo in
      ScrollView {
        LazyVGrid(
          columns: Array(
            repeating: GridItem(.flexible(), spacing: 8), count: geo.size.width < 560 ? 2 : 3),
          spacing: 8
        ) {
          ForEach(filtered) { app in card(app) }
        }.padding(.bottom, 4)
        if filtered.isEmpty {
          Text(
            m.t(
              "No apps found. Try another search.",
              "Nenhuma app encontrada. Experimenta outra pesquisa.")
          ).foregroundStyle(p.secondary).padding(.top, 40)
        }
      }.scrollIndicators(.hidden)
    }
  }
  func card(_ app: CatalogApp) -> some View {
    let selected = m.state.installSelection.contains(app.id)
    let installed = m.installed(app)
    return VStack(alignment: .leading, spacing: 7) {
      Button {
        m.toggle(app)
      } label: {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .top) {
            Text(app.name).font(.system(size: 13, weight: .regular)).lineLimit(2)
              .multilineTextAlignment(.leading)
            Spacer(minLength: 3)
            ZStack {
              RoundedRectangle(cornerRadius: 6).stroke(p.secondary.opacity(0.7), lineWidth: 1)
              if selected || installed {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
              }
            }.frame(width: 18, height: 18)
          }
          Spacer(minLength: 4)
          VStack(alignment: .leading, spacing: 3) {
            Text(m.categoryName(app.category))
            Text(
              installed
                ? m.t("Installed · detected on this Mac", "Instalada · detetada neste Mac")
                : m.sourceName(app))
          }.font(.system(size: 10.5)).tracking(0.2).foregroundStyle(p.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 72).contentShape(
          Rectangle())
      }.buttonStyle(.plain).disabled(installed || m.busy).accessibilityLabel(app.name)
        .accessibilityValue(
          installed
            ? m.t("Installed", "Instalada")
            : selected ? m.t("Selected", "Selecionada") : m.t("Not selected", "Não selecionada"))
      Button {
        m.detailApp = app
      } label: {
        Text(m.t("Details", "Detalhes")).font(.system(size: 11)).frame(maxWidth: .infinity).frame(
          height: 27)
      }.buttonStyle(.plain).glass(radius: 16, control: true)
    }.padding(13).frame(height: 140).glass(radius: 18, selected: selected).opacity(
      installed ? 0.57 : 1)
  }
  var filteredInventory: [InstalledApp] {
    m.inventory.apps.filter { installed in
      let catalog = m.apps.first { $0.bundleID == installed.bundleID }
      return (m.search.isEmpty || installed.name.localizedCaseInsensitiveContains(m.search))
        && (m.category == "all" || catalog?.category == m.category)
        && (!m.installedOnly || catalog.map { m.state.receipts[$0.id] != nil } == true)
    }
  }
  var uninstallList: some View {
    ScrollView {
      LazyVStack(spacing: 8) {
        ForEach(filteredInventory) { installed in
          let app = m.apps.first { $0.bundleID == installed.bundleID }
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
              Text(installed.name).fontWeight(.medium)
              Text(installed.path).font(.system(size: 10)).foregroundStyle(p.secondary).lineLimit(1)
              Text(installed.version + (installed.store ? " · App Store" : "")).font(
                .system(size: 10)
              ).foregroundStyle(p.secondary)
            }
            Spacer()
            if let app {
              Button(m.t("Leftovers", "Resíduos")) { m.scanLeftovers(app) }.buttonStyle(
                GlassButtonStyle(compact: true)
              ).disabled(m.busy)
              if m.state.receipts[app.id] != nil {
                Button(
                  m.selection.contains(app.id)
                    ? m.t("Selected", "Selecionada") : m.t("Select", "Selecionar")
                ) { m.toggle(app) }.buttonStyle(
                  GlassButtonStyle(selected: m.selection.contains(app.id), compact: true)
                ).disabled(m.busy)
              } else {
                Button(m.t("Show in Finder", "Mostrar no Finder")) {
                  NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: installed.path)
                  ])
                }.buttonStyle(GlassButtonStyle(compact: true))
              }
            } else {
              Button(m.t("Show in Finder", "Mostrar no Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([
                  URL(fileURLWithPath: installed.path)
                ])
              }.buttonStyle(GlassButtonStyle(compact: true))
            }
          }.padding(14).glass(radius: 18)
        }
        if filteredInventory.isEmpty {
          Text(
            m.scanning
              ? m.t("Reading app bundles…", "A ler as aplicações…")
              : m.t("No apps in the scanned locations.", "Nenhuma app nos locais analisados.")
          ).padding(30)
        }
      }.padding(.bottom, 4)
    }.scrollIndicators(.hidden)
  }
  var selection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(m.t("Selection", "Seleção")).font(.system(size: 20, weight: .semibold)).padding(
        .bottom, 8)
      Text(
        "\(m.selection.count) "
          + (m.selection.count == 1
            ? m.t("app selected", "app selecionada") : m.t("apps selected", "apps selecionadas"))
      ).foregroundStyle(p.secondary).padding(.bottom, 18)
      button(m.t("Save selection…", "Guardar seleção…")) { m.saveProfile() }.disabled(m.busy)
      line.padding(.top, 16).padding(.bottom, 12)
      ScrollView {
        VStack(alignment: .leading, spacing: 17) {
          ForEach(m.selectedApps) { app in
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 10) {
                Text(app.name)
                Text(m.sourceName(app)).font(.system(size: 11)).foregroundStyle(p.secondary)
              }
              Spacer()
              Button {
                m.toggle(app)
              } label: {
                Image(systemName: "xmark").font(.system(size: 10))
              }.buttonStyle(.plain).disabled(m.busy).accessibilityLabel(
                m.t("Remove ", "Retirar ") + app.name)
            }.padding(.vertical, 12)
          }
          if !m.state.queue.isEmpty {
            line
            Text(m.t("QUEUE RESULTS", "RESULTADOS DA FILA")).font(
              .system(size: 10, weight: .semibold)
            ).foregroundStyle(p.secondary)
            ForEach(m.state.queue) { entry in
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Text(entry.name)
                  Spacer()
                  if entry.stage == .succeeded {
                    Image(systemName: "checkmark.circle")
                  } else if !entry.stage.terminal && entry.stage != .waiting {
                    ProgressView().controlSize(.small)
                  }
                }
                Text(m.resultLabel(entry)).font(.system(size: 11)).foregroundStyle(p.secondary)
                if !entry.detail.isEmpty {
                  Text(m.t("See diagnostics for details.", "Consulta os detalhes no diagnóstico."))
                    .font(.system(size: 10)).foregroundStyle(p.secondary)
                }
                if entry.operation == "remove", entry.stage == .succeeded,
                  let app = m.apps.first(where: { $0.id == entry.appID })
                {
                  Button(m.t("Review leftovers", "Rever resíduos")) { m.scanLeftovers(app) }
                    .buttonStyle(GlassButtonStyle(compact: true))
                }
              }
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.scrollIndicators(.hidden)
      line.padding(.vertical, 14)
      Text(m.status.isEmpty ? m.t("Ready when you are.", "Tudo pronto quando quiseres.") : m.status)
        .font(.system(size: 12)).foregroundStyle(p.secondary).fixedSize(
          horizontal: false, vertical: true
        ).padding(.bottom, 10)
      Text(m.t("Queue progress · apps processed", "Progresso da fila · apps processadas")).font(
        .system(size: 11)
      ).foregroundStyle(p.secondary)
      GeometryReader { g in
        ZStack(alignment: .leading) {
          Rectangle().fill(p.separator)
          Rectangle().fill(p.action).frame(
            width: m.state.queue.isEmpty
              ? 0
              : g.size.width * CGFloat(m.state.queue.filter { $0.stage.terminal }.count)
                / CGFloat(m.state.queue.count))
        }
      }.frame(height: 5).padding(.top, 6).padding(.bottom, 14)
      Text(
        m.page == "uninstall"
          ? m.t(
            "Automatic removal: apps installed by this preview. Data gets a separate review.",
            "Remoção automática: apps instaladas por esta prévia. Os dados têm uma revisão separada."
          )
          : m.t(
            "Automatic: installs with Homebrew.\nGuided: opens the official website.",
            "Automática: instala com Homebrew.\nGuiada: abre o site oficial.")
      ).font(.system(size: 11)).foregroundStyle(p.secondary).padding(.bottom, 14)
      if m.busy {
        button(
          m.stopRequested
            ? m.t("Stopping after this app…", "A parar após esta app…")
            : m.t("Stop after current app", "Parar após a app atual")
        ) { m.stopRequested = true }.disabled(m.stopRequested)
      } else {
        button(
          m.page == "uninstall"
            ? m.t("Review & remove  →", "Rever e remover  →")
            : m.t("Review & install  →", "Rever e instalar  →"), prominent: true
        ) { m.review = true }.disabled(m.selectedApps.isEmpty)
      }
      Button {
        m.changePage("history")
      } label: {
        Text(m.t("Open logs", "Abrir registos")).frame(maxWidth: .infinity).padding(.top, 14)
      }.buttonStyle(.plain).font(.system(size: 12))
    }.padding(.horizontal, 18).padding(.top, 25).padding(.bottom, 22).glass(radius: 26, panel: true)
  }
  var line: some View { Rectangle().fill(p.separator).frame(height: 1) }
  var settings: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        Text(m.t("Settings", "Definições")).font(.system(size: 28, weight: .semibold))
        Text(
          m.t(
            "The same identity, in every appearance.", "A mesma identidade, em todas as aparências."
          )
        ).foregroundStyle(p.secondary)
        settingsCard(m.t("Appearance", "Aparência")) {
          HStack {
            ForEach(["system", "light", "dark"], id: \.self) { value in
              button(
                value == "system"
                  ? m.t("System", "Sistema")
                  : value == "light" ? m.t("Light", "Claro") : m.t("Dark", "Escuro"),
                selected: m.theme == value
              ) { m.theme = value }
            }
          }
          Toggle(m.t("Use macOS accent colour", "Usar a cor de destaque do macOS"), isOn: $m.accent)
            .toggleStyle(.checkbox)
          Text(
            m.t(
              "Off gives you a completely monochrome interface, with the same gradients and depth.",
              "Desligada, a interface fica totalmente monocromática, mantendo os gradientes e a profundidade."
            )
          ).font(.system(size: 12)).foregroundStyle(p.secondary)
        }
        settingsCard(m.t("Motion", "Movimento")) {
          Toggle(m.t("Reduce motion", "Reduzir movimento"), isOn: $m.lessMotion).toggleStyle(
            .checkbox)
          Text(
            m.t(
              "The system's Reduce Motion preference is always respected.",
              "A preferência Reduzir movimento do sistema é sempre respeitada.")
          ).font(.system(size: 12)).foregroundStyle(p.secondary)
        }
        settingsCard(m.t("Language", "Idioma")) {
          HStack {
            button("Português (Portugal)", selected: m.pt) { m.language = "pt-PT" }
            button("English", selected: !m.pt) { m.language = "en" }
          }
        }
        settingsCard(m.t("About this preview", "Sobre esta prévia")) {
          Text("1nstall for Mac · 0.1.0 · Apple Silicon").fontWeight(.medium)
          Text(
            m.t(
              "15 curated entries · 5 reviewed Homebrew installers. Other apps continue on their official website or App Store.",
              "15 entradas selecionadas · 5 instalações Homebrew revistas. As restantes apps continuam no site oficial ou na App Store."
            ))
          Text(
            m.t(
              "App updates, signing and notarisation are not included in this development preview.",
              "As atualizações da própria app, a assinatura de distribuição e a notarização ainda não estão incluídas nesta prévia de desenvolvimento."
            )
          ).foregroundStyle(p.secondary)
          Text(
            m.brew.available
              ? m.t("Homebrew available", "Homebrew disponível")
              : m.t(
                "Homebrew not found. Guided downloads remain available.",
                "Homebrew não encontrado. As descargas guiadas continuam disponíveis."))
        }
      }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
    }.glass(radius: 26, panel: true)
  }
  func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 16) {
      Text(title).font(.system(size: 17, weight: .semibold))
      content()
    }.frame(maxWidth: .infinity, alignment: .leading).padding(20).glass(radius: 20)
  }
  var history: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text(m.t("History & diagnostics", "Histórico e diagnóstico")).font(
          .system(size: 25, weight: .semibold))
        Spacer()
        Button(m.t("Refresh inventory", "Atualizar inventário")) { m.refresh() }.buttonStyle(
          GlassButtonStyle())
      }
      Text(
        "\(m.inventory.apps.count) "
          + m.t(
            "app bundles found in /Applications, ~/Applications and /System/Applications.",
            "apps encontradas em /Applications, ~/Applications e /System/Applications.")
      ).foregroundStyle(p.secondary)
      Text(
        m.t(
          "Nested app bundles are excluded. Permission errors make the inventory partial.",
          "As apps internas a outras apps são excluídas. Erros de acesso tornam o inventário parcial."
        )
      ).font(.system(size: 12)).foregroundStyle(p.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if m.state.history.isEmpty {
            Text(
              m.t(
                "Your confirmed operations will appear here.",
                "As tuas operações vão aparecer aqui.")
            ).foregroundStyle(p.secondary)
          }
          ForEach(m.state.history.reversed()) { entry in
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text(entry.name).fontWeight(.medium)
                Spacer()
                Text(m.resultLabel(entry))
              }
              Text(entry.date, style: .date).font(.system(size: 11))
              if !entry.detail.isEmpty {
                Text(entry.detail).font(.system(size: 11, design: .monospaced)).textSelection(
                  .enabled)
              }
              if entry.operation == "remove", entry.stage == .succeeded,
                let app = m.apps.first(where: { $0.id == entry.appID })
              {
                Button(m.t("Review leftovers", "Rever resíduos")) { m.scanLeftovers(app) }
                  .buttonStyle(GlassButtonStyle(compact: true))
              }
            }.padding(16).glass()
          }
          ForEach(m.inventory.warnings, id: \.self) {
            Text($0).font(.system(size: 11, design: .monospaced))
          }
          if !m.logText.isEmpty {
            Text(m.logText).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
      Button(m.t("Show log file", "Mostrar ficheiro de registo")) {
        NSWorkspace.shared.activateFileViewerSelecting([m.logURL])
      }.buttonStyle(GlassButtonStyle()).disabled(
        !FileManager.default.fileExists(atPath: m.logURL.path))
    }.padding(24).glass(radius: 26, panel: true)
  }
  func details(_ app: CatalogApp) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text(app.name).font(.system(size: 27, weight: .semibold))
        Spacer()
        Button(m.t("Done", "Concluído")) { m.detailApp = nil }.buttonStyle(GlassButtonStyle())
      }
      Text(m.pt ? app.summaryPT : app.summaryEN)
      line
      Text(m.sourceName(app)).fontWeight(.medium)
      Text(m.t("Reviewed version: ", "Versão revista: ") + app.version)
      Text("macOS ≥ \(app.minimumOS) · \(app.architecture)")
      Text(m.t("Source checked: ", "Fonte consultada: ") + app.verified).foregroundStyle(
        p.secondary)
      if app.automatic {
        Text(
          m.t(
            "1nstall verifies the cask version and checksum before installation. A changed cask needs a new review.",
            "A 1nstall verifica a versão e o checksum do cask antes de instalar. Um cask alterado precisa de nova revisão."
          )
        ).font(.system(size: 12)).foregroundStyle(p.secondary)
      } else {
        Text(
          m.t(
            "Guided entry: availability checked; installation has not been tested by this preview. Confirm current requirements and terms at the source.",
            "Entrada guiada: disponibilidade consultada; instalação ainda não testada nesta prévia. Confirma os requisitos e condições atuais na fonte."
          )
        ).font(.system(size: 12)).foregroundStyle(p.secondary)
      }
      Button(m.t("Open official source  ↗", "Abrir fonte oficial  ↗")) { m.openOfficial(app) }
        .buttonStyle(GlassButtonStyle(prominent: true))
    }.padding(28).frame(width: 530).background(p.background).foregroundStyle(p.ink).saturation(
      m.accent ? 1 : 0)
  }
  var review: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(
        m.page == "uninstall"
          ? m.t("Review removal", "Rever remoção") : m.t("Review installation", "Rever instalação")
      ).font(.system(size: 25, weight: .semibold))
      Text(
        m.page == "uninstall"
          ? m.t(
            "The app bundle is removed with Homebrew. Preferences and support files are kept for a separate review. Quit each app first.",
            "A app é removida através do Homebrew. As preferências e os ficheiros de suporte ficam para uma revisão separada. Fecha cada app primeiro."
          )
          : m.t(
            "Homebrew installs the reviewed apps in /Applications. Guided entries open their official page; purchases and downloads remain your choice.",
            "O Homebrew instala as apps revistas em /Applications. As entradas guiadas abrem a página oficial; as compras e descargas ficam à tua escolha."
          )
      ).foregroundStyle(p.secondary)
      ScrollView {
        VStack(spacing: 10) {
          ForEach(m.selectedApps) { app in
            HStack {
              Text(app.name)
              Spacer()
              Text(m.sourceName(app)).font(.system(size: 11)).foregroundStyle(p.secondary)
            }.padding(14).glass()
          }
        }
      }.frame(maxHeight: 250)
      Text(
        m.t(
          "Progress counts completed apps, not download bytes. Success is shown only after verification.",
          "O progresso conta apps processadas, não bytes descarregados. O sucesso só aparece após verificação."
        )
      ).font(.system(size: 12)).foregroundStyle(p.secondary)
      HStack {
        button(m.t("Back", "Voltar")) { m.review = false }
        button(
          m.page == "uninstall"
            ? m.t("Remove these apps", "Remover estas apps")
            : m.t("Start installation", "Iniciar instalação"), prominent: true
        ) { m.runQueue() }
      }
    }.padding(28).frame(width: 570).background(p.background).foregroundStyle(p.ink).saturation(
      m.accent ? 1 : 0)
  }
  func leftovers(_ app: CatalogApp) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(m.t("Review leftovers", "Rever resíduos")).font(.system(size: 24, weight: .semibold))
        Spacer()
        Button(m.t("Done", "Concluído")) { m.leftoverApp = nil }.buttonStyle(GlassButtonStyle())
          .disabled(m.busy)
      }
      Text(app.name).fontWeight(.semibold)
      Text(
        m.t(
          "Exact bundle paths only. Personal data can include settings and saved content. Containers and shared resources stay protected. Nothing is selected automatically.",
          "Apenas caminhos exatos associados ao bundle. Os dados pessoais podem incluir definições e conteúdo guardado. Os contentores e recursos partilhados ficam protegidos. Nada é selecionado automaticamente."
        )
      ).foregroundStyle(p.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(m.leftoverReport.items) { item in
            HStack(alignment: .top) {
              Toggle(
                isOn: Binding(
                  get: { m.leftoverSelection.contains(item.id) },
                  set: {
                    if $0 {
                      m.leftoverSelection.insert(item.id)
                    } else {
                      m.leftoverSelection.remove(item.id)
                    }
                  })
              ) { EmptyView() }.toggleStyle(.checkbox).labelsHidden().disabled(
                !item.selectable || m.installed(app) || m.busy
              ).accessibilityLabel(item.url.lastPathComponent)
              VStack(alignment: .leading, spacing: 6) {
                Text(item.url.path).font(.system(size: 11, design: .monospaced)).textSelection(
                  .enabled)
                Text(itemSummary(item)).font(.system(size: 11)).foregroundStyle(p.secondary)
              }
            }.padding(13).glass()
          }
          if m.leftoverReport.items.isEmpty {
            Text(
              m.t(
                "No candidates found in the reviewed locations. This does not prove that all traces are absent.",
                "Nenhum candidato nos locais revistos. Isto não prova a ausência de todos os vestígios."
              )
            ).foregroundStyle(p.secondary)
          }
          ForEach(m.leftoverReport.warnings, id: \.self) {
            Text($0).font(.system(size: 10, design: .monospaced))
          }
        }
      }.frame(minHeight: 100, maxHeight: 280)
      if m.installed(app) {
        Text(
          m.t(
            "An installed copy still uses these data. Cleanup is blocked.",
            "Uma cópia instalada ainda utiliza estes dados. A limpeza está bloqueada.")
        ).fontWeight(.medium)
      }
      if !m.leftoverResult.isEmpty { Text(m.leftoverResult).font(.system(size: 12)) }
      if m.cleanupConfirm {
        Text(
          m.t(
            "Move the selected items, including any personal data, to Trash? You can restore them from Trash.",
            "Mover os itens selecionados, incluindo eventuais dados pessoais, para o Lixo? Podes restaurá-los a partir do Lixo."
          )
        ).fontWeight(.medium)
        HStack {
          button(m.t("Back", "Voltar")) { m.cleanupConfirm = false }
          button(m.t("Move to Trash", "Mover para o Lixo"), prominent: true) { m.cleanup() }
        }
      } else {
        button(m.t("Review selected cleanup", "Rever a limpeza selecionada"), prominent: true) {
          m.cleanupConfirm = true
        }.disabled(m.leftoverSelection.isEmpty || m.busy || m.installed(app))
      }
    }.padding(26).frame(width: 660).background(p.background).foregroundStyle(p.ink).saturation(
      m.accent ? 1 : 0
    ).interactiveDismissDisabled(m.busy)
  }
  func itemSummary(_ item: Leftover) -> String {
    let size = ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)
    let count = "\(item.files) " + m.t("files", "ficheiros")
    return [kind(item.kind), count, size, item.complete ? "" : m.t("partial", "parcial")].filter {
      !$0.isEmpty
    }.joined(separator: " · ")
  }
  func kind(_ kind: DataKind) -> String {
    switch kind {
    case .personal: return m.t("Personal data", "Dados pessoais")
    case .regenerable: return m.t("Regenerable files", "Ficheiros regeneráveis")
    case .shared:
      return m.t(
        "Protected container / potentially shared",
        "Contentor protegido / potencialmente partilhado")
    }
  }
}
