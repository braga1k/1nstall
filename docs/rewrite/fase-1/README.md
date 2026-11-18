# Fase 1 — Oráculo do comportamento da 3.6

Atualizado em 2026-11-18, após a segunda iteração. O harness está no ramo `oracle/phase-1` do repositório, em quatro commits que não tocam em código da aplicação. A execução de referência é a [44300617038](https://github.com/braga1k/1nstall/actions/runs/44300617038), sobre o commit `092f4b7`.

## Estado

| Entregável da Fase 1 | Estado |
| --- | --- |
| Oráculo das funções puras do motor | **Feito.** 1 552 casos, 23 funções, reproduzido em três máquinas. |
| Oráculo dos fluxos de remoção | **Feito.** 8 cenários com o estado da máquina em cada passo, reproduzido nas duas imagens do Actions. |
| Testes nativos de remoção em máquina descartável | **Feito.** Passam nas duas imagens, em três execuções. |
| Leitura do registo real | **Feito**, como observação. |
| Instalação real pelo caminho da 3.6 | **Feito**, com duas apps reais. O caminho com inventário completo ficou por observar. |
| Tabela de códigos conferida contra o WinGet | **Feito.** |
| Desinstalador elevado a partir de processo sem privilégios | **Feito neste PC, sem VM.** A falha foi reproduzida com a função real da 3.6. |
| API COM do WinGet numa sessão normal | **Feito neste PC.** Ativa em 0,1 s. |
| Remoção real com diálogos do desinstalador | **Por fazer.** É o único ponto que ainda pede uma máquina descartável. |
| Traços do Process Monitor | **Por fazer.** |

## O que existe no repositório

Tudo em `oracle/`:

| Ficheiro | Função |
| --- | --- |
| `corpus/pure.json` | Entradas das funções puras. Neutro quanto à implementação. |
| `drivers/v36-pure.ps1` | Passa o corpus pelos helpers C# da 3.6, incluindo os privados. |
| `golden/v3.6.0/pure.jsonl` | Oráculo das funções: uma linha JSON por caso. |
| `golden/v3.6.0/removal.jsonl` | Oráculo da remoção: uma linha por cenário, mais o ficheiro de histórico. |
| `observe-machine.ps1` | Camada de máquina. Recusa correr sem `-DisposableEnvironment`. |
| `reference/winget-errors.json` | Nomes oficiais dos 203 códigos do `AppInstallerErrors.h`. |
| `.github/workflows/oracle.yml` | Regenera os dois oráculos em máquinas limpas e falha se um byte diferir. |

## Quem confirma, além de nós

| Verificação | Resultado |
| --- | --- |
| Oráculo das funções, neste PC | sha256 `ceb376cc…622c` |
| Oráculo das funções, `windows-2022` e `windows-2025` | Byte a byte, mesmo sha256, em três execuções |
| Oráculo da remoção, `windows-2022` e `windows-2025` | Byte a byte, sha256 `fa845f11…aae4` nas duas |
| `tests/uninstall.ps1` e `tests/uninstall-process.ps1` | PASS nas duas imagens, em três execuções |
| Códigos especiais da 3.6 contra o header oficial | Os 11 existem, com o sentido que a 3.6 lhes dá |

O oráculo da remoção foi **produzido** pelo Actions e só depois fixado: nunca correu neste PC. As duas imagens geraram-no de forma independente, e coincidiu depois de retirado um campo que dependia da máquina.

## Os oito cenários de remoção

Cada cenário regista uma app fictícia em `HKCU` com um desinstalador de substituição e corre as chamadas reais da 3.6: `Inventory`, `RemoveAsync`, `ScanAsync`, `CleanAsync`. Em cada passo fica gravado o estado do registo e dos ficheiros.

| Cenário | Desinstalador | Resultado gravado da 3.6 |
| --- | --- | --- |
| Alpha | Sai bem; deixa um ficheiro, dados, uma chave e um rasto | `Success`; 4 restos oferecidos e limpos |
| Bravo | Sai com 1602 | `Cancelled`; nada é oferecido |
| Charlie | Sai com 0 mas o registo fica | `Manual action required` |
| Delta | Sai com 3010 | `Restart required`; a análise de restos fica bloqueada |
| Echo | O lançador sai logo; um filho termina 1,5 s depois | `Success`, depois de esperar pelo filho |
| Foxtrot | Sai com 1603 | `Failed` |
| Golf | Sai bem; o registo não tem `InstallLocation` | `Success`; ver o achado abaixo |
| Hotel | O comando é `cmd.exe` | Recusado; `Failed` |

Ficam também gravados o conteúdo da pasta de backup, a forma de `items.json` e `results.json`, o texto de `RESTORE.txt` e a forma de `uninstall-history.json`. São os contratos de disco que a Fase 0 só tinha lido no código.

## Achados com prova

### 0. Com o UAC ligado, a remoção falha quando o desinstalador elevado tem um processo filho

Reproduzido neste PC (Windows 11, sessão sem privilégios, UAC ligado, .NET Framework 4.8.1) com a rotina real `WaitForUninstaller` da 3.6 e um comando inofensivo, `cmd.exe /c timeout /t 6`:

| Caso | Resultado |
| --- | --- |
| Sem elevação | Esperou os 6 s e terminou bem, saída `0` |
| Elevado pelo UAC, como a 3.6 faz com entradas `HKLM` | `Win32Exception`, erro nativo 5, «Access is denied» |

A causa é a prevista na Fase 0. A rotina lê o identificador de cada processo filho (`uninstall-helper.cs:302`); num filho elevado essa leitura é recusada, e o código só apanha `ArgumentException` e `InvalidOperationException` (`:305-306`). A exceção sobe até `RemoveAsync`, que a reporta como `Failed` (`:369`).

Medição complementar no mesmo PC: de 239 processos em execução, a leitura lançou `Win32Exception 5` em 89, e em nenhum lançou outro tipo de exceção.

Consequências num PC comum:

- A app aparece como `Failed` com «Access is denied», mesmo que o desinstalador esteja a correr bem.
- A fila avança para a app seguinte **com o desinstalador anterior ainda a correr**, porque a espera foi abandonada.
- Só afeta apps registadas em `HKLM`, que são as que a 3.6 lança com `runas`, e só quando o desinstalador cria um processo filho. Os desinstaladores NSIS e Inno Setup copiam-se para uma pasta temporária e relançam-se, por isso é de esperar que caiam aqui; isto não foi testado com um desinstalador real.

Porque é que os testes anteriores não o apanharam: os fixtures são todos `HKCU`, e os runners do Actions correm como administrador, onde a leitura é permitida. Os testes reais com 7-Zip e Notepad++ descritos nos docs foram feitos no Windows Sandbox; não verifiquei se lá a sessão é elevada, mas seria a explicação mais simples para não terem falhado.

O teste ficou no repositório como verificação manual, `oracle/manual/elevated-uninstaller.ps1`: precisa de um clique no pedido do UAC, por isso não corre em CI.

### 1. Numa máquina nova, a 3.6 instala bem e diz «Unknown»

Em `windows-2025`, sem o módulo `Microsoft.WinGet.Client`:

- O Sumatra PDF instalou com saída `0` e ficou registado.
- A 3.6 reportou `Unknown`: «resulting state could not be confirmed».
- A causa está medida. O comando de recurso da 3.6, `winget export … --disable-interactivity`, devolve `0x8A150046` (acordos de origem não aceites) por causa da origem `msstore`.
- O mesmo comando com `--accept-source-agreements` devolve `0`. Depois disso, o comando original da 3.6 também passa a devolver `0`.

A instalação passa `--accept-source-agreements` com `--source winget`, e mesmo depois dela o export continuou a falhar por causa da `msstore`. A leitura que os dados sustentam é que a instalação só aceita o acordo da origem que usa, e o export consulta todas. Num PC acabado de instalar, sem o módulo, todas as instalações da 3.6 aparecem como `Unknown` até alguma coisa aceitar esse acordo.

A Fase 0 tinha isto como hipótese (ausência da flag no export). Fica confirmado.

### 2. Sem `InstallLocation`, a 3.6 ofereceu e reciclou a pasta do desinstalador

No cenário Golf a app chama-se «OracleGolf Editor» e o desinstalador está em `…\Programs\OracleGolf Tools`. A 3.6:

- tomou a pasta do desinstalador como localização da app;
- ofereceu-a como «Recorded installation folder», com confiança `Linked path`;
- reciclou-a na limpeza.

O botão «Select linked paths» da interface seleciona exatamente estes itens. Nas imagens reais do Actions, 44 % das apps não têm `InstallLocation` (31 de 71 e 27 de 59), por isso este caminho é o comum, não a exceção.

### 3. O backup de um rasto exporta a chave partilhada inteira

Ao apagar um único valor de rasto em `JumplistData`, o `.reg` de backup tinha 900 bytes numa imagem e 1 308 na outra: contém os valores de outras apps. Foi este o único campo que diferiu entre as duas máquinas.

### 4. A mensagem de erro mostra XML cru

Quando o módulo falta ou falha, o texto mostrado ao utilizador inclui `#< CLIXML <Objs …>_x001B_[31;1m…`.

### 5. O caminho do módulo não funcionou no runner

Com o módulo `Microsoft.WinGet.Client` 1.29.380 instalado, `Get-WinGetPackage` falhou com `Failed to create instance: -2147023174`, ou seja `0x800706BA` (servidor RPC indisponível). O servidor COM do WinGet não arrancou naquele ambiente.

É uma limitação daquele ambiente, não do WinGet. Neste PC, numa sessão normal sem privilégios e com o WinGet v1.29.380, a classe `PackageManager` da API COM (CLSID `C53A4F16-787E-42A4-B304-29EFFB4BF597`) ativou em 0,1 s a partir do Windows PowerShell 5.1, sem PowerShell 7 e sem o módulo.

Para a Fase 2 isto é uma boa notícia com uma ressalva:

- **A API COM está ao alcance de um processo normal**, que é o caso da interface da 4.0. Chamá-la diretamente do Rust dispensa o PowerShell 7 e o módulo, e dá o inventário completo que hoje a 3.6 só tem com esses dois instalados.
- **Num processo elevado ou sem sessão interativa falhou.** O ajudante elevado da 4.0 não deve depender dela, e o CI precisa de outra forma de testar esse caminho.
- **Só foi testada a ativação.** Nenhum método foi chamado; listar pacotes e instalar ficam para o teste isolado da Fase 2.

Neste PC a 3.6 também só obteve inventário **parcial** (71 pacotes pelo export), porque o PowerShell 7 não está instalado. O inventário **completo** da 3.6 continua por observar; o `Success` gravado no Notepad++ veio do inventário parcial.

### 6. Comandos reais que a 3.6 recusa

| App real na imagem | Comando registado | Veredicto da 3.6 |
| --- | --- | --- |
| Microsoft Azure Compute Emulator | `msiexec /x{04ca054c-…}` | «No executable uninstaller» |
| Microsoft Azure Service Fabric | `powershell.exe -File "…\CleanFabric.ps1"` | «Uninstaller is missing» |

O primeiro é um `msiexec` sem caminho numa entrada não marcada como MSI: a 3.6 não o consegue remover. As restantes 127 entradas das duas imagens foram aceites.

### 7. Divergências certas numa tradução direta para Rust

Cada ponto é uma linha do oráculo das funções:

- **Minúsculas.** `Token("İstanbul")` devolve `İstanbul` e `Token("STRAẞE")` devolve `straẞe`. O `to_lowercase` do Rust altera os dois. `Token` decide que pastas pertencem a uma app.
- **Fim de linha no regex.** `ValidId("Git.Git\n")` é verdadeiro, e a quebra de linha acaba na linha de comandos do WinGet. `SafeRegistry("Software\\Sample Editor\n", …)` também é verdadeiro.
- **Números pela cultura.** `FormatBytes(1536)` dá `1.5 KB` em `en-US` e `1,5 KB` em `pt-PT`.
- **JSON.** Propriedades tipadas não distinguem maiúsculas; chaves de dicionário distinguem. Chave repetida vale a última. `"Version": 1.0` é rejeitado.
- **Redação.** `Redact("C:\\Users\\alice\\…\\app.log failed")` devolve só `<path>`: o resto da linha desaparece.

## Tabela de códigos contra o WinGet

Fonte: `AppInstallerErrors.h`, commit `df1118d` de 2026-10-01, com 203 códigos.

- **Os 11 códigos que a 3.6 trata à parte existem e batem certo.** Por exemplo `0x8A150061` é `PACKAGE_ALREADY_INSTALLED` e `0x8A15010B` é `INSTALL_REBOOT_INITIATED`.
- **Fica confirmada uma dúvida da Fase 0:** com `--no-upgrade` e o pacote já instalado, o WinGet devolve `0x8A150061`. Foi observado com o 7-Zip na primeira execução.
- **Candidatos a reclassificar na 4.0.** A 3.6 dá `Failed` genérico a códigos que têm causa clara:

| Código | Nome oficial | Leitura mais útil |
| --- | --- | --- |
| `0x8A15010E` | `INSTALL_DOWNGRADE` | Já existe uma versão mais recente: verificar, não falhar |
| `0x8A150102` | `INSTALL_INSTALL_IN_PROGRESS` | Outra instalação a decorrer: tentar depois |
| `0x8A150101`, `0x8A150103`, `0x8A150111` | pacote ou ficheiro em uso | Ação manual: fechar a app |
| `0x8A15010F`, `0x8A15003A` | bloqueado por política | Ação manual, sem repetição |
| `0x8A150105` | `INSTALL_DISK_FULL` | Mensagem própria |

Reclassificar é uma decisão de produto; fica na lista de divergências intencionais se for aceite.

## Limites

- **O inventário completo da 3.6 não foi observado.** Exige PowerShell 7 e o módulo, numa sessão normal.
- **Não houve remoção de uma app real.** Os desinstaladores reais abrem diálogos, e a 3.6 lança-os sem modo silencioso.
- **A falha de elevação foi reproduzida com um comando de substituição**, não com um desinstalador real.
- **Os cenários de remoção usam só `HKCU`.** Nenhum passa por `HKLM`, vista de 32 bits, MSI ou apps da Store.
- **Os artefactos do workflow não foram descarregados.** Li as gravações que o próprio workflow publica como anotações, com hash conferido. O inventário completo das imagens e os `.reg` em bruto continuam só no artefacto.
- **O corpus e os cenários foram escritos por mim.** Cobrem o que os invariantes da Fase 0 sugerem; fora da gama de códigos não são exaustivos.
- **A fila de instalação não tem oráculo.** As regras de dependências, paragem e agregação por app vivem no script PowerShell da interface e não estão cobertas.

## O que falta para fechar a Fase 1

1. Um cenário de remoção em `HKLM` e outro em vista de 32 bits, no Actions.
2. Oráculo da fila de instalação, extraindo o worker do script como faz `tests/reliability.ps1`.
3. Remoção real do Notepad++ e do Sumatra PDF, com os diálogos dos desinstaladores. É o único ponto que pede uma máquina descartável com sessão interativa; pode ficar para o beta.

## Sobre a VM

Não é precisa agora. Dos três testes que a justificavam, dois fizeram-se neste PC só a ler e com um clique no UAC. Além disso, este PC não tem Hyper-V nem Windows Sandbox: montar uma VM implicaria instalar um hipervisor de terceiros e descarregar uma imagem do Windows de vários GB, para cobrir apenas o ponto 3.
