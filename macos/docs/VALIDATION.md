# Validação — 04/10/2026

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
