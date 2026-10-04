import AppKit
import OneInstallCore
import SwiftUI

struct ContentView: View {
  @ObservedObject var m: AppModel
  @Environment(\.colorScheme) var systemScheme
  @FocusState var searchFocused: Bool
  @State var activity = false
  @State var appeared = false
  @State var activeProfile = Library.profiles[0].id
  @State var addProfile = false
  var p: Palette {
    Palette(
      dark: m.theme == "dark" || (m.theme == "system" && systemScheme == .dark), accent: m.accent,
      demo: m.capture)
  }
  var body: some View {
    let _ = PerformanceHarness.root()
    ZStack {
      p.background
      RadialGradient(
        colors: [p.action.opacity(p.dark ? 0.1 : 0.12), .clear], center: .topLeading,
        startRadius: 10, endRadius: 850)
      HStack(spacing: 20) {
        navigation.frame(width: 246).offset(x: appeared || m.reduced ? 0 : -12)
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
        .modifier(PageArrival(page: m.page, reduced: m.reduced))
        if m.page == "install" || m.page == "uninstall" {
          selection.frame(width: 246).offset(x: appeared || m.reduced ? 0 : 12)
        }
      }.padding(12).opacity(appeared || m.capture || m.reduced ? 1 : 0)
      if m.successPulse {
        RoundedRectangle(cornerRadius: 26).stroke(p.action.opacity(0.65), lineWidth: 5).blur(
          radius: 18
        ).padding(12).allowsHitTesting(false)
      }
    }
    .overlay {
      PointerTracking(enabled: !m.reduced && !m.capture)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
    .coordinateSpace(name: "surface")
    .overlayPreferenceValue(SelectionAnchors.self) { anchors in
      GeometryReader { geometry in
        if let event = m.selectionEvent, !m.reduced,
          let origin = anchors["card-" + event.app.id], let destination = anchors["selection"]
        {
          let card = geometry[origin]
          let selection = geometry[destination]
          let a = CGPoint(x: card.midX, y: card.midY)
          let b = CGPoint(x: selection.midX, y: selection.minY + 180)
          SelectionFlight(event: event, start: event.adding ? a : b, end: event.adding ? b : a).id(
            event.id)
        }
      }.allowsHitTesting(false)
    }
    .ignoresSafeArea()
    .onAppear {
      if m.capture || m.reduced {
        appeared = true
      } else {
        withAnimation(.easeOut(duration: 0.55)) { appeared = true }
      }
    }
    .foregroundStyle(p.ink).font(.system(size: 13))
    .environment(\.palette, p).environmentObject(m)
    .preferredColorScheme(m.theme == "system" ? nil : (m.theme == "dark" ? .dark : .light))
    .tint(p.action)
    .saturation(m.accent ? 1 : 0)
    .frame(minWidth: 1040, minHeight: 640)
    .animation(
      m.reduced ? nil : .spring(response: 0.32, dampingFraction: 0.86),
      value: m.state.installSelection
    )
    .animation(
      m.reduced ? nil : .spring(response: 0.32, dampingFraction: 0.86),
      value: m.state.removalSelection
    )
    .animation(m.reduced ? nil : .easeInOut(duration: 0.2), value: m.category)
    .animation(m.reduced ? nil : .easeInOut(duration: 0.22), value: m.expandedGroups)
    .animation(m.reduced ? nil : .easeInOut(duration: 0.20), value: activity)
    .sheet(isPresented: $m.profilePicker) {
      profilePicker.environment(\.palette, p).environmentObject(m)
    }
    .sheet(item: $m.installedDetail) { app in
      installedDetails(app).environment(\.palette, p).environmentObject(m)
    }
    .sheet(item: $m.detailApp) { app in details(app).environment(\.palette, p).environmentObject(m)
    }
    .sheet(isPresented: $m.review) { review.environment(\.palette, p).environmentObject(m) }
    .sheet(item: $m.leftoverApp) { app in
      leftovers(app).environment(\.palette, p).environmentObject(m)
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("1nstall.search"))) {
      _ in searchFocused = true
    }
    .environment(\.motionReduced, m.reduced)
    .environment(\.pointerLighting, !m.capture || PerformanceHarness.enabled)
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
      }.frame(height: 64, alignment: .top)
      VStack(spacing: 5) {
        button(m.t("Install", "Instalar"), selected: m.page == "install") {
          m.changePage("install")
        }
        button(m.t("Uninstall", "Desinstalar"), selected: m.page == "uninstall") {
          m.changePage("uninstall")
          m.refreshIfStale()
        }
        button(
          m.t("History & diagnostics", "Histórico e diagnóstico"), selected: m.page == "history"
        ) { m.changePage("history") }
      }
      VStack(alignment: .leading, spacing: 8) {
        Text(m.page == "uninstall" ? m.t("INSTALLED", "INSTALADAS") : m.t("LIBRARY", "BIBLIOTECA"))
          .font(.system(size: 11, weight: .regular))
        Text(
          m.page == "uninstall"
            ? "\(filteredInventory.count) "
              + (filteredInventory.count == 1
                ? m.t("app shown", "app apresentada") : m.t("apps shown", "apps apresentadas"))
            : m.categoryName(m.category) + " · \(filtered.count) "
              + (filtered.count == 1 ? "app" : "apps")
        ).font(.system(size: 11))
      }.foregroundStyle(p.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(
        .horizontal, 8
      ).padding(.top, 22).padding(.bottom, 12)
      if m.page == "install" || m.page == "uninstall" {
        ScrollView {
          VStack(spacing: 8) {
            Button {
              m.category = "all"
            } label: {
              Text(m.t("All apps", "Todas as apps")).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(GlassButtonStyle(selected: m.category == "all", compact: true)).padding(
              .bottom, 2)
            ForEach(Library.groups) { group in
              VStack(spacing: 4) {
                Button {
                  if !m.expandedGroups.insert(group.id).inserted {
                    m.expandedGroups.remove(group.id)
                  }
                } label: {
                  HStack {
                    Text(m.t(group.english, group.portuguese))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                      .rotationEffect(.degrees(m.expandedGroups.contains(group.id) ? 90 : 0))
                  }.padding(.horizontal, 10).frame(height: 43)
                }.buttonStyle(CardPressStyle()).glass(radius: 12, quiet: true)
                  .accessibilityValue(
                    m.expandedGroups.contains(group.id)
                      ? m.t("Expanded", "Expandido") : m.t("Collapsed", "Recolhido"))
                if m.expandedGroups.contains(group.id) {
                  VStack(spacing: 2) {
                    categoryRow(group.id, name: m.t("All in this group", "Todas deste grupo"))
                    ForEach(Library.categories.filter { $0.group == group.id }) { category in
                      categoryRow(category.id, name: m.t(category.english, category.portuguese))
                    }
                  }.padding(.leading, 8).transition(
                    .opacity.combined(with: .offset(y: m.reduced ? 0 : -5)))
                }
              }
            }
          }.padding(.vertical, 4)
        }.scrollIndicators(.hidden)
      }
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
          Circle().stroke(p.secondary.opacity(0.4), lineWidth: 0.6)
        ).contentShape(Circle())
    }.buttonStyle(.plain).accessibilityLabel(label).help(label)
  }
  var library: some View {
    VStack(spacing: 14) {
      HStack(spacing: 8) {
        Button(m.t("All apps", "Todas as apps")) { m.installedOnly = false }.buttonStyle(
          GlassButtonStyle(selected: !m.installedOnly, compact: true))
        Button(
          m.page == "uninstall"
            ? m.t("Removable apps", "Apps removíveis") : m.t("Installed", "Instaladas")
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
            .contentShape(Rectangle())
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
      }.glass(radius: 14, quiet: true).padding(.bottom, 5)
    }
  }
  var searchField: some View {
    ZStack {
      // A button also claims clicks in the padding of a draggable AppKit window.
      Button {
        searchFocused = true
      } label: {
        Color.clear.contentShape(Capsule())
      }.buttonStyle(.plain).accessibilityHidden(true)
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass").foregroundStyle(p.secondary)
        TextField(m.t("Search apps · ⌘F", "Pesquisar apps · ⌘F"), text: $m.search).textFieldStyle(
          .plain
        ).focused($searchFocused).accessibilityLabel(m.t("Search apps", "Pesquisar apps"))
        Button {
          m.search = ""
        } label: {
          Image(systemName: "xmark").font(.system(size: 10))
            .frame(width: 22, height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(m.t("Clear search", "Limpar pesquisa"))
      }.padding(.horizontal, 13)
    }.frame(height: 42).glass(radius: 22, control: true)
  }
  @ViewBuilder var profileTools: some View {
    if m.page == "install" {
      Button(m.t("All profiles", "Perfis")) { m.profilePicker = true }
        .buttonStyle(GlassButtonStyle(compact: true)).fixedSize().disabled(m.busy)
      Menu {
        Button(m.t("Save selection…", "Guardar seleção…")) { m.saveProfile() }
        Button(m.t("Load profile…", "Carregar perfil…")) { m.loadProfile() }
      } label: {
        Text(m.t("User profiles", "Os meus perfis")).foregroundStyle(p.ink)
      }.menuStyle(.button).buttonStyle(GlassButtonStyle(compact: true))
        .fixedSize().disabled(m.busy)
    }
    Button(m.t("Clear selection", "Limpar seleção")) { m.clear() }.buttonStyle(
      GlassButtonStyle(compact: true)
    ).fixedSize().disabled(m.busy)
  }
  var filtered: [CatalogApp] {
    m.apps.filter {
      Library.matches($0.category, filter: m.category) && (!m.installedOnly || m.installed($0))
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
    return ZStack(alignment: .bottomLeading) {
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
                RoundedRectangle(cornerRadius: 6).fill(
                  installed ? p.secondary.opacity(0.20) : p.action)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                  .foregroundStyle(installed ? p.ink : p.actionText)
                  .transition(.scale.combined(with: .opacity))
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
        }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 72)
          .padding(.horizontal, 13).padding(.top, 17)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .contentShape(RoundedRectangle(cornerRadius: 18))
      }.buttonStyle(CardPressStyle()).disabled(installed || m.busy).accessibilityLabel(app.name)
        .accessibilityValue(
          installed
            ? m.t("Installed", "Instalada")
            : selected ? m.t("Selected", "Selecionada") : m.t("Not selected", "Não selecionada"))
      Button {
        m.detailApp = app
      } label: {
        Text(m.t("Details", "Detalhes")).font(.system(size: 11)).frame(maxWidth: .infinity).frame(
          height: 27)
      }.buttonStyle(CardPressStyle()).glass(radius: 16, control: true)
        .padding(.horizontal, 13).padding(.trailing, 22).padding(.bottom, 17)
    }.frame(height: 140).glass(radius: 18, selected: selected)
      .saturation(installed ? 0 : 1).opacity(installed ? 0.62 : 1)
      .anchorPreference(key: SelectionAnchors.self, value: .bounds) { ["card-" + app.id: $0] }
  }
  var filteredInventory: [InstalledApp] {
    m.inventory.apps.filter { installed in
      let catalog = m.apps.first { $0.bundleID == installed.bundleID }
      return (m.search.isEmpty || installed.name.localizedCaseInsensitiveContains(m.search))
        && (m.category == "all"
          || catalog.map { Library.matches($0.category, filter: m.category) } == true)
        && (!m.installedOnly || RemovalEngine.protection(installed) == nil)
    }
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
      if m.page == "install" {
        button(m.t("Save selection…", "Guardar seleção…")) { m.saveProfile() }.disabled(m.busy)
      }
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
                  .frame(width: 22, height: 22).contentShape(Rectangle())
              }.buttonStyle(.plain).disabled(m.busy).accessibilityLabel(
                m.t("Remove ", "Retirar ") + app.name)
            }.padding(.vertical, 12).transition(
              .opacity.combined(with: .offset(x: m.reduced ? 0 : 14)))
          }
          if !m.state.queue.isEmpty { queueResults }
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
            "Remove installed apps, including apps outside the catalog. Data gets a separate review.",
            "Remove apps instaladas, incluindo apps fora do catálogo. Os dados têm uma revisão separada."
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
        ) { m.beginReview() }.disabled(m.selectedApps.isEmpty || m.preparingRemoval)
      }
      Button {
        m.changePage("history")
      } label: {
        Text(m.t("Open logs", "Abrir registos")).frame(maxWidth: .infinity).padding(.top, 14)
          .contentShape(Rectangle())
      }.buttonStyle(.plain).font(.system(size: 12))
    }.padding(.horizontal, 18).padding(.top, 25).padding(.bottom, 22).glass(radius: 26, panel: true)
      .anchorPreference(key: SelectionAnchors.self, value: .bounds) { ["selection": $0] }
  }
  var line: some View { Rectangle().fill(p.separator).frame(height: 1) }
  var settings: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text(m.t("Settings", "Definições")).font(.system(size: 26, weight: .regular))
          .padding(.bottom, 10)
        settingsCard(
          m.t("Theme", "Tema"),
          subtitle: m.t(
            "Choose the appearance of 1nstall.", "Escolhe a aparência da 1nstall.")
        ) {
          Menu {
            ForEach(["system", "light", "dark"], id: \.self) { value in
              Button {
                m.theme = value
              } label: {
                if m.theme == value {
                  Label(themeName(value), systemImage: "checkmark")
                } else {
                  Text(themeName(value))
                }
              }
            }
          } label: {
            settingsChoice(themeName(m.theme))
          }
          .menuStyle(.button).buttonStyle(GlassButtonStyle(compact: true, cornerRadius: 12))
          .accessibilityLabel(m.t("Theme", "Tema")).accessibilityValue(themeName(m.theme))
        }
        settingsCard(
          m.t("Accent colour", "Cor de destaque"),
          subtitle: m.t(
            "Turn off for black and white, keeping gradients and depth.",
            "Desliga para preto e branco, mantendo os gradientes e a profundidade.")
        ) {
          Toggle(m.t("Use macOS accent colour", "Usar a cor de destaque do macOS"), isOn: $m.accent)
            .toggleStyle(.checkbox)
        }
        settingsCard(
          m.t("Language", "Idioma"),
          subtitle: m.t(
            "Changes apply immediately.", "As alterações são aplicadas de imediato.")
        ) {
          Menu {
            Button("Português (Portugal)") { m.language = "pt-PT" }
            Button("English") { m.language = "en" }
          } label: {
            settingsChoice(m.pt ? "Português (Portugal)" : "English")
          }
          .menuStyle(.button).buttonStyle(GlassButtonStyle(compact: true, cornerRadius: 12))
          .accessibilityLabel(m.t("Language", "Idioma"))
          .accessibilityValue(m.pt ? "Português (Portugal)" : "English")
        }
        settingsCard(
          m.t("Motion", "Movimento"),
          subtitle: m.t(
            "The system's Reduce Motion preference is always respected.",
            "A preferência Reduzir movimento do sistema é sempre respeitada.")
        ) {
          Toggle(m.t("Reduce motion", "Reduzir movimento"), isOn: $m.lessMotion)
            .toggleStyle(.checkbox)
        }
        settingsCard(m.t("About", "Sobre"), subtitle: "1nstall Mac Preview 0.3.0 · Apple Silicon") {
          Text(
            m.t(
              "\(m.apps.count) curated entries · \(m.apps.filter(\.automatic).count) reviewed Homebrew installers.",
              "\(m.apps.count) entradas selecionadas · \(m.apps.filter(\.automatic).count) instalações Homebrew revistas."
            )
          )
          .foregroundStyle(p.secondary)
          Text(
            m.t(
              "Development preview. App updates will arrive in a future version.",
              "Prévia de desenvolvimento. As atualizações da app chegarão numa próxima versão.")
          )
          .foregroundStyle(p.secondary)
          HStack(spacing: 8) {
            Button("GitHub") {
              NSWorkspace.shared.open(URL(string: "https://github.com/braga1k/1nstall")!)
            }
            .buttonStyle(GlassButtonStyle(compact: true))
            Button(m.t("Report a problem", "Comunicar um problema")) {
              NSWorkspace.shared.open(URL(string: "https://github.com/braga1k/1nstall/issues")!)
            }.buttonStyle(GlassButtonStyle(compact: true))
          }
        }
      }.font(.system(size: 12)).frame(maxWidth: 780, alignment: .leading)
        .padding(.leading, 68).padding(.trailing, 28).padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }.scrollIndicators(.visible)
  }
  func themeName(_ value: String) -> String {
    value == "system"
      ? m.t("System", "Sistema")
      : value == "light" ? m.t("Light", "Claro") : m.t("Dark", "Escuro")
  }
  func settingsChoice(_ title: String) -> some View {
    HStack {
      Text(title)
      Spacer(minLength: 6)
      Image(systemName: "chevron.down").font(.system(size: 9))
    }.frame(width: 168, height: 38).contentShape(RoundedRectangle(cornerRadius: 12))
  }
  func settingsCard<Content: View>(
    _ title: String, subtitle: String, @ViewBuilder content: () -> Content
  )
    -> some View
  {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.system(size: 15, weight: .medium))
      Text(subtitle).font(.system(size: 11)).foregroundStyle(p.secondary)
      content()
    }.frame(maxWidth: .infinity, alignment: .leading).padding(20).glass(radius: 16)
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
                Text(m.issueText(entry.detail)).font(.system(size: 11, design: .monospaced))
                  .textSelection(
                    .enabled)
              }
              if entry.operation == "remove", entry.stage == .succeeded,
                let app = m.identity(for: entry)
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
      Text(
        app.minimumOS == "source"
          ? m.t(
            "Confirm current macOS requirements at the source.",
            "Confirma os requisitos atuais de macOS na fonte.") + " · \(app.architecture)"
          : "macOS ≥ \(app.minimumOS) · \(app.architecture)")
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
            "Apps are moved to Trash, or uninstalled with Homebrew when it owns the bundle. Preferences and support files are kept for a separate review. Quit each app first.",
            "As apps são movidas para o Lixo ou desinstaladas pelo Homebrew quando este gere a instalação. As preferências e o suporte ficam para uma revisão separada. Fecha cada app primeiro."
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
              VStack(alignment: .leading, spacing: 5) {
                Text(app.name)
                if m.page == "uninstall" {
                  Text(app.id).font(.system(size: 10, design: .monospaced)).foregroundStyle(
                    p.secondary
                  ).textSelection(.enabled)
                }
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 4) {
                Text(m.sourceName(app)).font(.system(size: 11)).foregroundStyle(p.secondary)
                if m.page == "uninstall", let issue = m.removalIssues[app.id] {
                  Text(m.issueText(issue)).font(.system(size: 11)).foregroundStyle(p.secondary)
                    .fixedSize(
                      horizontal: false, vertical: true)
                }
              }
            }.padding(14).glass()
          }
        }
      }.frame(maxHeight: 250)
      if m.page == "uninstall", m.preparingRemoval {
        HStack {
          ProgressView().controlSize(.small)
          Text(
            m.t(
              "Checking ownership and removal instructions…",
              "A verificar a origem e as instruções de remoção…"))
        }
      }
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
        ) { m.runQueue() }.disabled(
          m.page == "uninstall"
            && (m.preparingRemoval || !m.removalIssues.isEmpty || m.removalPlans.isEmpty))
      }
    }.padding(28).frame(width: 570).background(p.background).foregroundStyle(p.ink).saturation(
      m.accent ? 1 : 0)
  }
  func leftovers(_ app: RemovalIdentity) -> some View {
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
          "Review each association before removing data. Preferences, support and verified containers may hold personal content. Shared resources stay protected. Nothing is selected automatically.",
          "Revê cada associação antes de remover dados. As preferências, o suporte e os contentores verificados podem guardar conteúdo pessoal. Os recursos partilhados ficam protegidos. Nada é selecionado automaticamente."
        )
      ).foregroundStyle(p.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(m.leftoverReport.items) { item in
            Button {
              if !m.leftoverSelection.insert(item.id).inserted {
                m.leftoverSelection.remove(item.id)
              }
            } label: {
              HStack(alignment: .top, spacing: 12) {
                Image(
                  systemName: m.leftoverSelection.contains(item.id)
                    ? "checkmark.square.fill" : item.selectable ? "square" : "lock"
                )
                .font(.system(size: 17)).foregroundStyle(p.secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: 6) {
                  Text(item.url.path).font(.system(size: 11, design: .monospaced))
                    .multilineTextAlignment(.leading)
                  Text(itemSummary(item)).font(.system(size: 11)).foregroundStyle(p.secondary)
                  Text(association(item.reason)).font(.system(size: 10)).foregroundStyle(
                    p.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
              }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(CardPressStyle()).glass(selected: m.leftoverSelection.contains(item.id))
              .disabled(!item.selectable || m.installed(app) || m.busy)
              .accessibilityLabel(item.url.lastPathComponent + " · " + itemSummary(item))
              .accessibilityValue(
                m.leftoverSelection.contains(item.id)
                  ? m.t("Selected", "Selecionado") : m.t("Not selected", "Não selecionado"))
          }
          if m.leftoverScanning {
            HStack(spacing: 10) {
              ProgressView().controlSize(.small)
              Text(m.t("Reviewing associated locations…", "A analisar os locais associados…"))
            }
          } else if m.leftoverReport.items.isEmpty {
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
      if !m.leftoverScanning {
        let selected = m.leftoverReport.items.filter { m.leftoverSelection.contains($0.id) }
        Text(
          "\(selected.count) "
            + (selected.count == 1
              ? m.t("item selected", "item selecionado")
              : m.t("items selected", "itens selecionados")) + " · "
            + ByteCountFormatter.string(
              fromByteCount: selected.reduce(0) { $0 + $1.bytes }, countStyle: .file)
        )
        .font(.system(size: 12, weight: .medium)).monospacedDigit()
      }
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
  func association(_ reason: String) -> String {
    switch reason {
    case "system":
      return m.t(
        "System-wide resource. Needs a dedicated removal handler; kept here.",
        "Recurso disponível para todo o sistema. Precisa de um método de remoção específico; preservado aqui."
      )
    case "name":
      return m.t(
        "Exact app name; review the contents before removing.",
        "Nome exato da app; revê o conteúdo antes de remover.")
    case "sharedName":
      return m.t(
        "Name is shared or may belong to a suite; protected.",
        "Nome partilhado ou associado a uma família de apps; protegido.")
    case "container":
      return m.t(
        "Container metadata matches this app's identifier.",
        "Os metadados do contentor correspondem ao identificador da app.")
    case "unverifiedContainer":
      return m.t(
        "Container ownership is not verified; protected.",
        "A origem do contentor não foi confirmada; protegido.")
    case "group":
      return m.t(
        "Application group from the app's signature; may be shared.",
        "Grupo de aplicações identificado na assinatura; pode ser partilhado.")
    case "launchAgent":
      return m.t(
        "Background service points inside this app; it will be stopped first.",
        "Serviço em segundo plano aponta para esta app; será parado primeiro.")
    default: return m.t("Exact application identifier.", "Identificador exato da aplicação.")
    }
  }
  func itemSummary(_ item: Leftover) -> String {
    let size = ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)
    let count =
      "\(item.files) " + (item.files == 1 ? m.t("file", "ficheiro") : m.t("files", "ficheiros"))
    return [kind(item.kind), count, size, item.complete ? "" : m.t("partial", "parcial")].filter {
      !$0.isEmpty
    }.joined(separator: " · ")
  }
  func kind(_ kind: DataKind) -> String {
    switch kind {
    case .system: return m.t("System resource · protected", "Recurso do sistema · protegido")
    case .personal: return m.t("Personal data", "Dados pessoais")
    case .regenerable: return m.t("Regenerable files", "Ficheiros regeneráveis")
    case .shared:
      return m.t(
        "Protected container / potentially shared",
        "Contentor protegido / potencialmente partilhado")
    }
  }
}
