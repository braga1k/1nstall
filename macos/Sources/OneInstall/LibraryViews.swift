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

  var uninstallList: some View {
    ScrollView {
      LazyVStack(spacing: 8) {
        ForEach(filteredInventory) { app in installedRow(app) }
      }.padding(.bottom, 4)
      if filteredInventory.isEmpty {
        VStack(spacing: 12) {
          Image(systemName: m.scanning ? "app.badge.checkmark" : "list.bullet.rectangle").font(
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

  func installedRow(_ installed: InstalledApp) -> some View {
    let managed = RemovalEngine.protection(installed) == nil
    let selected = m.state.removalSelection.contains(installed.path)
    return ZStack(alignment: .trailing) {
      Button {
        if managed { m.toggleRemoval(installed) } else { m.installedDetail = installed }
      } label: {
        HStack(spacing: 12) {
          ZStack {
            RoundedRectangle(cornerRadius: 5).stroke(
              p.secondary.opacity(managed ? 0.7 : 0.35), lineWidth: 1)
            if selected {
              RoundedRectangle(cornerRadius: 5).fill(p.action)
              Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(p.actionText)
            } else if !managed {
              Image(systemName: "info").font(.system(size: 10)).foregroundStyle(p.secondary)
            }
          }.frame(width: 18, height: 18)
          VStack(alignment: .leading, spacing: 6) {
            Text(installed.name).font(.system(size: 13)).lineLimit(1)
            Text(
              (installed.version.isEmpty ? "" : installed.version + " · ")
                + m.removalName(installed)
            ).font(.system(size: 10.5)).foregroundStyle(p.secondary).lineLimit(1)
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.leading, 16).padding(.trailing, 102)
          .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
          .contentShape(RoundedRectangle(cornerRadius: 18))
      }.buttonStyle(CardPressStyle()).disabled(m.busy)
        .accessibilityLabel(installed.name).accessibilityValue(
          managed
            ? selected ? m.t("Selected", "Selecionada") : m.t("Not selected", "Não selecionada")
            : m.removalName(installed))
      Button {
        m.installedDetail = installed
      } label: {
        Text(m.t("Details", "Detalhes")).font(.system(size: 11)).frame(width: 74, height: 30)
      }.buttonStyle(CardPressStyle()).glass(radius: 16, control: true).padding(.trailing, 16)
    }.frame(height: 70).glass(radius: 18, selected: selected)
      .anchorPreference(key: SelectionAnchors.self, value: .bounds) { anchor in
        return ["card-" + installed.path: anchor]
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
      Text(m.removalName(installed)).fontWeight(.medium)
      if RemovalEngine.protection(installed) == nil {
        Text(
          m.t(
            "Select this app to review its removal. The queue verifies the selected bundle and keeps personal data for a separate review.",
            "Seleciona esta app para rever a remoção. A fila verifica a aplicação selecionada e preserva os dados pessoais para uma revisão separada."
          ))
        Button(
          m.state.removalSelection.contains(installed.path)
            ? m.t("Remove from selection", "Retirar da seleção")
            : m.t("Select for removal", "Selecionar para remoção")
        ) {
          m.toggleRemoval(installed)
          m.installedDetail = nil
        }.buttonStyle(GlassButtonStyle(prominent: true)).disabled(m.busy)
        if !NSRunningApplication.runningApplications(withBundleIdentifier: installed.bundleID)
          .isEmpty
        {
          Button(m.t("Quit app normally", "Fechar a app normalmente")) {
            for process in NSRunningApplication.runningApplications(
              withBundleIdentifier: installed.bundleID)
            { process.terminate() }
          }.buttonStyle(GlassButtonStyle()).disabled(m.busy)
          Text(
            m.t(
              "Unsaved changes may need your attention in that app.",
              "As alterações por guardar podem precisar da tua atenção nessa app.")
          ).font(.system(size: 11)).foregroundStyle(p.secondary)
        }
      } else {
        Text(
          m.t(
            "This application is protected and cannot be removed here.",
            "Esta aplicação está protegida e não pode ser removida aqui."))
      }
      HStack {
        Button(m.t("Show in Finder", "Mostrar no Finder")) {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: installed.path)])
        }.buttonStyle(GlassButtonStyle())
        if RemovalEngine.protection(installed) == nil {
          Button(m.t("Review leftovers", "Rever resíduos")) {
            m.installedDetail = nil
            // Present after the current sheet has dismissed; there is never a second modal underneath it.
            Task {
              try? await Task.sleep(for: .milliseconds(250))
              m.scanLeftovers(installed)
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
        ScrollView {
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
          }
        }.frame(width: 185, height: 330)
        ScrollView {
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
          }
        }.frame(maxWidth: .infinity).frame(height: 330)
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
            Button(
              entry.stage == .succeeded
                ? m.t("View result", "Ver resultado") : m.t("View issue", "Ver problema")
            ) { m.changePage("history") }.buttonStyle(
              .plain
            ).font(.system(size: 11)).underline()
          }
          if entry.recoveryPath != nil {
            Button(m.t("Restore app", "Restaurar app")) { m.restoreApp(entry) }
              .buttonStyle(GlassButtonStyle(compact: true)).disabled(m.busy)
          }
          if entry.operation == "remove", entry.stage == .succeeded,
            let app = m.identity(for: entry)
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
