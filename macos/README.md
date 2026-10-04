# 1nstall para macOS — prévia 0.2.0

Implementação nativa em desenvolvimento em SwiftUI e AppKit, desenvolvida num M4 Pro com 24 GB e macOS Tahoe 26.5.2. Conserva a estrutura visual da 1nstall Windows 3.5.0. A versão Windows e o seu processo de compilação não foram modificados.

## Abrir e utilizar

Abre `1nstall Mac Preview.app`. A app entregue é arm64, com assinatura local ad hoc; ainda não está assinada para distribuição nem notarizada.

- **Instalar:** pesquisa com ⌘F, explora dez subcategorias em quatro grupos e seleciona apps ou um perfil. A pesquisa e os filtros são conservados separadamente entre Install e Uninstall. Revê a lista antes de iniciar. Apps detetadas no Mac aparecem atenuadas.
- **Catálogo:** 15 entradas, incluindo cinco casks revistos (IINA, Rectangle, Keka, LocalSend e VLC). As outras dez abrem o fabricante ou a App Store. Abrir uma página não conta como instalação confirmada.
- **Perfis:** seis perfis com revisão, contagem de apps disponíveis e escolha entre acrescentar ou substituir a seleção, além de importação/exportação JSON. Um perfil não instala nada por si. As entradas já instaladas são excluídas da nova seleção.
- **Desinstalar:** grelha com a mesma geometria dos cartões Install e inventário real em `/Applications`, `~/Applications` e `/System/Applications`, incluindo pastas de fabricantes até três níveis, sem contar apps internas/auxiliares como apps independentes. A remoção automática está limitada às instalações feitas por esta prévia. Outras apps têm acesso ao Finder e, quando há uma associação revista, análise de resíduos.
- **Fila:** etapas por app, progresso por apps processadas, parar após a app atual, verificação e resultados persistentes. As apps confirmadas saem da seleção; limpar os resultados conserva o histórico. A nova tentativa prepara uma seleção para revisão, sem executar. Um arranque após interrupção mostra esse estado e nunca o transforma em sucesso. Não há percentagens de descarga inventadas.
- **Resíduos:** revisão independente; ficheiros regeneráveis, dados pessoais e contentores protegidos. Nada pré-selecionado. Uma app ainda instalada/em execução, inventário parcial, symlinks ou ficheiros alterados após análise bloqueiam a limpeza. Os itens aprovados vão para o Lixo. O tamanho é lógico e não significa espaço físico já libertado.
- **Definições:** Sistema/Claro/Escuro, accent do macOS, opção monocromática, movimento reduzido e Português (Portugal)/English. A redução de movimento do sistema prevalece.
- **Janelas e menus:** ⌘Q, ⌘W, ⌘M, ⌘F, ⌘, e ⌘R; ⌘1/2/3 para Install, Uninstall e Histórico; fechar, minimizar e ecrã completo. Fechar/sair durante uma operação é bloqueado para preservar a fila. A app respeita o gestor de janelas existente; numa largura pequena, a grelha usa duas colunas e a barra de pesquisa pode ocupar duas linhas.

Preferências em `UserDefaults` do bundle `com.braga1k.1nstall.mac.preview`. Seleções, recibos e resultados em `~/Library/Application Support/1nstall-mac-preview/state.json`; registo técnico em `operations.log`. A app não envia estes dados para um serviço.

## Compilar

Requer macOS, Swift 6 e o SDK macOS. Nesta máquina bastaram as Command Line Tools; não foi instalado o Xcode completo. Homebrew só é necessário para executar as instalações automáticas.

```sh
./macos/scripts/build-app.sh /caminho/para/entrega
```

O script compila em release, inclui os recursos no bundle, reutiliza o ícone original e aplica assinatura ad hoc. Não altera `/Applications`, não publica e não configura atualizações automáticas.

## Verificar

```sh
swift run --package-path macos OneInstallChecks
swift run --package-path macos 1nstall --ui-checks
```

As Command Line Tools locais não incluem XCTest. 19 verificações do núcleo e 10 de estado da interface passaram nesta iteração. As verificações são executadas por um pequeno runner Swift autónomo, com falha do processo quando uma asserção falha. Incluem inventário, associação e medição dos resíduos, symlinks, revisão obsoleta, proteção de cópias/contentores, ida e recuperação do Lixo, persistência, argumentos de processos, timeout e casks alterados/privilegiados. Apenas criam fixtures próprias.

Ensaio real opcional, explicitamente delimitado a uma **pasta nova** em `work/`, com Rectangle e IINA ausentes do Mac:

```sh
ONEINSTALL_LIVE_TEST_APPDIR="$PWD/work/disposable-apps-new" \
  swift run --package-path macos OneInstallChecks
```

Instala e remove apenas essas duas apps; não usa `--zap` nem inicia as apps. Antes de cada instalação, o motor recusa uma cópia/registo já existente. A remoção confirma o registo Homebrew, o bundle e a ausência de cópias nas localizações analisadas. O ensaio pode demorar ao processar itens de início de sessão do Rectangle.

Capturas reproduzíveis, com dados de seleção de demonstração e interface sempre inglesa:

```sh
'/caminho/1nstall Mac Preview.app/Contents/MacOS/1nstall' \
  --capture '/caminho/para/capturas'
```

Gera 18 imagens inglesas de Install, Uninstall, Definições, subcategorias, fila e janela mínima. A remoção usa dados de demonstração explícitos, nunca o inventário pessoal. Captura a composição SwiftUI real num painel AppKit de 1240 × 840 pontos (1040 × 640 para a janela mínima), em Retina 2×, sem depender do gestor de janelas. Não é uma captura do compositor nem um teste de movimentos. Não lê o inventário pessoal nem altera preferências/seleções guardadas nesse modo. As imagens de comparação estão em `docs/images/`.

## Limites e continuidade

É uma prévia funcional, não uma release Mac com paridade total. A fidelidade foi comparada nas quatro aparências; a fonte é a San Francisco do sistema, o catálogo é próprio e os controlos da janela estão no lado esquerdo. A linguagem de movimento inicial inclui pressão, seleção, filtros/navegação, luz do rato e brilho global após confirmação; inclui agora entrada dos painéis e transferência de cápsulas entre cartão e seleção. Os tempos e a sensação completa da versão Windows ainda precisam de afinação.

Faltam catálogo mais amplo, manutenção periódica dos metadados, instaladores especiais/permissões administrativas, remoção de apps anteriores à prévia, recuperação orientada de instalações parciais, mais caminhos de resíduos com prova de propriedade, testes em outras versões/macOS/arquiteturas, auditoria completa de acessibilidade, assinatura/notarização e atualizador da própria app. Nem a análise vazia nem a saída zero do Homebrew prometem ausência universal de resíduos. A versão Windows pública mantém-se 3.5.0.

A referência Mole foi estudada sem incorporar código. Ver [pesquisa e limites](docs/RESEARCH.md) e [validação](docs/VALIDATION.md).
