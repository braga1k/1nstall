import AppKit
import OneInstallCore
import SwiftUI

extension ContentView {
  func categoryRow(_ id: String, name: String) -> some View {
    let count =
      m.page == "uninstall"
      ? m.inventory.apps.filter { installed in
        m.apps.contains {
          $0.bundleID == installed.bundleID && Library.matches($0.category, filter: id)
        }
      }.count
      : m.apps.filter { Library.matches($0.category, filter: id) }.count
    return Button {
      m.category = id
    } label: {
      HStack {
        Text(name).lineLimit(2).multilineTextAlignment(.leading)
        Spacer(minLength: 5)
        Text("\(count)").font(.system(size: 10)).foregroundStyle(p.secondary)
      }.padding(.horizontal, 10).padding(.vertical, 8).frame(minHeight: 33)
        .background(
          RoundedRectangle(cornerRadius: 9).fill(m.category == id ? p.action.opacity(0.18) : .clear)
        )
    }.buttonStyle(CardPressStyle()).accessibilityAddTraits(m.category == id ? .isSelected : [])
  }

  var uninstallGrid: some View {
    GeometryReader { geometry in
      ScrollView {
        LazyVGrid(
          columns: Array(
            repeating: GridItem(.flexible(), spacing: 8), count: geometry.size.width < 560 ? 2 : 3),
          spacing: 8
        ) {
          ForEach(filteredInventory) { app in installedCard(app) }
        }.padding(.bottom, 4)
        if filteredInventory.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: m.scanning ? "app.badge.checkmark" : "square.grid.2x2").font(
              .system(size: 25)
            ).accessibilityHidden(true)
            Text(
              m.scanning
                ? m.t("Reading app bundles…", "A ler as aplicações…")
                : m.t("No apps match these filters.", "Nenhuma app corresponde a estes filtros."))
            if !m.search.isEmpty || m.category != "all" || m.installedOnly {
              Button(m.t("Reset filters", "Repor filtros")) {
                m.search = ""
                m.category = "all"
                m.installedOnly = false
              }.buttonStyle(GlassButtonStyle())
            }
          }.foregroundStyle(p.secondary).frame(maxWidth: .infinity).padding(.top, 50)
        }
      }.scrollIndicators(.visible)
    }
  }

  func installedCard(_ installed: InstalledApp) -> some View {
    let catalog = m.apps.first { $0.bundleID == installed.bundleID }
    let managed = catalog.map { m.state.receipts[$0.id] == installed.path } ?? false
    let selected = catalog.map { m.state.removalSelection.contains($0.id) } ?? false
    return VStack(alignment: .leading, spacing: 7) {
      Button {
        if managed, let catalog { m.toggle(catalog) } else { m.installedDetail = installed }
      } label: {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .top) {
            Text(installed.name).font(.system(size: 13)).lineLimit(2).multilineTextAlignment(
              .leading)
            Spacer(minLength: 3)
            ZStack {
              RoundedRectangle(cornerRadius: 6).stroke(
                p.secondary.opacity(managed ? 0.7 : 0.25), lineWidth: 1)
              if selected {
                RoundedRectangle(cornerRadius: 6).fill(p.action)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                  .foregroundStyle(p.actionText)
              } else if !managed {
                Image(systemName: "info").font(.system(size: 10)).foregroundStyle(p.secondary)
              }
            }.frame(width: 18, height: 18)
          }
          Spacer(minLength: 4)
          VStack(alignment: .leading, spacing: 3) {
            Text(installed.version)
            Text(
              managed
                ? m.t("Homebrew · managed", "Homebrew · gerida")
                : installed.store
                  ? m.t("App Store · guided removal", "App Store · remoção guiada")
                  : m.t("Installed · guided removal", "Instalada · remoção guiada"))
          }.font(.system(size: 10.5)).foregroundStyle(p.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 72).contentShape(
          Rectangle())
      }.buttonStyle(CardPressStyle()).disabled(m.busy)
        .accessibilityLabel(installed.name).accessibilityValue(
          managed
            ? selected ? m.t("Selected", "Selecionada") : m.t("Not selected", "Não selecionada")
            : m.t("Guided removal", "Remoção guiada"))
      Button {
        m.installedDetail = installed
      } label: {
        Text(m.t("Details", "Detalhes")).font(.system(size: 11)).frame(maxWidth: .infinity).frame(
          height: 27)
      }.buttonStyle(CardPressStyle()).glass(radius: 16, control: true).padding(.trailing, 22)
    }.padding(13).frame(height: 140).glass(radius: 18, selected: selected)
      .anchorPreference(key: SelectionAnchors.self, value: .bounds) { anchor in
        guard let catalog else { return [:] }
        return ["card-" + catalog.id: anchor]
      }
  }

  func installedDetails(_ installed: InstalledApp) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text(installed.name).font(.system(size: 26, weight: .semibold))
        Spacer()
        Button(m.t("Done", "Concluído")) { m.installedDetail = nil }.buttonStyle(GlassButtonStyle())
      }
      Text(m.t("Installed version: ", "Versão instalada: ") + installed.version)
      Text(installed.bundleID).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
        .foregroundStyle(p.secondary)
      Text(installed.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
      line
      if installed.path.hasPrefix("/System/") {
        Text(
          m.t(
            "Included with macOS. This app is protected and is not offered for removal.",
            "Incluída no macOS. Esta app está protegida e não é disponibilizada para remoção."))
      } else if let catalog = m.apps.first(where: { $0.bundleID == installed.bundleID }),
        m.state.receipts[catalog.id] == installed.path
      {
        Text(
          m.t(
            "Installed by 1nstall. Select this app to review its removal in the queue.",
            "Instalada pela 1nstall. Seleciona esta app para rever a remoção na fila."))
      } else {
        Text(
          m.t(
            "This preview does not own this installation. Open its location and use Finder or the manufacturer's uninstaller.",
            "Esta instalação não foi feita pela prévia. Abre a localização e utiliza o Finder ou o desinstalador do fabricante."
          ))
      }
      HStack {
        Button(m.t("Show in Finder", "Mostrar no Finder")) {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: installed.path)])
        }.buttonStyle(GlassButtonStyle())
        if let catalog = m.apps.first(where: { $0.bundleID == installed.bundleID }) {
          Button(m.t("Review leftovers", "Rever resíduos")) {
            m.installedDetail = nil
            // Present after the current sheet has dismissed; there is never a second modal underneath it.
            Task {
              try? await Task.sleep(for: .milliseconds(250))
              m.scanLeftovers(catalog)
            }
          }.buttonStyle(GlassButtonStyle()).disabled(m.busy)
        }
      }
    }.padding(28).frame(width: 570).background(p.background).foregroundStyle(p.ink).saturation(
      m.accent ? 1 : 0)
  }

  var profilePicker: some View {
    let profile = Library.profiles.first { $0.id == activeProfile } ?? Library.profiles[0]
    let apps = profile.apps.compactMap { id in m.apps.first { $0.id == id } }
    let eligible = Library.selectable(profile.apps, catalog: m.apps, installed: m.inventory.apps)
    return VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text(m.t("Choose a profile", "Escolher um perfil")).font(
          .system(size: 26, weight: .semibold))
        Spacer()
        Button(m.t("Done", "Concluído")) { m.profilePicker = false }.buttonStyle(GlassButtonStyle())
      }
      Text(
        m.t(
          "A starting point for your selection. Installed apps are skipped.",
          "Um ponto de partida para a seleção. As apps instaladas são ignoradas.")
      ).foregroundStyle(p.secondary)
      HStack(alignment: .top, spacing: 18) {
        VStack(spacing: 7) {
          ForEach(Library.profiles) { item in
            Button {
              activeProfile = item.id
            } label: {
              Text(m.t(item.english, item.portuguese)).frame(
                maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(GlassButtonStyle(selected: item.id == activeProfile))
          }
        }.frame(width: 185)
        VStack(alignment: .leading, spacing: 14) {
          ForEach(apps) { app in
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                Text(m.sourceName(app)).font(.system(size: 11)).foregroundStyle(p.secondary)
              }
              Spacer()
              if m.installed(app) {
                Text(m.t("Installed", "Instalada")).font(.system(size: 11)).foregroundStyle(
                  p.secondary)
              }
            }.padding(12).glass()
          }
        }.frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
      }
      Toggle(m.t("Add to current selection", "Acrescentar à seleção atual"), isOn: $addProfile)
        .toggleStyle(.checkbox)
      Text(
        "\(eligible.count) "
          + (eligible.count == 1
            ? m.t("app available to select", "app disponível para selecionar")
            : m.t("apps available to select", "apps disponíveis para selecionar"))
      ).font(.system(size: 12)).foregroundStyle(p.secondary)
      HStack {
        Text(
          m.t(
            "Nothing is installed until you review and confirm.",
            "Nada é instalado antes da revisão e confirmação.")
        ).font(.system(size: 11)).foregroundStyle(p.secondary)
        Spacer()
        Button(m.t("Apply profile", "Aplicar perfil")) {
          m.applyProfile(profile, adding: addProfile)
        }.buttonStyle(GlassButtonStyle(prominent: true)).disabled(m.busy || eligible.isEmpty)
      }
    }.padding(28).frame(width: 680).background(p.background).foregroundStyle(p.ink).saturation(
      m.accent ? 1 : 0)
  }

  var queueResults: some View {
    let summary = QueueSummary(m.state.queue)
    return VStack(alignment: .leading, spacing: 14) {
      line
      HStack {
        Text(m.busy ? m.t("IN PROGRESS", "EM CURSO") : m.t("QUEUE RESULTS", "RESULTADOS DA FILA"))
          .font(.system(size: 10, weight: .medium)).foregroundStyle(p.secondary)
        Spacer()
        Text("\(summary.completed)/\(summary.total)").monospacedDigit().font(.system(size: 10))
          .foregroundStyle(p.secondary)
      }
      ForEach(m.state.queue) { entry in
        VStack(alignment: .leading, spacing: 7) {
          HStack {
            Text(entry.name)
            Spacer()
            Image(
              systemName: entry.stage == .succeeded
                ? "checkmark.circle"
                : entry.stage == .failed || entry.stage == .interrupted
                  ? "exclamationmark.circle"
                  : entry.stage == .guided ? "arrow.up.right.circle" : "circle.dotted"
            )
            .foregroundStyle(p.secondary)
          }
          Text(m.resultLabel(entry)).font(.system(size: 11)).foregroundStyle(p.secondary)
          if !entry.stage.terminal {
            HStack(spacing: 4) {
              ForEach(
                Array(
                  [
                    QueueStage.preparing, entry.operation == "remove" ? .removing : .installing,
                    .verifying,
                  ].enumerated()), id: \.offset
              ) { _, stage in
                Capsule().fill(entry.stage == stage ? p.action : p.separator.opacity(0.45)).frame(
                  height: 3)
              }
            }.accessibilityHidden(true)
          }
          if !entry.detail.isEmpty {
            Button(m.t("View issue", "Ver problema")) { m.changePage("history") }.buttonStyle(
              .plain
            ).font(.system(size: 11)).underline()
          }
          if entry.operation == "remove", entry.stage == .succeeded,
            let app = m.apps.first(where: { $0.id == entry.appID })
          {
            Button(m.t("Review leftovers", "Rever resíduos")) { m.scanLeftovers(app) }.buttonStyle(
              GlassButtonStyle(compact: true)
            ).disabled(m.busy)
          }
        }.padding(.vertical, 3)
      }
      if !m.busy {
        if m.state.queue.contains(where: { [.failed, .stopped, .interrupted].contains($0.stage) }) {
          Button(m.t("Prepare retry", "Preparar nova tentativa")) { m.prepareRetry() }.buttonStyle(
            GlassButtonStyle(compact: true))
        }
        Button(m.t("Clear results", "Limpar resultados")) { m.clearResults() }.buttonStyle(.plain)
          .font(.system(size: 11)).foregroundStyle(p.secondary)
          .help(m.t("History is kept", "O histórico é mantido"))
      }
    }
  }
}
