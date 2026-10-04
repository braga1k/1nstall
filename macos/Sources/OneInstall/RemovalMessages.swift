import Foundation

extension AppModel {
  func issueText(_ text: String) -> String {
    guard pt else { return text }
    return Self.removalMessages[text] ?? text
  }
  private static let removalMessages: [String: String] = [
    "This application is protected.": "Esta aplicação está protegida.",
    "The selected app's location or identity changed. Refresh and review again.":
      "A localização ou a identidade da app mudou. Atualiza o inventário e revê novamente.",
    "The app's identity file is a symbolic link.":
      "O ficheiro de identidade da app é uma ligação simbólica.",
    "Homebrew is unavailable.": "O Homebrew não está disponível.",
    "Homebrew ownership could not be confirmed.":
      "Não foi possível confirmar que o Homebrew gere esta instalação.",
    "Homebrew's installed receipt is missing.": "Falta o registo de instalação do Homebrew.",
    "Homebrew's installed metadata is unreadable or unsafe.":
      "Não é possível ler os metadados de instalação do Homebrew com segurança.",
    "This Homebrew app uses uninstall scripts that require a dedicated review.":
      "Esta app do Homebrew usa scripts de desinstalação que precisam de uma revisão específica.",
    "Homebrew's installed cask definition is missing.":
      "Falta a definição do cask instalado pelo Homebrew.",
    "Homebrew's recorded uninstall instructions are incomplete.":
      "As instruções de remoção guardadas pelo Homebrew estão incompletas.",
    "This Homebrew app includes package or script actions. A dedicated uninstall handler is required.":
      "Esta app do Homebrew inclui pacotes ou scripts. Precisa de um método de desinstalação específico.",
    "This Homebrew uninstaller changes services or external files. Those actions need a dedicated review.":
      "Este desinstalador do Homebrew altera serviços ou ficheiros externos. Essas ações precisam de uma revisão específica.",
    "This cask owns several app bundles. Review the whole package first.":
      "Este cask gere várias aplicações. É necessário rever o pacote completo primeiro.",
    "This app includes system extensions. Its supported uninstaller must deactivate them first.":
      "Esta app inclui extensões do sistema. O desinstalador compatível tem de as desativar primeiro.",
    "More than one cask claims this app. Resolve Homebrew ownership first.":
      "Há vários casks associados a esta app. Resolve a origem no Homebrew primeiro.",
    "The app changed after review. Create a fresh removal plan.":
      "A app mudou após a revisão. Revê a remoção novamente.",
    "Quit this app before removing it. Unsaved work has been preserved.":
      "Fecha esta app antes de a remover. O trabalho por guardar foi preservado.",
    "The removal method changed after review. Review again.":
      "O método de remoção mudou após a revisão. Revê novamente.",
    "The app changed during preparation.": "A app mudou durante a preparação.",
    "Homebrew did not complete removal. Inspect the log; no fallback deletion was attempted.":
      "O Homebrew não concluiu a remoção. Consulta o registo; a 1nstall não tentou uma remoção alternativa.",
    "Homebrew still records this cask, or its state could not be verified.":
      "O Homebrew ainda regista este cask ou não foi possível verificar o seu estado.",
    "The app's destination in Trash could not be verified.":
      "Não foi possível verificar o destino da app no Lixo.",
    "The app is still present at the selected location.":
      "A app continua na localização selecionada.",
    "The app was moved, but inventory verification is incomplete. Refresh to inspect the result.":
      "A app foi movida, mas a verificação do inventário está incompleta. Atualiza para consultar o resultado.",
    "An installed or running copy still uses these data.":
      "Uma cópia instalada ou em execução ainda utiliza estes dados.",
    "Protected, shared or unreviewed path.": "Caminho protegido, partilhado ou por rever.",
    "Files changed after review. Scan again.":
      "Os ficheiros mudaram após a revisão. Analisa novamente.",
    "The launch agent changed after review.": "O serviço de arranque mudou após a revisão.",
    "The background service could not be stopped. Its file was preserved.":
      "Não foi possível parar o serviço em segundo plano. O ficheiro foi preservado.",
    "The background service state is unknown. Its file was preserved.":
      "O estado do serviço em segundo plano é desconhecido. O ficheiro foi preservado.",
    "The background service is still registered.": "O serviço em segundo plano continua registado.",
    "Files changed while the background service was stopping. Review again.":
      "Os ficheiros mudaram enquanto o serviço parava. Revê novamente.",
    "Moving to Trash was not confirmed.": "Não foi possível confirmar a passagem para o Lixo.",
  ]
}
