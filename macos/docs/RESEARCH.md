# Catálogo macOS — recolha de 04/10/2026

O catálogo desta prévia contém 27 entradas e não pretende representar as aplicações mais usadas no mundo. A investigação de 60 candidatos foi consultada e é conservada em `research/candidates-60.csv`. Os eventos Homebrew de 30/90/365 dias pertencem ao respetivo canal e à participação nas estatísticas; não são utilizadores únicos. A variação de quota da pesquisa inicial não é apresentada como selo de tendência.

As listagens Mac App Store [Portugal](https://apps.apple.com/pt/mac/charts/36) e [EUA](https://apps.apple.com/us/mac/charts/36) complementam o Homebrew. São rankings regionais, momentâneos e sujeitos a cache. Apps como WhatsApp, Microsoft Word, CapCut e Canva reforçam a necessidade de não limitar o futuro catálogo ao público Homebrew; não foram promovidas automaticamente à seleção desta prévia.

## Instalação automática

| App | Versão revista | Método e arquitetura | Requisitos e fonte oficial |
| --- | --- | --- | --- |
| Rectangle | 2.0.2 | Cask; Universal; arm64 verificado no binário instalado | Cask atual ≥ macOS 14; o site ainda refere suporte histórico ≥ 10.15. [Fabricante](https://rectangleapp.com), [Cask](https://formulae.brew.sh/cask/rectangle). |
| IINA | 1.5.0 | Cask; Universal; arm64 verificado no binário instalado | Apple Silicon ≥ macOS 12. [Fabricante](https://iina.io), [Cask](https://formulae.brew.sh/cask/iina). |
| Keka | 1.6.8 | Cask; Universal; instalação não repetida para preservar a cópia pessoal | Site ≥ macOS 10.10; a edição App Store apoia o fabricante. [Fabricante](https://www.keka.io/en/), [release oficial](https://github.com/aonez/Keka/releases/tag/v1.6.8). |
| LocalSend | 1.18.2 | Cask; Universal; instalação não repetida para preservar a cópia pessoal | macOS ≥ 11 confirmado no Info.plist da cópia local 1.18.2; binário Universal. A app pessoal foi apenas lida, não reinstalada. [Fabricante](https://localsend.org/download), [release oficial](https://github.com/localsend/localsend/releases/tag/v1.18.2). |
| VLC | 3.0.24 | Cask específico arm64; instalação não repetida para preservar a cópia pessoal | Usar a variante Apple Silicon; não confundir os mínimos históricos Intel (10.7.5) com o Mac M4. A cópia local 3.0.23 é Universal; não foi atualizada ou reinstalada. [Cask](https://formulae.brew.sh/cask/vlc), [servidor oficial](https://get.videolan.org/vlc/3.0.24/macosx/). A página web VideoLAN recusou a leitura automatizada; metadados Cask e bundle local complementam a verificação. |

Os JSON brutos em `research/` preservam versão, checksum, variantes, requisitos e estado de manutenção. Os cinco casks estavam ativos, sem `deprecated`/`disabled`. O motor consulta novamente os metadados locais Homebrew, recusa casks descontinuados, tipos de instalador não revistos e, na instalação, versões/checksums diferentes dos revistos. Não usa `--force`, `--zap`, `sudo`, atualização automática do Homebrew ou limpeza automática de dependências. Não instala o Homebrew sem pedido.

A verificação não representa uma auditoria dos fabricantes. A app confirma código de saída, identidade do bundle e presença de arm64. A compatibilidade funcional das aplicações, além destes checks, exige utilização própria.

## Entradas guiadas

Blender, Brave, Firefox, Obsidian, Raycast, Spotify e Visual Studio Code usam os links oficiais devolvidos pelo catálogo e cruzados com os JSON Homebrew. A disponibilidade foi consultada, mas esta prévia não testou a instalação dessas sete apps. As variantes de Blender, Raycast e Spotify nos metadados são arm64, não universais. Onde os casks não dão um mínimo e a fonte não permite fixar um valor atual com confiança (Blender, Raycast, VS Code), a interface pede confirmação dos requisitos na fonte; não apresenta um número presumido. O VS Code usa a regra de versões macOS com suporte de segurança Apple, normalmente a atual e duas anteriores. Final Cut Pro, Logic Pro e Motion encaminham para a App Store portuguesa; os JSON Apple Lookup preservam versão e `minimumOsVersion`. Não se inicia uma compra, não se assume uma licença e não se confunde abrir uma página com instalar.

Fontes adicionais: [Firefox](https://www.mozilla.org/firefox/mac/), [Obsidian](https://obsidian.md/download), [Raycast](https://www.raycast.com), [VS Code](https://code.visualstudio.com/docs/supporting/requirements), [Brave](https://brave.com/download/), [Spotify](https://www.spotify.com/download/mac/), [Apple](https://support.apple.com/en-ie/122605), [analytics Homebrew](https://docs.brew.sh/Analytics).

## Ampliação 0.3.0 — 12 novas entradas

Fontes novamente consultadas em 04/10/2026: metadados Homebrew ativos (sem deprecated/disabled), páginas oficiais e, para Slack/Bitwarden, Apple Lookup Portugal. São entradas guiadas de instalação; não se instalaram estas 12 apps. A arquitetura abaixo vem dos metadados/distribuições, não de um ensaio de cada binário. Não constitui um ranking de utilização global ou de tendências.

| App | Versão | Variante / mínimo macOS | Fonte oficial e Homebrew |
|---|---|---|---|
| Google Chrome | 154.0.8037.98 | Universal / ≥ 13 | [Fabricante](https://www.google.com/chrome/), [cask](https://formulae.brew.sh/cask/google-chrome) |
| Notion | 7.36.1 | Apple Silicon / ≥ 12 | [Fabricante](https://www.notion.com/desktop), [cask](https://formulae.brew.sh/cask/notion) |
| LibreOffice | 26.8.0 | Apple Silicon / ≥ 11 | [Fabricante](https://www.libreoffice.org/download/), [cask](https://formulae.brew.sh/cask/libreoffice) |
| Bitwarden | 2026.9.1 | Universal / ≥ 12 | [Fabricante](https://bitwarden.com/download/), [cask](https://formulae.brew.sh/cask/bitwarden) |
| 1Password | 8.12.38 | Apple Silicon / ≥ 12 | [Fabricante](https://1password.com/downloads/mac), [cask](https://formulae.brew.sh/cask/1password) |
| Slack | 4.52.171 | Apple Silicon / ≥ 13 | [Fabricante](https://slack.com/downloads/mac), [cask](https://formulae.brew.sh/cask/slack) |
| Discord | 0.0.414 | Universal / ≥ 12 | [Fabricante](https://discord.com/download), [cask](https://formulae.brew.sh/cask/discord) |
| Signal | 8.29.0 | Apple Silicon / ≥ 13 | [Fabricante](https://signal.org/download/), [cask](https://formulae.brew.sh/cask/signal) |
| Audacity | 4.0.1 | Apple Silicon / mínimo a confirmar na fonte | [Fabricante](https://www.audacityteam.org/download/mac/), [cask](https://formulae.brew.sh/cask/audacity) |
| HandBrake | 1.11.2 | Universal / ≥ 10.13 | [Fabricante](https://handbrake.fr/downloads.php), [cask](https://formulae.brew.sh/cask/handbrake-app) |
| OBS Studio | 32.2.2 | Apple Silicon / ≥ 13 | [Fabricante](https://obsproject.com/download), [cask](https://formulae.brew.sh/cask/obs) |
| Inkscape | 1.4.4 | Apple Silicon / mínimo a confirmar na fonte | [Fabricante](https://inkscape.org/release/inkscape-1.4.4/), [cask](https://formulae.brew.sh/cask/inkscape) |

- Slack e Bitwarden: IDs Apple `803453959` e `1352778147`, bundle/minimumOsVersion/versão cruzados nos JSON guardados. Fontes [Slack](https://slack.com/downloads/mac) e [Bitwarden](https://bitwarden.com/download/).
- LibreOffice: requisitos [oficiais](https://www.libreoffice.org/get-help/system-requirements/); pacote Apple Silicon identificado no cask.
- Discord: requisitos [oficiais](https://support.discord.com/hc/en-us/articles/213491697-What-are-the-OS-system-requirements-for-Discord); a cópia pessoal 0.0.412 foi apenas lida e confirma bundle/mínimo/Universal dessa cópia. Não equivale a testar o novo pacote 0.0.414.
- Signal requer a app no telemóvel; 1Password requer subscrição. Isso consta das descrições.
- Audacity: a distribuição Apple Silicon tem diferenças de suporte de plug-ins; o mínimo permanece por confirmar para a variante concreta. Inkscape: a página de descarga recusou leitura automatizada; cask e anúncio oficial 1.4.4 foram cruzados, mas não se inventou um mínimo.
- O cask gráfico HandBrake é agora `handbrake-app`; `handbrake` designa outra distribuição e a API desse cask devolveu 404. OBS pode instalar componentes adicionais; disponibilidade para instalar pelo site não é validação de uma remoção integral desses componentes.
- Evidência bruta em `research/0.3.0/` (12 casks e dois resultados Apple). As cinco instalações automáticas anteriores não foram ampliadas por esta pesquisa.

## Referência Mole e limites da limpeza

Referência estudada no commit `42b7b8d4c0331fed9c9c01480ec448ef23aabbdd`:

- [Licença GPL-3.0](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/LICENSE).
- [Desenho de segurança](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/docs/SECURITY_DESIGN.md).
- [Proteção de apps e dados](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/lib/core/app_protection.sh).

Não foi copiado, incorporado nem executado código do Mole. A implementação Swift é própria. A licença concreta deve voltar a ser analisada antes de qualquer reutilização. A app gráfica Mole for Mac é um produto separado.

O estudo foi aprofundado na 0.3.0: leitura dos percursos de fila, identidade fixada na revisão, cópias sobreviventes, serviços, associações por nome, origens Homebrew e regras para desinstaladores oficiais. O código Homebrew 7.0.1 instalado também foi consultado para confirmar que a remoção carrega o cask guardado e o `INSTALL_RECEIPT.json`, que podem diferir dos metadados atuais.

A implementação, a matriz de cobertura, os testes e os limites reais estão em [REMOVAL.md](REMOVAL.md). O Uninstall já não exige recibos criados pela 1nstall e os resíduos podem ser revistos para apps fora do catálogo. Recursos partilhados, permissões/serviços privilegiados e percursos especiais não são declarados removidos quando não o foram. Nenhum módulo geral de otimização/monitorização do Mole foi acrescentado.
