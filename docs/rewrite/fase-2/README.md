# Fase 2 — Motor em Rust, sem interface

Estado em 2026-11-18. O código está no ramo `v4/engine`, pasta `engine/`. A aplicação 3.6 na raiz do repositório não foi tocada.

## Resumo

O motor da 1nstall existe em Rust e reproduz a 3.6 em tudo o que o oráculo cobre, com as diferenças declaradas uma a uma. Ainda não substitui a 3.6: faltam a integração da API COM do WinGet, as definições, o updater e a interface.

## Estado face ao pedido

| Pedido para a Fase 2 | Estado |
| --- | --- |
| Workspace com `core`, `platform`, `cli` e ajudante elevado | `core`, `platform`, `cli` e `harness` feitos. **Ajudante elevado não feito**: o motor eleva como a 3.6, pedido a pedido, e isso bastou para a paridade. |
| WinGet pela API COM, com teste isolado primeiro | **Teste isolado feito e documentado. Integração no motor por fazer**: o inventário ainda vem do `winget export`. |
| Tabela de resultados gerada do `AppInstallerErrors.h` | **Parcial.** A classificação é a da 3.6, verificada nos 512 códigos da gama do WinGet. Os nomes oficiais estão em `oracle/reference/winget-errors.json`, mas a tabela não é gerada a partir deles. |
| `proptest` para os invariantes | Feito: 17 propriedades, 2 000 casos gerados cada. |
| `cargo-fuzz` nos dois parsers | **Não feito.** As propriedades geram entradas hostis para os dois parsers, mas não é fuzzing guiado por cobertura. |
| As 56 regressões passam contra o motor | 55 cobertas por testes Rust. A que falta (resolução de idioma) pertence às definições, não ao motor. |
| Diff diferencial vazio ou em lista aprovada | Vazio fora das divergências listadas abaixo. **A lista está por aprovar por ti.** |

## Quem confirma, além de nós

Tudo isto corre no GitHub Actions em Windows Server 2022 e 2025, em máquinas limpas.

| Verificação | Resultado |
| --- | --- |
| Regras puras contra o oráculo da 3.6 | 1 552 casos: 1 532 idênticos, 9 entradas nulas, 5 erros de sintaxe JSON, 6 divergências listadas, 0 por explicar |
| Cenários de remoção contra a gravação da 3.6 | 9 linhas: 7 idênticas, 2 divergências listadas, 0 por explicar |
| Inventário de apps, Rust contra 3.6, num PC real | 210 de 210 idênticas e pela mesma ordem; inventário de proteção 323 de 323 |
| Propriedades de segurança | 17 passam; nenhuma violação encontrada no motor |
| Regressões de instalação da 3.6 portadas | 9 testes passam, com um WinGet de substituição |
| Fila de instalação | 8 testes passam |
| `cargo fmt --check` e `cargo clippy -D warnings` | Limpos |

Os cenários de remoção só correm em máquina descartável. Neste PC ficam desligados; o resultado acima é o do Actions.

O inventário foi comparado num único PC real. É um teste só de leitura e pode repetir-se em qualquer máquina com o exemplo `dump_inventory`.

## O que foi construído

| Crate | Conteúdo |
| --- | --- |
| `core` | As regras, sem I/O: identidade de pacotes, linha de comandos do WinGet, códigos de saída, parsing do export e das seleções, redação, comando de desinstalação, normalização de nomes, regras de pastas e de registo, porta de reinício, planeamento de dependências e fila de instalação. Tudo o que depende do Windows passa pelo trait `Host`. |
| `platform` | Windows: implementação do `Host`, registo, inventário de apps de ambiente de trabalho e da Store, seguimento de processos sem os abrir, lançamento com elevação, reciclagem, e os passos remover, analisar e limpar com os mesmos ficheiros de histórico e backup da 3.6. Execução do WinGet, histórico de operações, seleções guardadas, diagnósticos. |
| `harness` | Desinstalador e WinGet de substituição, e os testes de cenário. |
| `cli` | `oneinstall`, só de leitura: `apps`, `packages`, `state`, `plan`, `history`, `version`. |

Números da CLI neste PC, compilada em release:

| Medida | Valor |
| --- | --- |
| Tamanho do executável | 1 474 048 bytes |
| `oneinstall version` | 11 ms |
| `oneinstall apps` (210 apps) | 698 ms, quase tudo na consulta da Store pelo PowerShell |
| `oneinstall packages` | 696 ms, quase tudo no `winget export` |

Servem de referência para a Fase 3: o motor em si não é o que vai pesar no arranque.

## Teste isolado da API COM do WinGet

Pergunta: um processo Rust normal consegue ler o inventário completo por COM, sem PowerShell 7 nem o módulo?

| Configuração | Resultado |
| --- | --- |
| `CoCreateInstance`, sem mais nada ao lado do programa | Falha na primeira chamada: `0x80073D54`, sem registo de proxy para a interface |
| O mesmo, com `Microsoft.Management.Deployment.winmd` ao lado do programa | Funciona: catálogo local em 0,3 s; catálogo composto em 0,8 a 3,5 s |
| Runner do Actions (elevado, sem sessão interativa), pelo módulo PowerShell | Falha: `0x800706BA` |

O catálogo composto devolveu 237 pacotes, 71 deles correlacionados com a origem winget, o mesmo número que o `winget export` dá neste PC.

Consequências para a 4.0:

- O ficheiro `.winmd` da Microsoft (64 KB, licença MIT) tem de estar na pasta do executável.
- O `winget export` fica como recurso para os contextos onde o servidor COM não arranca.
- Só foi testada a leitura. Instalar por COM não foi testado.

O teste está em `engine/spikes/winget-com/`.

## Divergências intencionais

Cada uma é uma decisão minha tomada para não parar, e fica **por aprovar**. As duas primeiras estão fixadas em ficheiros que os testes verificam: se o comportamento mudar de outra forma, o teste falha.

| # | Divergência | Onde está registada | Porquê |
| --- | --- | --- | --- |
| 1 | Um identificador ou caminho de registo com quebra de linha no fim é recusado | `engine/oracle-divergences.json`, 6 casos | A 3.6 aceitava-o por causa do `$` do .NET, e a quebra de linha chegava à linha de comandos do WinGet. |
| 2 | Uma localização deduzida do ícone ou do desinstalador não é levada para a remoção | `engine/oracle-removal-divergences.json`, cenário Golf e a sua entrada no histórico | A 3.6 tomava a pasta do desinstalador como pasta de instalação, com a etiqueta `Linked path`, e reciclava-a. |
| 3 | Os processos do desinstalador são seguidos sem os abrir | Código; também corrigido na 3.6 no ramo `fix/elevated-uninstaller-wait` | Com o UAC ligado, a 3.6 falhava com «Access is denied». |
| 4 | A verificação depois de instalar passa `--accept-source-agreements` ao `winget export` | Código (`packages.rs`); **sem cobertura do oráculo** | Sem isso, num PC novo todas as instalações ficam `Unknown`. Só acontece depois de o utilizador aceitar os termos para instalar. |
| 5 | O histórico de remoções é escrito por ficheiro temporário | Código | Uma escrita interrompida deixava o ficheiro truncado. Não muda o formato. |
| 6 | A janela de abertura não é portada | Decisão tua na Fase 0 | Só existia para mascarar o carregamento. |
| 7 | O nome da pasta de instalação só conta como nome do produto quando partilha o nome do produto, e nomes de pastas partilhadas (Plugins, VST3, Components, Shared, Tools…) nunca contam | `engine/oracle-divergences.json`, 5 casos; testes em `engine/core/tests/properties.rs` | Acrescentada na Fase 4, depois de uma limpeza real: a 3.6 ofereceu pastas e chaves «Plugins» de outros programas como vestígios de uma app instalada em `Common Files\OFX\Plugins`. |

Diferenças de classe, aceites pelos testes sem lista caso a caso:

- **Entrada nula** (9 casos): o Rust não consegue receber um nulo onde a 3.6 recebia.
- **Sintaxe JSON** (5 casos): ambos recusam texto que não é JSON, com palavras diferentes.

Diferenças possíveis que o oráculo não cobre:

- **Texto de erros do sistema.** «Acesso negado» ao percorrer uma pasta sai com outra redação.
- **JSON tolerante.** O serializador da 3.6 aceitava aspas simples e outras liberdades; o Rust é estrito.
- **Versão do Unicode.** Letras atribuídas depois da versão que o .NET Framework conhece contam como letras em Rust e não na 3.6.

## O que ficou igual à 3.6 de propósito

Assinalei estes pontos na Fase 0 como defeitos, mas mantive-os para não mexer no que o oráculo fixa. São decisões tuas.

| Ponto | Comportamento mantido |
| --- | --- |
| Chaves de registo oferecidas só por igualdade de nome | Continuam a ser oferecidas como `Name match`, sem exigir prova de posse. |
| Espera pelo desinstalador sem tempo limite | Um desinstalador que deixe um processo a correr continua a prender a fila. |
| Flags de confiança lidas do histórico | Continuam a ser lidas de `uninstall-history.json`. |
| Um histórico de remoções ilegível é tratado como vazio | E depois sobrescrito. |
| Inventário da Store pelo PowerShell 5.1 | O mesmo comando da 3.6, para a paridade ser exata. |

## O que não foi feito

- **Integração da API COM no motor.** Só existe o teste isolado.
- **Definições, updater e launcher.** São da interface e da Fase 4.
- **Remoção e limpeza pela CLI.** A CLI é só de leitura; os passos destrutivos só são exercidos pelos testes.
- **Instalação real a partir do Rust.** Os testes usam um WinGet de substituição. As instalações reais da Fase 1 foram feitas pela 3.6.
- **Cenários em `HKLM`, vista de 32 bits, MSI e Store.** Os oito cenários de remoção são todos `HKCU`.
- **Oráculo da fila de instalação.** A fila foi portada e testada com as regressões da 3.6, mas não comparada contra uma gravação.
- **Fuzzing guiado por cobertura.**
- **Ajudante elevado.**

## Ramos no repositório

| Ramo | Conteúdo | Estado no Actions |
| --- | --- | --- |
| `main` | 3.6.0, intocado | — |
| `fix/elevated-uninstaller-wait` | Correção da falha de elevação na 3.6 | Verde |
| `oracle/phase-1` | O oráculo | Verde |
| `oracle/verify-elevated-fix` | Oráculo mais a correção, só para verificação; pode apagar-se | Verde |
| `v4/engine` | Tudo o que está acima, mais o motor Rust e estes relatórios | Ver a última execução |

Não há nenhum pull request aberto.

## Antes da Fase 3

Preciso de três decisões tuas:

1. **Aprovar, ou alterar, a lista de divergências.** Em especial a 4, que não tem cobertura do oráculo.
2. **A ponte de atualização da 3.6 para a 4.0**: stub .NET ou release-ponte. Continua em aberto desde a Fase 0.
3. **Confirmar os três protótipos da Fase 3**: Slint, Tauri com WebView2, e a shell WPF atual sobre o motor Rust.

O objetivo já aceite (pronta em menos de 500 ms, pico abaixo de 80 MB, executável abaixo de 12 MB) passa a ser um dos critérios de comparação dos protótipos.
