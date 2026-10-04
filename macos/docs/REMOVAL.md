# Remoção macOS — estado 0.3.0

O objetivo confirmado por Vitor é atingir a competência de desinstalação do Mole. O encaminhamento generalizado para o Finder deixou de ser o percurso normal. Esta versão amplia a remoção real, mas **ainda não tem paridade total com o Mole**.

## Percursos implementados

| Caso | Comportamento 0.3.0 | Verificação |
|---|---|---|
| App comum anterior à 1nstall, dentro das raízes analisadas | Seleção pelo caminho instalado, revisão e passagem para o Lixo | Identidade e localização antes/depois; destino no Lixo; inventário atualizado |
| App fora do catálogo | Mesmo percurso nativo; não precisa de recibo da 1nstall | Identidade conservada no histórico para rever dados depois de remover |
| App com recibo da App Store | Mesmo percurso nativo quando as permissões permitem | Fixture com estrutura de recibo; não se removeram apps pessoais da Store |
| Homebrew anterior à 1nstall | Prova pelo link exato do Caskroom e `brew list`; instruções da instalação guardadas no cask/INSTALL_RECEIPT | Remove com `brew uninstall --cask`, confirma ausência do bundle e do registo; sem `--zap` |
| Várias cópias do mesmo bundle | Remove apenas a cópia selecionada e indica as sobreviventes | Dados continuam bloqueados enquanto houver uma cópia instalada |
| App em execução | Recusa a remoção; ficha permite pedir encerramento normal | Sem encerramento forçado nem perda deliberada de trabalho por guardar |
| App do sistema ou a própria 1nstall | Proteção explícita | Não aparece como remoção guiada nem como sucesso |
| Interrupção/falha | Fila e histórico persistentes, diagnóstico e nova revisão | Reiniciar nunca transforma uma operação incompleta em sucesso |

O plano fixa a identidade do diretório, do pai e do Info.plist, e o conteúdo da identidade da app. A execução verifica novamente os caminhos, a origem Homebrew e as instruções de remoção. Não há fallback para apagar uma app quando o Homebrew falha. A UI mostra o caminho da cópia na revisão. Uma conclusão de remoção significa **remoção do bundle selecionado**, não ausência universal de dados ou componentes externos.

## Resíduos e dados

- Caminhos exatos pelo bundle ID: preferências, ByHost com UUID válido, caches, logs, WebKit, HTTPStorages/cookies, Application Support, scripts, autosave e estado guardado.
- Nomes completos exatos da app/bundle e nomes revistos do catálogo: Application Support, caches e logs. Sem pesquisas vagas por substring, corte de versões, diretórios globais de fabricantes ou dotfiles pessoais. A associação por nome aparece como tal na revisão.
- Colisões de nome com outra app instalada ficam protegidas. Famílias Apple mantêm os diretórios por nome protegidos; só caminhos identificados especificamente podem ser selecionados.
- Contentor individual: só pode ser selecionado quando o `MCMMetadataIdentifier` confirma o bundle. Sem essa prova, fica protegido. Conteúdo pessoal nunca é pré-selecionado.
- Group Containers e scripts de grupos: IDs obtidos dos entitlements de uma assinatura validada; apresentados como potencialmente partilhados e protegidos.
- LaunchAgents do utilizador: o executável tem de apontar literalmente para dentro do bundle selecionado, sem `..`. Antes de mover o plist, o serviço é descarregado e a ausência no launchd é confirmada. O caminho/ficheiro é novamente validado.
- Recursos associados em `/Library`: contados e apresentados como recursos do sistema protegidos, incluindo LaunchAgents/LaunchDaemons cujo programa aponta para o bundle. Ainda não são removidos por este motor.
- A medição conta ficheiros e bytes lógicos reais, com teto de 20 000 entradas por candidato e indicação de resultados parciais. Symlinks, dados alterados, inventário incompleto, cópia instalada/em execução e caminho reaparecido bloqueiam a limpeza. Uma associação não prova, por si só, exclusividade.
- Os itens selecionados vão para o Lixo; a UI distingue esta quantidade de espaço efetivamente libertado. O resultado da limpeza também fica no histórico. Não se esvazia o Lixo.

## Cobertura seguinte para atingir o Mole

1. Desinstaladores específicos de pacotes, serviços privilegiados, launch daemons, helpers externos e extensões, com autorização nativa do macOS quando necessária. Casks com scripts/pkgutil/delete, vários bundles ou hooks especiais são diagnosticados antes de iniciar e não executados por uma revisão limitada ao bundle.
2. Integração de permissões administrativas: `FileManager.trashItem` usa as permissões correntes; acesso negado fica como falha, não como confirmação. Não existe ainda helper privilegiado ou elevação.
3. Descoberta de instalações fora de `/Applications`, `~/Applications` e `/System/Applications`, recibos PKG e recursos específicos dos fabricantes. O inventário atual examina até três níveis e exclui bundles auxiliares internos.
4. Mais provas de utilização exclusiva de grupos, contentores com links, auxiliares e famílias de apps. Não retirar a proteção a dados partilhados para aumentar artificialmente a cobertura.
5. Mais testes de apps Store reais descartáveis, serviços carregados e permissões; esta versão usa fixtures para esses casos.

O próprio Mole também reserva software específico de segurança/MDM para desinstaladores oficiais. Esse limite não justifica encaminhar todas as apps comuns para o Finder.

## Referência e licença

Estudado o Mole no commit `42b7b8d4c0331fed9c9c01480ec448ef23aabbdd`, confirmado em 04/10/2026. Fontes: [segurança](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/docs/SECURITY_DESIGN.md), [proteção e associações](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/lib/core/app_protection.sh), [fila e cópias sobreviventes](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/lib/uninstall/batch.sh), [Homebrew](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/lib/uninstall/brew.sh), [exceções](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/lib/core/app_protection_data.sh).

A licença dessa revisão é [GPL-3.0](https://github.com/tw93/Mole/blob/42b7b8d4c0331fed9c9c01480ec448ef23aabbdd/LICENSE). Nenhum código ou binário do Mole foi incorporado, distribuído ou executado. O motor Swift é próprio; a consulta serviu para estudar comportamentos, provas de associação, falhas e proteção. A licença e as atribuições terão de ser revistas antes de qualquer reutilização futura. Não foram acrescentados os módulos gerais de limpeza/otimização do Mole.
