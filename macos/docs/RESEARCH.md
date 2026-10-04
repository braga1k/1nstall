# Catálogo macOS — recolha de 04/10/2026

O catálogo desta prévia contém 15 entradas e não pretende representar as aplicações mais usadas no mundo. A investigação de 60 candidatos foi consultada e é conservada em `research/candidates-60.csv`. Os eventos Homebrew de 30/90/365 dias pertencem ao respetivo canal e à participação nas estatísticas; não são utilizadores únicos. A variação de quota da pesquisa inicial não é apresentada como selo de tendência.

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

## Referência Mole e limites da limpeza

Referência estudada no commit `42b7b8d4c0331fed9c9c01480ec448ef23aabbdd`:

- [Licença GPL-3.0](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/LICENSE).
- [Desenho de segurança](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/docs/SECURITY_DESIGN.md).
- [Proteção de apps e dados](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/lib/core/app_protection.sh).

Não foi copiado, incorporado nem executado código do Mole. A implementação Swift é própria. A licença concreta deve voltar a ser analisada antes de qualquer reutilização. A app gráfica Mole for Mac é um produto separado.

Lições aplicadas: identidade por bundle, deteção de cópias ainda instaladas, bloqueio de apps em execução, validação de caminhos e antepassados sem symlinks, distinção entre dados pessoais e regeneráveis, proteção de contentores e recursos partilhados, medição limitada com avisos de resultados parciais e revisão separada antes de mover dados para o Lixo. Nada é pré-selecionado.

A prévia não pesquisa nomes semelhantes, wildcards `zap`, diretórios globais de fabricantes, Group Containers, documentos ou projetos pessoais. `Application Support/<nome>` só entra para nomes explícitos e revistos por app. A associação exata ainda não prova propriedade exclusiva: a revisão apresenta esse limite. Uma cópia instalada, inventário incompleto, árvore com symlinks, mais de 20 000 entradas ou alteração da árvore após a revisão bloqueia a limpeza. A medição representa bytes lógicos dos ficheiros, não espaço físico recuperável em APFS. Mover para o Lixo não liberta esse espaço imediatamente.

A remoção automática fica limitada às instalações criadas pela própria prévia e cuja identidade/caminho/registo Homebrew são novamente verificados. Outras apps aparecem no inventário, com acesso ao Finder; instaladores especiais, serviços privilegiados e remoção universal ficam para uma fase seguinte. Não foram adicionados os módulos gerais de otimização/monitorização do Mole.
