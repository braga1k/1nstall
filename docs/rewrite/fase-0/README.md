# Fase 0 — Especificação da 1nstall 3.6.0 a partir do código

Base: tag `v3.6.0`, commit `80e584f`, lido em 2026-11-18. A fonte foi o código e os testes; o README e os docs do repositório não foram usados como fonte de verdade.

## Estado

| Entregável da Fase 0 | Estado |
| --- | --- |
| Invariantes com ficheiro:linha | Feito: 283 invariantes em três documentos. |
| Contratos de dados | Feito: dados embutidos, ficheiros de runtime, rede do updater, linha de comandos. |
| Medições da 3.6 | Feito neste PC: pronta em 1 962 ms a quente (2 405 ms na primeira execução), pico de 238,5 MB, exe de 2 699 264 bytes. Não é um arranque a frio após reinício. Ver [medicoes.md](medicoes.md). |

Nada foi compilado nem alterado no repositório. A única execução foi a do `1nstall.exe` publicado, com `--startup-test`, para as medições.

## Documentos

| Ficheiro | Conteúdo |
| --- | --- |
| [invariantes/remocao.md](invariantes/remocao.md) | U-01 a U-107: inventário, validação do comando de desinstalação, seguimento de processos, descoberta e limpeza de restos. |
| [invariantes/instalacao.md](invariantes/instalacao.md) | I-01 a I-86: catálogo, linha de comandos do WinGet, códigos de saída, fila, inventário, importação de seleções. Inclui a tabela das 56 regressões de `tests/reliability.ps1`. |
| [invariantes/updater-e-arranque.md](invariantes/updater-e-arranque.md) | S-01 a S-90: updater, launcher, definições. Parte B: todos os ficheiros de runtime, contrato de rede, switches e códigos de saída. |
| [contratos-de-dados.md](contratos-de-dados.md) | Esquema medido de `catalog.json`, `profiles.json`, `locales.json` e tamanhos da release. |
| [medicoes.md](medicoes.md) | Arranque, memória e tamanho da 3.6.0 neste PC, e o objetivo aceite para a 4.0. |
| [verificacao/](verificacao/) | Scripts e listas que voltam a conferir as citações contra o código, e o script de medição do arranque. |

Cada documento de invariantes termina com três listas: comportamentos que parecem bugs, dependências de .NET/PowerShell/WPF que o Rust não dá de graça, e o que não se conseguiu determinar pelo código.

## Como foi verificado

Três leituras independentes do código, uma por fatia. Cada invariante traz um excerto literal da linha citada.

| Verificação | Resultado |
| --- | --- |
| Excertos de `remocao.md` contra as linhas citadas | 107 de 107 exatos |
| Excertos de `instalacao.md` (lista completa, inclui linhas secundárias) | 118 de 118 exatos |
| Excertos de `updater-e-arranque.md` (lista completa) | 191 de 191 exatos |
| Segunda leitura direta das conclusões mais graves | 6 confirmadas: porta de identidade do updater (`update-helper.cs:90-91`), histórico de remoções (`uninstall-helper.cs:196-207`), exceções apanhadas no seguimento de processos (`:292-309`), `SafeRegistry` (`:484-492` e `:699`), flags do WinGet (`package-helper.cs:114`) e códigos de saída (`:209-212`) |

**Limite desta verificação:** um excerto exato prova que a linha existe e diz aquilo. Não prova que a interpretação do invariante está certa. Fora das seis conclusões com segunda leitura, as restantes afirmações assentam numa única leitura.

Para repetir a verificação, a partir da pasta que contém `v36/` e `fase-0/`:

```bash
node fase-0/verificacao/verificar-relatorio.js v36 fase-0/invariantes/remocao.md '{"UH":"src/uninstall-helper.cs","VX":"vexan_installers.ps1","MU":"src/manager-ui.ps1"}'
```

```bash
node fase-0/verificacao/verificar-lista.js v36 fase-0/verificacao/citacoes-instalacao.txt '{"V":"vexan_installers.ps1","P":"src/package-helper.cs","M":"src/manager-ui.ps1","R":"tests/reliability.ps1"}'
```

```bash
node fase-0/verificacao/verificar-lista.js v36 fase-0/verificacao/citacoes-updater.txt '{}'
```

## O que muda o plano

### 1. A 3.6 recusa atualizar-se para um executável Rust

Depois de verificar o hash, o updater exige que o `1nstall.exe` descarregado seja um assembly .NET com nome `1nstall` e versão igual à tag (`src/update-helper.cs:90-91`, S-17). Um PE nativo falha essa leitura, o erro é engolido (`:93`) e o utilizador vê apenas «Could not check or download the update».

Consequência: publicar a 4.0 em Rust com o asset `1nstall.exe` deixa todas as 3.6 instaladas presas, a repetir a falha em cada arranque. Confirmado por leitura; não foi executado.

Duas saídas possíveis:

- **Stub .NET (recomendado).** O asset `1nstall.exe` da 4.0 é um pequeno assembly .NET chamado `1nstall`, versão `4.0.0.x`, que traz o binário Rust e se substitui por ele no primeiro arranque. O binário nativo é publicado noutro asset, e o updater da 4.x passa a procurar esse. Nenhum utilizador fica para trás.
- **Release-ponte 3.7.** Uma última versão .NET que relaxa a verificação. Quem saltar a 3.7 fica preso, porque o updater só consulta `/releases/latest`.

O resto do contrato que a 4.0 tem de cumprir para a 3.6 a aceitar está em `updater-e-arranque.md`, secção B2.

### 2. As flags de confiança da limpeza vivem num ficheiro editável

`uninstall-history.json` guarda `RemovalVerified`, `OwnershipVerified` e `IdentityVerified`, e essas flags voltam a ser confiadas quando o ficheiro é relido (`uninstall-helper.cs:196-207`, U-36 a U-39). A escrita não é atómica, e um ficheiro corrompido é tratado como vazio e depois sobrescrito. O outro histórico, `operations.json`, faz o contrário: recusa sobrescrever (I-62).

Na 4.0 a confiança deve ser recalculada a partir do estado da máquina, não lida do disco.

### 3. Chaves de registo são apagadas só por igualdade de nome

`SafeRegistry` (`uninstall-helper.cs:484-492`) aceita uma chave se o nome coincidir com o da app removida e não colidir com apps instaladas. Não exige `OwnershipVerified`, ao contrário dos valores de rasto (`:699`). Isto inclui subárvores inteiras em HKLM. Há sempre backup e revisão pelo utilizador, mas a prova é mais fraca do que a das pastas.

### 4. Provável falha com desinstaladores elevados

O seguimento de processos filhos lê `StartTime` e `Handle` de cada descendente (`uninstall-helper.cs:297`, `:302`), e só apanha `ArgumentException` e `InvalidOperationException` (`:305-306`). Com a app a correr sem elevação (`app.manifest:5`) e o desinstalador de uma entrada HKLM lançado com `runas`, essas leituras devem lançar «acesso negado», que sobe e marca a remoção como `Failed`.

É análise estática e está por confirmar. Os fixtures de teste são todos HKCU, por isso nenhum teste existente passa por aqui. É o primeiro cenário a pôr no harness da Fase 1.

### 5. A fila de remoção pode ficar bloqueada para sempre

A espera pelos descendentes do desinstalador não tem tempo limite (`uninstall-helper.cs:310-311`), e a janela recusa fechar durante uma remoção. Um desinstalador que abra um browser ou deixe um updater a correr prende a app.

### 6. A cobertura real de testes é menor do que parece

146 dos 283 invariantes não têm teste (48 na remoção, 31 na instalação, 67 no updater e arranque).

O CI corre cinco coisas: `catalog.py`, `locales.py`, `reliability.ps1`, o movimento elástico em modo headless e `--self-test`. Não corre os testes de remoção (exigem ambiente descartável) nem `--manager-test`, que é onde estão as asserções do updater e das definições.

Para a Fase 1 isto significa que o oráculo não pode ser «o CI passa». Tem de incluir esses testes a correr numa VM.

### 7. Onde uma tradução para Rust diverge em silêncio

As listas 2 e 3 dos documentos de invariantes enumeram os comportamentos herdados do .NET e do PowerShell. Os que mais pesam:

- **Regex:** o `$` do .NET aceita um `\n` final, por isso `ValidId("Foo.Bar\n")` é verdadeiro (`package-helper.cs:94`). O `regex` de Rust é mais estrito.
- **Comparações do PowerShell:** `-eq`, `-contains` e `-in` não distinguem maiúsculas; as chaves de hashtable também não.
- **JSON:** `Version` tem de ser inteiro (`1.0` é rejeitado); há limites de tamanho e profundidade por ficheiro.
- **BOM:** uns ficheiros de runtime têm, outros não.
- **Estados como texto inglês:** `Success`, `Failed`, `Installed ·` são comparados como literais. Na 4.0 devem ser um `enum`.
- **Caminhos:** `Path.GetFullPath` não equivale a `std::fs::canonicalize`, que resolve links e devolve prefixo `\\?\`.

### 8. Factos da arquitetura atual

- O PowerShell corre dentro do processo, sem `powershell.exe` (S-46). Os scripts nunca vão para disco (S-43).
- Não há instância única (S-60): duas janelas podem escrever o mesmo histórico.
- A instalação passa `--accept-source-agreements --accept-package-agreements` (I-14), depois de uma caixa de consentimento obrigatória (I-10). Na API COM do WinGet esse consentimento tem de ser passado explicitamente.
- Uma saída 0 do WinGet nunca conta como instalado: só um inventário novo o confirma (I-28, I-31). O mesmo vale para a remoção (U-30).
- A app já tem um medidor de arranque: `1nstall.exe --startup-test` escreve `READY`, `FirstFrameMs`, `BeforeShowMs`, `LoadedMs` e `RenderMs` (`launcher.cs:139-141`).

## Decisões tomadas

| Decisão | Data | Detalhe |
| --- | --- | --- |
| Objetivo mensurável da 4.0 | 2026-11-18 | Pronta em menos de 500 ms, pico abaixo de 80 MB, exe abaixo de 12 MB, sem dependências além do Windows e do WinGet. Medido neste PC com `--startup-test`. Ver [medicoes.md](medicoes.md). |
| Não portar a janela de abertura | 2026-11-18 | A animação só existe para mascarar o carregamento. Com o objetivo acima deixa de ser precisa; S-54 a S-57 ficam fora. Reabre-se se a Fase 3 não atingir o limiar. |

## Decisões em aberto

| Decisão | Porque é precisa agora |
| --- | --- |
| Ponte de atualização: stub .NET ou release-ponte | Define que assets a 4.0 publica e como se chama o binário nativo. |
| Bugs: reproduzir ou corrigir | A lista de divergências intencionais começa aqui. Proposta: corrigir os pontos 2 a 5 acima e reproduzir tudo o resto até prova em contrário. |

## O que ficou por cobrir

- **Arranque a frio após reinício, e medições numa máquina comum.** As medições feitas são de um PC topo de gama, sem reinício entre execuções.
- **Interface.** `interface.xaml`, `src/motion.cs`, `src/ui-helper.cs`, `src/window-helper.cs` e a maior parte de `src/appearance.cs` não foram lidos. A Fase 0 tratou do motor; a interface é assunto da Fase 3.
- **Comportamento em execução.** Tudo aqui é leitura estática. O ponto 1 e o ponto 4 são conclusões de leitura, por confirmar numa VM.
- **Upstream.** Os códigos HRESULT do WinGet foram extraídos do código da 3.6, não conferidos contra `AppInstallerErrors.h`. O código não tem os nomes simbólicos.
- **Dados reais.** Não foram recolhidas chaves `Uninstall` de máquinas reais nem traços do Process Monitor. Isso é a Fase 1.
