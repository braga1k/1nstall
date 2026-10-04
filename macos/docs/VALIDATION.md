# Validação — 04/10/2026

## Iteração 0.2.1 — resposta imediata e Uninstall em lista

Base local limpa `4955f33e76c7c09f4def93b0bc72b0c05cd8bb38`. `main` e `v3.5.0` remotos voltaram a ser confirmados em `db4931e533aa951f7ff564555714ac38497ba20c`. Apenas `macos/` alterado; sem push/release.

- **Pedido confirmado:** rapidez sem retirar animações; Install → Uninstall parecia aguardar a animação. Pedido posterior: Uninstall em lista, seguindo Windows. Implementadas linhas de 70 pontos com seleção, nome, versão, origem/tipo de remoção e detalhes; referência `docs/images/3.5/uninstall-dark.png`.
- **Navegação:** destino aplicado imediatamente, entrada suave de 200 ms interrompível, sem hierarquia de saída a bloquear os novos controlos. Luz do rato em camadas Core Animation, sem atualizar o estado global; estilos isolados das alterações não visuais do modelo. Inventário recente reutilizado na navegação durante 30 s; atualização explícita e verificação de operações mantidas.
- **Compilação:** release arm64 com Swift 6.3.1/SDK 26.4.1, sem avisos; assinatura ad hoc verificada. Nenhum Xcode completo ou dependência adicional instalado.
- **19 verificações do núcleo + 10 de estado + 11 de composição/movimento**, zero falhas. A composição testa substituição do destino aos 40 ms, animação ativa, nova navegação e pesquisa antes de acabar, redução de movimento, luz visível/em movimento e overlays sem captura de cliques. Os testes usam fixtures e preservam o estado real.
- **Benchmark:** duas execuções release por versão com catálogo fixo/200 bundles fictícios; hover físico suprimido de igual forma para estabilizar o ensaio. Movimento do rato em Install/Uninstall passa de 120 avaliações da raiz a zero; camadas luminosas verificadas como visíveis. Medianas e todos os resultados, incluindo fases sem melhoria, em `PERFORMANCE.md` e JSON da entrega. CPU não é FPS nem latência clique/píxel.
- **Interface nativa antes da última alteração de disposição:** alternância por atalhos/cliques, pesquisa e filtros conservados, seleção existente e fila visíveis; tracking nativo registou luz ativa. A tentativa final de verificar cliques/deslocação na lista foi interrompida porque o Mac ficou bloqueado. Foi pedido desbloqueio; essa confirmação nativa permanece pendente, distinta dos testes de composição que passaram.
- **20 capturas inglesas:** quatro aparências, Uninstall em lista, seleção/resultado com fixtures e tamanhos mínimos de ambos os modos. Inspeção visual da lista normal e mínima; comparações Install e Uninstall com Windows. Seis monocromáticas com diferença RGB máxima 1 e zero píxeis acima de 1. Capturas não expõem o inventário pessoal.
- **Preservação:** seleção Final Cut Pro existente observada; não foi iniciada instalação/remoção nesta correção. Não se repetiu o ciclo Homebrew real da 0.2.0, porque o motor não foi alterado. Catálogo permanece 15 entradas/5 casks; remoção automática mantém os limites anteriores. Versões 0.1/0.2 preservadas.

Continua uma prévia local, sem Developer ID/notarização. Ficam por ampliar catálogo, remoção anterior à prévia, resíduos e cobertura; pesquisa/seleção ainda têm custo a melhorar. A validação da 0.2.0 abaixo é histórica e não substitui os limites desta iteração.

## Iteração 0.2.0 — aproximação à experiência Windows

Esta iteração parte do commit local `77142d85a797c14eda337162138a01ce277ff2dd`, com checkout limpo. `main` e `v3.5.0` remotos continuavam em `db4931e533aa951f7ff564555714ac38497ba20c`. O trabalho permanece apenas em `macos/`, sem publicar.

### O que mudou e foi verificado

- Painéis de 246 pontos e intervalos de 20: alinhamentos medidos nas referências Windows 1240×840. Separados os materiais de painel, cartão, controlo e grupo; contornos dos cartões e grupos mais discretos, gradientes com vários pontos, bevel interno e botões de detalhes com a largura da referência. A fonte continua San Francisco, sem alegar equivalência píxel a píxel.
- Grelha Uninstall com cartões de 140 pontos, seleção da cópia efetivamente gerida e ficha de detalhes. As restantes instalações continuam num percurso guiado. Apps em `/System/` são identificadas como protegidas na ficha; não foi ampliada a autoridade de remoção.
- Dez subcategorias dentro de quatro grupos expansíveis. Contagens calculadas sobre os dados reais, filtro pelo grupo/categoria, pesquisa e filtros independentes conservados na navegação. Atalhos ⌘1/2/3 e ⌘R acrescentados aos menus nativos.
- Seis perfis com revisão da lista, contagem elegível e opção de acrescentar/substituir. Na interface real, o perfil Ficheiros reconheceu LocalSend/Keka já instalados e desativou Aplicar; o perfil Estúdio criativo acrescentou apenas Blender, preservando a seleção IINA existente. A seleção inicial foi reposta após o ensaio.
- Entrada dos painéis, pressão dos cartões, expansão, transições e cápsula de seleção com percurso entre cartão e painel. Luz calculada a partir da posição global real do rato e das dimensões de cada superfície, em vez do divisor fixo 240×160 anterior. Atualização limitada a 60 eventos/s, sem temporizador de animação permanente. Redução de movimento corta trajetos, offsets e luz móvel; alterações de acessibilidade do sistema são observadas. Sem benchmark de FPS ou auditoria VoiceOver integral.
- Resultados da fila com contador processado/total e indicação de etapa real. As operações confirmadas retiram a app da seleção, conservando a fila e o histórico. Limpar resultados não apaga o histórico; preparar nova tentativa não executa operações. Callbacks antigos não podem reverter uma entrada já concluída.
- Corrigida seleção de remoção obsoleta, observada na interface: um inventário completo reconcilia seleções com identidade/caminho/recibo. Inventários parciais não apagam seleções. Resíduos apresentam estado de análise e total dos itens selecionados, sem anunciar análise vazia antes de acabar.

### Testes desta iteração

- **19 verificações do núcleo e 10 verificações do estado da interface, zero falhas.** Novos cenários cobrem ligações catálogo/categorias/perfis, exclusão por bundle mesmo com nome diferente, progresso sem falso sucesso, cópias geridas desaparecidas, filtros independentes, perfis aditivos, nova tentativa sem executar e histórico preservado. Os testes do estado usam modo isolado e confirmam que não sobrescrevem o ficheiro real.
- **Novo ciclo nativo IINA 1.5.0:** revisão → instalação → verificação → seleção vazia; Uninstall → filtro Geridas → seleção → revisão → remoção → verificação → seleção vazia, grelha gerida vazia e fila conservada. Revisão de resíduos encontrou zero candidatos nos locais previstos; não foi executada limpeza. Bundle e comando IINA ausentes no fim; lista de casks igual à registada imediatamente antes do ensaio (LocalSend). Nenhuma app pessoal foi usada como alvo de teste.
- Navegação pelos atalhos e regresso ao filtro Leitores multimédia confirmados na interface. Perfis foram testados sem iniciar operações. O teste posterior de IINA foi iniciado separadamente na revisão de instalação. Idioma inglês, tema Sistema e accent escolhidos no estado existente foram preservados.
- **18 capturas inglesas:** Install, Uninstall e Definições nas quatro aparências; filas, subcategorias e janela mínima em claro/escuro. Uninstall usa fixtures explícitas; as imagens não expõem o inventário pessoal nem provam operações reais. Capturas de composição NSHostingView; os testes nativos são evidência separada.
- Seis imagens monocromáticas verificadas em toda a superfície: diferença máxima RGB 1, zero píxeis acima de 1, zero falhas; a medição acompanha a entrega. Comparação Windows 3.5.0 → Mac 0.1.0 → Mac 0.2.0 em `images/comparison.png`.
- Compilação release arm64 e assinatura ad hoc verificadas. Continua sem Developer ID/notarização. A suite de instalação Rectangle/IINA da primeira iteração não foi repetida integralmente; nesta iteração repetiu-se o ciclo nativo IINA.

### Limites atuais

O catálogo mantém 15 apps/5 casks automáticos; não foi fingida expansão do catálogo por acrescentar categorias ou perfis. Remoção de instalações anteriores, catálogos amplos, instaladores especiais, recuperação orientada e mais associações de resíduos continuam por implementar. A matriz em `PARITY.md` separa resultados atuais de trabalho futuro. Não foi incorporado código Mole, alterado o Windows ou publicado conteúdo.

## Validação da primeira implementação 0.1.0 — histórico

## Base preservada e ambiente

`main`, `HEAD` remoto e `v3.5.0` confirmados em `db4931e533aa951f7ff564555714ac38497ba20c` antes de clonar. Não existia um checkout local da 1nstall nos diretórios pesquisados. Criado `work/1nstall`, branch `macos/native-preview`. Todos os acrescentos ficam em `macos/`; nenhum ficheiro Windows foi modificado. Não houve push nem release.

Hardware confirmado: Apple M4 Pro, 25 769 803 776 bytes de RAM (24 GiB), arm64. Sistema: macOS 26.5.2, build 25F84. Swift 6.3.1, SDK macOS das Command Line Tools, Homebrew 7.0.1 em `/opt/homebrew/bin/brew`. Xcode completo ausente. A app foi compilada em release e a assinatura ad hoc passou `codesign --verify --deep --strict`. A assinatura ad hoc não é assinatura Developer ID nem notarização.

## Interface e comparação

- App nativa aberta e operada no Mac. Navegação, pesquisa com ⌘F, seleção/remoção individual, revisão, categorias, perfis, definições, idioma e ⌘, verificados pela interface e árvore de acessibilidade.
- Perfil Dia a dia selecionou IINA/Rectangle e excluiu o LocalSend já instalado. Exportação JSON confirmada, seleção limpa e perfil carregado novamente, sem iniciar instalações. Corrigida a abertura dos painéis após sair do menu nativo e a associação `.json` a ferramentas criativas deste Mac.
- Estado da fila preservado após revisão de resíduos, mudança de página, fecho e novo arranque. Resultados distinguem instalação e remoção.
- Quatro capturas inglesas da composição real em painel AppKit fixo: 1240 × 840 pontos, Retina 2480 × 1680. Comparação com `docs/images/3.5` da versão Windows em `images/comparison.png`. Preservados painéis laterais simétricos de 244 pontos, espaçamentos de 20, cartões de 140, grelha de três colunas à largura de referência, pills, gradientes e identidade do símbolo original.
- Diferenças assumidas: San Francisco em vez de Segoe UI, controlos da janela no lado esquerdo, atalhos Command, catálogo e perfis Mac. Não é equivalência píxel a píxel. O movimento completo da versão Windows ainda não foi reproduzido.
- Monocromia das duas imagens: diferença máxima RGB 1 em 255; zero píxeis com diferença superior a 1. O resíduo de um nível é quantização/gestão de cor, sem matiz visível. Verificação inclui toda a composição, não apenas amostras.
- Tema claro/escuro, accent ligado/desligado, preferências persistentes, redução de movimento e mudança inglês/pt-PT operados na app. A regra de redução do sistema também é consultada no código; não se alterou a preferência global do Mac.
- A largura real imposta pelo AeroSpace usa a variante de duas colunas e barra de pesquisa adaptável. Não foram alteradas as configurações desse gestor de janelas. Sem auditoria completa de VoiceOver, contraste ou todas as escalas/janelas.

## Operações reais

1. Rectangle 2.0.2 e IINA 1.5.0 instalados pelo mesmo `BrewEngine` usado na app, em pasta nova `work/disposable-apps-01`.
2. Confirmados saída zero, bundle ID e executável com arquitetura arm64. As apps não foram abertas.
3. Removidos pelo Homebrew sem `--zap`. Confirmados registo/caminho e ausência dos bundles; o comando `/opt/homebrew/bin/iina` criado pelo ensaio foi retirado. O Rectangle demorou no processamento de itens de início de sessão, mas terminou sem intervenção nas permissões.
4. Segundo ensaio do IINA pela própria interface: revisão → instalação real em `/Applications` → confirmação → inventário → revisão de remoção → desinstalação → confirmação persistente → revisão de resíduos sem candidatos nos locais delimitados.
5. Resultado final: IINA/Rectangle de teste ausentes. Casks pessoais mantidos: `aerospace 0.21.3-Beta` e `localsend 1.18.2`, como no início. Keka, LocalSend, VLC e restantes apps/projetos pessoais não foram instalados, atualizados ou removidos. O inventário final encontrou 106 bundles nos locais documentados; não é uma contagem universal de software do Mac.

As duas apps reais não criaram dados de utilização porque não foram iniciadas. A remoção e recuperação de resíduos foi testada com fixtures próprias, não com preferências ou projetos pessoais. Os resultados reais de instalação/remoção permanecem no histórico local da prévia.

## Verificações automáticas

15 verificações do runner Swift, zero falhas na execução final:

- Inventário em pastas de fabricantes e exclusão de helpers internos.
- Preservação de cópias distintas com o mesmo bundle ID.
- Associações exatas, contagens e bytes reais.
- Bloqueio de symlinks em antepassados e de árvores com symlinks internos.
- Recusa de uma revisão quando ficheiros mudam entretanto.
- Bloqueio por cópia ainda instalada e proteção de contentores.
- Mover uma fixture para o Lixo, verificar e restaurar o seu conteúdo.
- Persistência após interrupção, sem falso sucesso.
- Argumentos de subprocessos sem interpretação por uma shell; timeout sinalizado.
- Rejeição de remoção sem recibo próprio.
- Rejeição de nova versão, cask desativado e instalador privilegiado não revisto.
- Identidades únicas e checksums das entradas automáticas.

O runner normal não instala apps. O ensaio real é ativado separadamente por uma variável que exige pasta nova em `work/`. As Command Line Tools não fornecem XCTest; não se apresenta o runner como uma execução de XCTest. Sem execução de testes WPF/Win32 neste Mac; a preservação Windows foi verificada pela ausência de diferenças nos seus ficheiros.

## Limites que permanecem

Catálogo inicial; cinco entradas automáticas, apenas duas instaladas/removidas como ensaio. As restantes já existiam no Mac e foram preservadas. Instalações futuras com metadados novos pedem revisão do catálogo. Entradas guiadas não foram instaladas nesta sessão. Não há cobertura de Intel, outros macOS, elevação, serviços privilegiados, instaladores PKG, aplicações complexas ou todas as permissões/TCC.

Desinstalação automática limitada às instalações desta prévia. Limpeza por caminhos exatos revistos, com revisão e Lixo, sem alegar encontrar todos os resíduos. Não existe paridade integral com Mole nem código dele incorporado. Não existem assinatura de distribuição, notarização, atualizador da própria app ou publicação Mac. A linguagem completa de movimento Windows é trabalho seguinte, juntamente com a revisão visual por Vitor.
