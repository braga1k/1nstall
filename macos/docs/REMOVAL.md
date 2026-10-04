# Remoção macOS — estado 0.4.0

O objetivo confirmado por Vitor é atingir a competência de desinstalação do Mole. O encaminhamento generalizado para o Finder deixou de ser o percurso normal. Esta versão amplia a remoção real, mas **ainda não tem paridade total com o Mole**.

## Percursos implementados

| Caso | Comportamento 0.4.0 | Verificação |
|---|---|---|
| App comum anterior à 1nstall, dentro das raízes analisadas | Seleção pelo caminho instalado, revisão e passagem para o Lixo | Identidade e localização antes/depois; destino no Lixo; inventário atualizado |
| App fora do catálogo | Mesmo percurso nativo; não precisa de recibo da 1nstall | Identidade conservada no histórico para rever dados depois de remover |
| App com recibo da App Store | Mesmo percurso nativo quando as permissões permitem | Fixture com estrutura de recibo; não se removeram apps pessoais da Store |
| Homebrew anterior à 1nstall | Prova pelo link exato do Caskroom e `brew list`; instruções da instalação guardadas no cask/INSTALL_RECEIPT | Remove com `brew uninstall --cask`, confirma ausência do bundle e do registo; sem `--zap` |
| Várias cópias do mesmo bundle | Remove apenas a cópia selecionada e indica as sobreviventes | Dados continuam bloqueados enquanto houver uma cópia instalada |
| App em execução | Recusa a remoção; ficha permite pedir encerramento normal | Sem encerramento forçado nem perda deliberada de trabalho por guardar |
| App do sistema ou a própria 1nstall | Proteção explícita | Não aparece como remoção guiada nem como sucesso |
| Permissões insuficientes na remoção nativa | Pedido nativo do macOS; app movida para Recuperação, com restauro | Identidade fixada, revalidação no processo administrativo, destino sem substituição e verificação posterior |
| Serviços com executável dentro do bundle | Revisão dos LaunchAgents/LaunchDaemons associados; parar antes da remoção | Plist e programa exatos, ausência confirmada no launchd; domínio system pede autorização |
| Interrupção/falha | Fila e histórico persistentes, diagnóstico e nova revisão | Reiniciar nunca transforma uma operação incompleta em sucesso |

O plano fixa a identidade do diretório, do pai e do Info.plist, e o conteúdo da identidade da app. A execução verifica novamente os caminhos, a origem Homebrew e as instruções de remoção. Não há fallback para apagar uma app quando o Homebrew falha. A UI mostra o caminho da cópia na revisão. Uma conclusão de remoção significa **remoção do bundle selecionado**, não ausência universal de dados ou componentes externos.

## Resíduos e dados

- Caminhos exatos pelo bundle ID: preferências, ByHost com UUID válido, caches, logs, WebKit, HTTPStorages/cookies, Application Support, scripts, autosave e estado guardado.
- Nomes completos exatos da app/bundle e nomes revistos do catálogo: Application Support, caches e logs. Sem pesquisas vagas por substring, corte de versões, diretórios globais de fabricantes ou dotfiles pessoais. A associação por nome aparece como tal na revisão.
- Colisões de nome com outra app instalada ficam protegidas. Famílias Apple mantêm os diretórios por nome protegidos; só caminhos identificados especificamente podem ser selecionados.
- Contentor individual: só pode ser selecionado quando o `MCMMetadataIdentifier` confirma o bundle. Sem essa prova, fica protegido. Conteúdo pessoal nunca é pré-selecionado.
- Group Containers e scripts de grupos: IDs obtidos dos entitlements de uma assinatura validada; apresentados como potencialmente partilhados e protegidos.
- LaunchAgents do utilizador: o executável tem de apontar literalmente para dentro do bundle selecionado, sem `..`. Antes de mover o plist, o serviço é descarregado e a ausência no launchd é confirmada. O caminho/ficheiro é novamente validado.
- Recursos em `/Library/Preferences`, `/Library/Application Support`, `/Library/Caches` e `/Library/Logs` com nome exatamente igual ao bundle ID (ou ID.plist): medidos e elegíveis para revisão administrativa após a app desaparecer. Nomes de fabricantes, recursos partilhados e plists globais continuam protegidos. Os serviços exatos são descarregados antes de remover o bundle; o plist global não é apagado automaticamente.
- A medição conta ficheiros e bytes lógicos reais, com teto de 20 000 entradas por candidato e indicação de resultados parciais. Symlinks, dados alterados, inventário incompleto, cópia instalada/em execução e caminho reaparecido bloqueiam a limpeza. Uma associação não prova, por si só, exclusividade.
- Os itens selecionados vão para o Lixo; os que usam o componente administrativo ficam em Recuperação. A UI distingue estas quantidades de espaço efetivamente libertado. O resultado da limpeza também fica no histórico. Não se esvazia o Lixo.

## Autorização e recuperação

O componente `Contents/Helpers/1nstall-admin` aceita pedidos estruturados de parar serviços, mover a app/dados revistos e restaurar uma app. Não aceita comandos arbitrários nem tem uma operação de eliminação definitiva. O pedido passa pela autorização nativa do macOS com `NSAppleScript`; a execução fica fora da thread da interface. Cancelar não regista sucesso. O componente valida novamente conta, raízes, identidade, método e associação, rejeita symlinks e move com `renameatx_np` sem substituir o destino. Não muda permissões das apps existentes nem instala um daemon permanente.

O processo administrativo não obteve acesso ao Lixo do utilizador neste Mac. Não se alterou TCC nem se pediu acesso total ao disco para contornar essa restrição. O destino deste percurso é `~/Library/Application Support/1nstall-mac-preview/Recovery`. O diário é escrito antes do movimento; só aparece como recuperável se o destino ainda existir e a identidade da app corresponder. Apps podem ser restauradas pela fila/Histórico, novamente com autorização e verificação. Dados mostram o caminho original e o acesso à pasta; o seu restauro ainda é manual. Os itens continuam a ocupar espaço. Não existe limpeza automática desta pasta nem do Lixo.

A prévia usa assinatura ad hoc e execução administrativa pontual. Uma distribuição pública continua dependente de Developer ID, notarização e revisão da solução de privilégios para distribuição. Zero identidades de assinatura válidas encontradas no Mac; não se presume a existência ou ausência de uma conta Apple Developer. A autorização não contorna SIP, TCC nem permissões de outros utilizadores.

## Cobertura seguinte para atingir o Mole

1. Desinstaladores específicos de pacotes, helpers externos em PrivilegedHelperTools, extensões e registos PKG. Casks com scripts/pkgutil/delete, vários bundles ou hooks especiais continuam diagnosticados antes de executar. Não correr Homebrew como root nem substituir falhas por eliminação direta.
2. Ampliar a prova de propriedade de serviços externos e a recuperação do seu estado quando uma remoção falha depois de os parar. Neste caso os dados/app permanecem, mas o serviço pode ficar parado; não se anuncia reversão completa.
3. Descoberta fora de `/Applications`, `~/Applications` e `/System/Applications`. O inventário atual examina até três níveis e exclui bundles auxiliares internos.
4. Mais provas de utilização exclusiva de grupos, contentores com links e famílias de apps. Não retirar proteções para aumentar artificialmente a cobertura.
5. Mais testes de apps Store reais descartáveis, daemons carregados no domínio system, outras permissões/TCC e outros macOS. Testados um LaunchAgent real descartável do utilizador, remoção/restauro administrativos e cache global exata; descoberta de daemons coberta por fixtures, sem serviço root real instalado.

O próprio Mole também reserva software específico de segurança/MDM para desinstaladores oficiais. Esse limite não justifica encaminhar todas as apps comuns para o Finder.

## Referência e licença

Estudado o Mole no commit `42b7b8d4c0331fed9c9c01480ec448ef23aabbdd`, confirmado em 04/10/2026. Fontes: [segurança](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/docs/SECURITY_DESIGN.md), [proteção e associações](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/lib/core/app_protection.sh), [fila e cópias sobreviventes](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/lib/uninstall/batch.sh), [Homebrew](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/lib/uninstall/brew.sh), [exceções](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/lib/core/app_protection_data.sh).

A licença dessa revisão é [GPL-3.0](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/LICENSE). Nenhum código ou binário do Mole foi incorporado, distribuído ou executado. O motor Swift é próprio; a consulta serviu para estudar comportamentos, provas de associação, falhas e proteção. A licença e as atribuições terão de ser revistas antes de qualquer reutilização futura. Não foram acrescentados os módulos gerais de limpeza/otimização do Mole.

## Referências Apple

- [NSWorkspace.recycle](https://developer.apple.com/documentation/appkit/nsworkspace/recycle(_:completionhandler:)): percurso assíncrono do sistema para o Lixo; não substitui a validação de identidade.
- [ServiceManagement / SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice): referência para evolução futura dos componentes privilegiados.
- [Apple DTS — assinatura e SMAppService](https://developer.apple.com/forums/thread/799910): requisitos e limites observados com assinatura ad hoc. Não foi instalado um daemon SMAppService nesta prévia.
