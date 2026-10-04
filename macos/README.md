# 1nstall para macOS — beta 0.5.0-beta.1

Implementação nativa em desenvolvimento em SwiftUI e AppKit, desenvolvida num M4 Pro com 24 GB e macOS Tahoe 26.5.2. Conserva a estrutura visual da 1nstall Windows 3.5.0. A versão Windows e o seu processo de compilação não foram modificados.

## Beta pública — 0.5.0-beta.1

**112 apps, 25 categorias e 20 perfis.** 33 instalações automáticas revistas pelo Homebrew; as restantes 79 abrem o fabricante ou a Mac App Store. [Guia da beta em inglês](BETA.md) e [catálogo com fontes e limites](docs/SUPPORTED-APPS.md). O Windows 3.5 mantém 325 entradas; ainda não se anuncia equivalência de catálogo ou remoção integral ao Mole.

Maccy e Skim passaram novos ciclos reais em pastas descartáveis, sem abrir as apps. Os 33 percursos automáticos passaram a verificação de versão, checksum e artefacto esperado. Requisitos desconhecidos ficam explicitamente remetidos para a fonte; versões que pedem um macOS mais recente mostram esse aviso na ficha. A interface conserva a lista Uninstall, quatro aparências, animações e cliques completos.

## Permissões, serviços e recuperação — 0.4.0

A remoção nativa já pede autorização de administrador ao macOS quando as permissões normais não chegam. O pedido aparece na janela de autenticação do sistema; a 1nstall não lê nem guarda a palavra-passe. O componente administrativo executa apenas a operação revista, revalida a identidade e termina. Não instala um serviço permanente.

Apps que exigem elevação ficam em **Recuperação da 1nstall**, com restauro pela fila ou pelo Histórico, sem substituir ficheiros existentes. Um diário independente permite reencontrá-las após uma interrupção. Os dados de sistema com associação exata ao bundle ID também podem ser revistos e movidos para Recuperação. Os restantes dados seguem para o Lixo. Ambos continuam a ocupar espaço até serem eliminados pelo utilizador.

Antes de remover a app, o motor identifica serviços cujo executável pertence ao bundle, descarrega os serviços carregados e verifica o resultado. O plano mostra esses serviços. Helpers externos, extensões e desinstaladores especiais continuam a exigir implementação própria: **a equivalência integral ao Mole ainda não está concluída**. A [matriz de remoção](docs/REMOVAL.md) distingue o que funciona e o que falta.

## Remoção real e aproximação visual — 0.3.0

O Uninstall já remove apps anteriores à prévia e fora do catálogo. A seleção identifica a cópia instalada pelo caminho, o plano é revisto antes de executar e o resultado guarda a identidade necessária para analisar os dados depois. Apps comuns e da Store usam o Lixo; instalações Homebrew reconhecidas usam os seus registos e instruções de desinstalação. O sucesso só aparece após verificação. Há casos avançados ainda por implementar: ver [cobertura e limites de remoção](docs/REMOVAL.md).

A revisão de resíduos cobre mais locais, mostra a razão da associação, protege recursos partilhados e conserva quantidades/resultados no histórico. Nada é pré-selecionado. Os cartões são clicáveis em toda a superfície.

Definições com cartões e menus dispostos como no Windows; catálogo com 27 apps, 13 subcategorias e oito perfis. Gradientes, monocromia, luz e movimento preservados. As novas entradas de instalação continuam guiadas até terem o respetivo percurso automático validado; isso não limita a sua remoção se já estiverem instaladas.

## Cliques em toda a superfície — 0.2.2

Corrigidas as áreas de clique dos pills, cartões, linhas e botões de detalhes. As margens e os espaços vazios pertencem agora ao controlo; os detalhes continuam independentes da seleção. A pesquisa recebe foco também ao clicar na cápsula e o menu de perfis tem a mesma área visível e interativa dos outros pills. A reprodução nativa confirmou que na 0.2.1 a margem de Uninstall era ignorada e o texto funcionava; na 0.2.2 ambos funcionam.

A validação usa cliques por coordenadas fora dos textos, além dos testes de estado/composição. Estes últimos, isoladamente, não detetavam este problema. Mantidos as animações, a luz e o Uninstall em lista. Ver [validação](docs/VALIDATION.md).

## Rapidez e movimento — base 0.2.1

O Uninstall usa uma lista de linhas de 70 pontos, como na referência Windows: seleção/identificação à esquerda, nome, versão e tipo de remoção na mesma linha, com acesso aos detalhes. A troca Install/Uninstall aplica-se imediatamente. A página de destino conserva uma entrada suave de 200 ms, interrompível por nova navegação. A página anterior não permanece por cima dos novos controlos. Pressão, hover, cápsula da seleção, expansão e brilho após sucesso continuam presentes.

A luz do rato é agora desenhada em camadas Core Animation, sem atualizar o estado global SwiftUI nem voltar a filtrar/construir o catálogo a cada movimento. Os estilos recebem apenas as preferências visuais de que precisam. A navegação reutiliza o inventário recente durante 30 segundos; ⌘R e a verificação após operações continuam a atualizar diretamente.

Medições e limites em [Desempenho](docs/PERFORMANCE.md). Nessa correção, o catálogo e o âmbito da remoção mantiveram-se iguais aos da 0.2.0; foram ampliados na 0.3.0.

## Abrir e utilizar

Abre `1nstall Mac Preview.app`. A app entregue é arm64, com assinatura local ad hoc; ainda não está assinada para distribuição nem notarizada.

- **Instalar:** pesquisa com ⌘F, explora 25 subcategorias em quatro grupos e seleciona apps ou um perfil. A pesquisa e os filtros são conservados separadamente entre Install e Uninstall. Revê a lista antes de iniciar. Apps detetadas no Mac aparecem atenuadas.
- **Catálogo:** 112 entradas, incluindo 33 casks revistos. As outras 79 abrem o fabricante ou a App Store. Abrir uma página não conta como instalação confirmada.
- **Perfis:** 20 perfis com revisão, contagem de apps disponíveis e escolha entre acrescentar ou substituir a seleção, além de importação/exportação JSON. Um perfil não instala nada por si. As entradas já instaladas são excluídas da nova seleção.
- **Desinstalar:** lista vertical com linhas de 70 pontos e inventário real em `/Applications`, `~/Applications` e `/System/Applications`, incluindo pastas de fabricantes até três níveis, sem contar apps internas/auxiliares como apps independentes. Seleção e remoção de apps comuns, da Store e Homebrew anteriores à prévia, incluindo apps fora do catálogo. Apps protegidas e percursos especiais têm diagnóstico explícito; ver REMOVAL.md para limites e métodos efetivamente suportados.
- **Fila:** etapas por app, progresso por apps processadas, parar após a app atual, verificação e resultados persistentes. As apps confirmadas saem da seleção; limpar os resultados conserva o histórico. A nova tentativa prepara uma seleção para revisão, sem executar. Um arranque após interrupção mostra esse estado e nunca o transforma em sucesso. Não há percentagens de descarga inventadas.
- **Resíduos:** revisão independente; ficheiros regeneráveis, dados pessoais, contentores com identidade confirmada, grupos partilhados protegidos e recursos do sistema com associação explícita. Os recursos exatos elegíveis pedem autorização administrativa e ficam em Recuperação. Nada pré-selecionado. Uma app ainda instalada/em execução, inventário parcial, symlinks ou ficheiros alterados após análise bloqueiam a limpeza. Os itens aprovados vão para o Lixo ou para Recuperação, conforme o percurso indicado na revisão. O tamanho é lógico e não significa espaço físico já libertado.
- **Definições:** Sistema/Claro/Escuro, accent do macOS, opção monocromática, movimento reduzido e Português (Portugal)/English. A redução de movimento do sistema prevalece.
- **Janelas e menus:** ⌘Q, ⌘W, ⌘M, ⌘F, ⌘, e ⌘R; ⌘1/2/3 para Install, Uninstall e Histórico; fechar, minimizar e ecrã completo. Fechar/sair durante uma operação é bloqueado para preservar a fila. A app respeita o gestor de janelas existente; numa largura pequena, a grelha usa duas colunas e a barra de pesquisa pode ocupar duas linhas.

Preferências em `UserDefaults` do bundle `com.braga1k.1nstall.mac.preview`. Seleções, recibos e resultados em `~/Library/Application Support/1nstall-mac-preview/state.json`; registo técnico em `operations.log`. Recuperação fica na subpasta `Recovery`, com registos JSON do caminho original. O Histórico permite restaurar apps; o restauro de dados é manual pela pasta, podendo exigir permissões. Não mover nem apagar essa pasta enquanto contiver itens necessários. A app não envia estes dados para um serviço.

## Compilar

Requer macOS, Swift 6 e o SDK macOS. Nesta máquina bastaram as Command Line Tools; não foi instalado o Xcode completo. Homebrew só é necessário para executar as instalações automáticas.

```sh
./macos/scripts/build-app.sh /caminho/para/entrega
```

O script compila em release a app e o componente administrativo, inclui os recursos no bundle, reutiliza o ícone original e aplica assinatura ad hoc. Não altera `/Applications`, não publica e não configura atualizações automáticas.

## Verificar

```sh
swift run --package-path macos OneInstallChecks
swift run --package-path macos 1nstall --ui-checks
swift run --package-path macos 1nstall --render-checks
```

As Command Line Tools locais não incluem XCTest. Na 0.4.0 passaram 47 verificações do núcleo, 10 de estado e 11 de composição/movimento, além dos ciclos reais descartáveis e da validação da interface descritos em VALIDATION.md. As verificações são executadas por um pequeno runner Swift autónomo, com falha do processo quando uma asserção falha. Incluem inventário, associação e medição dos resíduos, symlinks, revisão obsoleta, proteção de cópias/contentores, ida e recuperação do Lixo, persistência, argumentos de processos, timeout e casks alterados/privilegiados. Apenas criam fixtures próprias.

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

Gera 24 imagens inglesas de Install, Uninstall, Definições, Recuperação, subcategorias, fila e janela mínima em ambos os modos. A remoção usa dados de demonstração explícitos, nunca o inventário pessoal. Captura a composição SwiftUI real num painel AppKit de 1240 × 840 pontos (1040 × 640 para a janela mínima), em Retina 2×, sem depender do gestor de janelas. Não é uma captura do compositor nem um teste de movimentos. Não lê o inventário pessoal nem altera preferências/seleções guardadas nesse modo. As imagens de comparação da entrega incluem Install, Uninstall e Definições. As referências históricas estão em `docs/images/`.

## Limites e continuidade

É uma prévia funcional, não uma release Mac com paridade total. A fidelidade foi comparada nas quatro aparências; a fonte é a San Francisco do sistema, o catálogo é próprio e os controlos da janela estão no lado esquerdo. A linguagem de movimento inicial inclui pressão, seleção, filtros/navegação, luz do rato e brilho global após confirmação; inclui agora entrada dos painéis e transferência de cápsulas entre cartão e seleção. Os tempos e a sensação completa da versão Windows ainda precisam de afinação.

Faltam maior cobertura automática do catálogo, manutenção periódica dos metadados, instaladores especiais, helpers externos e validação administrativa mais ampla, recuperação orientada de instalações parciais, mais caminhos de resíduos com prova de propriedade, testes em outras versões/macOS/arquiteturas, auditoria completa de acessibilidade, assinatura/notarização e atualizador da própria app. Nem a análise vazia nem a saída zero do Homebrew prometem ausência universal de resíduos. A versão Windows pública mantém-se 3.5.0.

A referência Mole foi estudada sem incorporar código. Ver [pesquisa e limites](docs/RESEARCH.md) e [validação](docs/VALIDATION.md).
