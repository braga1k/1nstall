import Foundation

extension AppModel {
  func issueText(_ text: String) -> String {
    guard pt else { return text }
    return Self.removalMessages[text] ?? text
  }
  private static let removalMessages: [String: String] = [
    "A reviewed path is a symbolic link or changed location.":
      "Um caminho revisto é uma ligação simbólica ou mudou de localização.",
    "The reviewed metadata is too large.": "Os metadados revistos são demasiado grandes.",
    "A service directory is a symbolic link. Review its location first.":
      "Uma pasta de serviços é uma ligação simbólica. Revê primeiro a sua localização.",
    "Several files claim the same background service. Resolve the conflict first.":
      "Vários ficheiros identificam o mesmo serviço em segundo plano. Resolve primeiro o conflito.",
    "The background service state could not be verified.":
      "Não foi possível verificar o estado do serviço em segundo plano.",
    "A loaded service belongs to another executable. It was preserved.":
      "Um serviço carregado pertence a outro executável. Foi preservado.",
    "The background service changed after review.":
      "O serviço em segundo plano mudou após a revisão.",
    "The background service could not be stopped. Its app was preserved.":
      "Não foi possível parar o serviço em segundo plano. A app foi preservada.",
    "Another copy uses the background services. Review the copies together.":
      "Outra cópia utiliza os serviços em segundo plano. Revê as cópias em conjunto.",
    "The app changed or started while services were stopping. Review again.":
      "A app mudou ou foi aberta enquanto os serviços paravam. Revê novamente.",
    "Administrator authorisation is required.": "É necessária autorização de administrador.",
    "Administrator authorisation was cancelled. No success was recorded.":
      "A autorização de administrador foi cancelada. Não foi registado sucesso.",
    "The administrative result could not be verified.":
      "Não foi possível verificar o resultado administrativo.",
    "The administrative component is missing.": "Falta o componente administrativo.",
    "The administrative request is too large.": "O pedido administrativo é demasiado grande.",
    "Unable to prepare native authorisation.": "Não foi possível preparar a autorização nativa.",
    "The app signature is invalid. Rebuild before requesting authorisation.":
      "A assinatura da app é inválida. É necessário recompilar antes de pedir autorização.",
    "The recovery directory is a symbolic link.": "A pasta de recuperação é uma ligação simbólica.",
    "The recovery destination could not be verified.":
      "Não foi possível verificar o destino de recuperação.",
    "The reviewed file changed before removal.": "O ficheiro revisto mudou antes da remoção.",
    "The recovery item or destination changed. Existing files were preserved.":
      "O item de recuperação ou o destino mudou. Os ficheiros existentes foram preservados.",
    "The restored app could not be verified.": "Não foi possível verificar a app restaurada.",
    "Invalid recovery request.": "Pedido de recuperação inválido.",
    "Invalid administrative request.": "Pedido administrativo inválido.",
    "Invalid service plan.": "Plano de serviços inválido.",
    "The installed app name changed after review.":
      "O nome da app a instalar mudou após a revisão.",
    "Invalid service scope.": "Âmbito de serviço inválido.",
    "The account for this removal could not be verified.":
      "Não foi possível verificar a conta para esta remoção.",
    "The account's home directory could not be verified.":
      "Não foi possível verificar a pasta pessoal da conta.",
    "Homebrew or services require their reviewed removal method.":
      "O Homebrew ou os serviços requerem o método de remoção revisto.",
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
