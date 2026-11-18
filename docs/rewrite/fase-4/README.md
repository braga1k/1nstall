# Fase 4 — Interface, migração e release

Estado em 2026-11-18, depois dos seis passos e de uma ronda de otimização do arranque. O código está no ramo `v4/app`, nas pastas `app/` e `engine/`. As fontes da 3.6 continuam na raiz, como referência do oráculo; `build-windows.ps1` passou a construir a 4.0.

## Resumo

Escolheste a interface WPF sobre o motor Rust. Existe um `1nstall.exe` 4.0 num único ficheiro, sem PowerShell, e está provado que a 3.6 se atualiza para ele sem release intermédia. Com todas as páginas da 3.6 incluídas, fica pronto em 473 ms, abaixo do limite de 500 ms, com o aspeto e as animações intactos. O limite de memória de 80 MB não é atingido: fica em 113 MB.

Os seis passos estão feitos e a release está preparada, mas não publicada: publicar é um push teu. Antes disso há uma decisão a tomar, descrita no passo 6: nesta versão o inventário do WinGet é sempre parcial, e por isso o botão de repetir uma instalação falhada nunca aparece.

## O executável da 4.0

| Medida | 3.6.0 | Passo 1, antes de otimizar | Passo 1, otimizado | Passo 2 | Passo 3 | Passo 4 | Passo 5 | Passo 6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Tamanho | 2 699 264 bytes | 3 098 624 bytes | 3 064 320 bytes | 3 130 880 bytes | 3 231 744 bytes | 3 277 312 bytes | 3 513 856 bytes | 3 942 912 bytes |
| Pronta e ociosa, a quente | 1 996 ms | 594 ms | 444 ms | 467 ms | 479 ms | 473 ms | 473 ms | 390 ms* |
| Primeira execução, com extração do motor | 2 425 ms | 763 ms | 501 ms | 563 ms | 569 ms | 559 ms | 567 ms | 482 ms* |
| Pico de working set | 242 MB | 105 MB | 101 MB | 110 MB | 113 MB | 116 MB | 113 MB | 87 MB* |
| Em repouso após 8 s (working set / privada) | não medido | não medido | 101 / 104 MB | 113 / 124 MB | 116 / 129 MB | 109 / 125 MB | 112 / 130 MB | 82 / 53 MB* |
| Precisa, além do Windows | .NET Framework 4.8, PowerShell 5.1 | .NET Framework 4.8 | .NET Framework 4.8 | .NET Framework 4.8 | .NET Framework 4.8 | .NET Framework 4.8 | .NET Framework 4.8 | .NET Framework 4.8 |

Medido neste PC com a régua da Fase 0, mediana de 10 arranques a quente. No passo 5 os 10 arranques ficaram entre 453 e 496 ms.

**\* Os valores do passo 6 não se comparam com as outras colunas.** Entre as duas medições a configuração de ecrã do PC mudou (o ecrã ativo passou a ser um adaptador virtual), e nela tudo desenha mais depressa e com menos memória. Medi por isso as três versões de novo, nas mesmas condições:

| Nas condições do passo 6 | 3.6.0 | Passo 5 | Passo 6 |
| --- | --- | --- | --- |
| Pronta e ociosa, a quente | 2 073 ms | 395 ms | 390 ms |
| Pico de working set | 210 MB | 86 MB | 87 MB |

O passo 6 não alterou o arranque nem a memória. Acrescentou 429 KB ao executável: o motor deixou de abortar em caso de erro interno, e o código que o permite ocupa espaço.

**Nas condições das colunas anteriores, a margem para os 500 ms era de 27 ms na mediana, e o arranque mais lento da série ficou a 4 ms do limite.** Não voltei a medir nessas condições depois do passo 6. A partir do passo 3 a app pergunta ao WinGet o que está instalado logo que a janela abre, como a 3.6 faz; isso corre noutro processo e não entra no pico de memória acima.

Como é construído:

- **Um só assembly.** A interface compilada da 3.6 (`interface.xaml`), os seus ajudantes C# e o anfitrião novo ficam no mesmo `1nstall.exe`.
- **O motor Rust vai dentro do executável** e é extraído para a mesma cache imutável da 3.6, com o SHA-256 verificado antes de ser carregado. É carregado pelo caminho completo, sem procurar em pastas.
- **O passo de atualização é o da 3.6**, sem alterações.

## Passo 2: definições, tema e idiomas

Portei `src/settings.ps1` inteiro e as funções de aspeto de `vexan_installers.ps1`.

| Parte | Onde ficou | O que faz |
| --- | --- | --- |
| Ficheiro de definições | Motor Rust | Lê e grava `%LOCALAPPDATA%\1nstall\settings.json`, o mesmo ficheiro e formato da 3.6. Cada propriedade só é aceite se for válida; a escrita passa por um ficheiro temporário. |
| Escolha do idioma | Motor Rust | Resolve o idioma do Windows para um dos 51, com os casos especiais da 3.6 (português, chinês, norueguês, montenegrino). |
| O que o Windows diz | Motor Rust | Cor de destaque e efeitos de transparência pelo mesmo objeto do Windows que a 3.6 usa, e o tema claro pelo mesmo valor do registo. |
| Traduções | C# | Cada texto guarda o original em inglês, e a janela inteira é traduzida no sítio quando o idioma muda. Árabe e urdu espelham a disposição. |
| Aspeto | C# | Tema claro, escuro ou do sistema; cor de destaque ou preto e branco; vidro; alto contraste. Segue o Windows uma vez por segundo, como a 3.6. |
| Página de definições | C# | As cinco secções da 3.6, incluindo a verificação de atualizações. |

A página de definições em tema claro ficou igual à captura da 3.6 em `docs/images/settings-light.png`, tirando o botão de histórico, que ainda não existe, e o número da versão.

Diferenças face à 3.6, todas sem efeito visível:

- **Código do idioma.** A 3.6 devolve o código em minúsculas (`sr-latn`) e conta com o PowerShell ignorar maiúsculas; a 4.0 devolve-o como está em `locales.json` (`sr-Latn`). É o mesmo idioma.
- **Modo `--ui-test`, novo.** É a janela normal com as preferências fixas dos modos de teste: não lê nem grava nada no perfil do utilizador. Existe para os testes de interface poderem mexer nas definições à vontade.
- **Identificadores de automação** nas quatro escolhas da página, para os testes as encontrarem.

## Passo 3: a biblioteca completa

Portei as partes de biblioteca de `vexan_installers.ps1` e de `src/manager-ui.ps1`.

| Parte | Onde ficou a lógica | O que faz |
| --- | --- | --- |
| Seleção | Motor Rust | Escolher uma app seleciona também o que ela exige; remover uma app remove as que dependiam dela. |
| Estados de instalação | Motor Rust | Pergunta ao WinGet o que está instalado ao abrir e no botão Atualizar; cada cartão mostra se a app está instalada. |
| Filtros | C# | Categorias, pesquisa e as vistas «Todas as apps» e «Instaladas». A vista escolhida é lembrada no mesmo `preferences.json` da 3.6. |
| Detalhes | Motor Rust | A janela de detalhes de cada app: editor, licença, site, método, estado, identificadores e dependências. |
| Perfis | Motor Rust | Os 20 perfis incluídos, com o número de apps já contando as dependências. |
| Seleções guardadas | Motor Rust | Guardar a seleção, carregar uma seleção com pré-visualização, e guardar um instantâneo do que está instalado. Os ficheiros são os da 3.6 e leem-se nos dois sentidos. |
| Animações | C# | Entrada dos cartões, voo para a seleção, reordenação ao filtrar. Usam o mesmo código de animação da 3.6. |

A captura da biblioteca ficou igual à da 3.6 em `docs/images/install-dark.png`, tirando o botão de histórico, que ainda não existe.

### Um erro meu, corrigido

No passo 1 a seleção não era a da 3.6: ao escolher uma app com dependências, eu mostrava-as na lista mas não as selecionava nem as contava. Na 3.6 ficam selecionadas e contam. Está agora como na 3.6, e o teste verifica-o.

### Uma diferença intencional, por aprovar

Na 3.6 um cartão só reage a cliques. Um leitor de ecrã que ative o cartão pela ação própria de acessibilidade muda o interruptor, mas a app não regista a seleção. Na 4.0 o cartão reage à mudança em si, seja por rato, teclado ou tecnologia de apoio. Para quem usa rato ou teclado nada muda.

### Um ajuste de arranque

O menu dos perfis incluídos passa a ser construído quando é aberto pela primeira vez, e não ao arrancar. Poupa cerca de 8 ms e não muda o que se vê.

## Passo 4: a fila de instalação

Portei `Confirm-Plan`, o trabalhador de instalação, `Set-Busy`, o temporizador e o botão de parar de `vexan_installers.ps1`.

| Parte | Onde ficou | O que faz |
| --- | --- | --- |
| Regras da fila | Motor Rust, desde a Fase 2 | Instala pela ordem do plano; uma app só corre se o que ela exige acabou em sucesso; uma app guiada nunca conta como sucesso; parar não interrompe o instalador em curso. |
| Execução | Motor Rust | A fila corre num fio próprio dentro do motor e escreve o mesmo `operations.json` da 3.6. |
| Revisão | C# | A janela «Ready to install?», com a aceitação explícita das licenças antes de o botão de começar ficar ativo. |
| Progresso | C# | Estado por app, barra de progresso, registo da sessão, e o resumo final. A janela pergunta à fila o que aconteceu de 250 em 250 ms, como a 3.6. |
| Parar e fechar | C# | «Stop after current app» pede à fila que pare; fechar a janela durante uma instalação espera pelo instalador em curso. |

### Como foi testado sem instalar nada no teu PC

Nos modos de teste o motor recusa-se a instalar. Para testar a fila, o teste indica um programa de substituição, que recebe a linha de comandos do WinGet e termina sem instalar nada. As páginas das apps guiadas são registadas em vez de abertas no navegador, e o histórico de operações fica numa pasta ao lado do executável.

O programa de substituição termina com sucesso, mas nada fica instalado. A fila tem por isso de responder «Unknown · refresh to verify» e não «Success»: é a regra da 3.6 de nunca promover a sucesso o que não foi verificado, e o teste confirma-a.

### Instalação real

Uma instalação real pela fila do motor corre só no Actions, em máquinas descartáveis: o Sumatra PDF, o mesmo pacote que a Fase 1 instalou pela 3.6. Neste PC o teste recusa-se a correr.

Resultado no commit `e485117`:

| Imagem | Resultado |
| --- | --- |
| Windows Server 2025 | `Preparing…`, `Installing SumatraPDF.SumatraPDF…`, `Verifying…`, `Success`. Depois de voltar a perguntar ao WinGet, a biblioteca mostra `Installed · 3.6.1`. |
| Windows Server 2022 | Não correu: a imagem não tem WinGet. |

Na Fase 1, a 3.6 instalou este mesmo pacote na mesma imagem e respondeu `Unknown`, porque a sua verificação não conseguia ler a lista de instalados antes de os acordos da origem serem aceites. A 4.0 aceita-os na verificação, depois de o utilizador os ter aceite para instalar. É a divergência 4 da Fase 2, agora confirmada com uma instalação real.

## Passo 5: a desinstalação

Portei a parte de desinstalação de `vexan_installers.ps1`: a lista de apps instaladas, a fila de remoção e a sua revisão, a análise de vestígios e a limpeza dos que o utilizador escolher.

| Parte | Onde ficou | O que faz |
| --- | --- | --- |
| Regras de remoção | Motor Rust, desde a Fase 2 | Corre o desinstalador do próprio editor; só conta como removida a app cujo registo exato desapareceu; a limpeza é sempre um passo à parte. |
| Execução | Motor Rust | Ler as apps, remover, analisar e limpar correm uma de cada vez, num fio próprio dentro do motor. O histórico e as cópias de segurança são os da 3.6. |
| Progresso em direto | Motor Rust | As mensagens que a 3.6 mostra durante a remoção e a análise, nos mesmos pontos. Na Fase 2 o motor não as emitia, porque não havia interface. |
| Lista e filtros | C# | As apps instaladas, os filtros «Desktop» e «Microsoft Store» e a pesquisa por nome ou editor. |
| Revisão | C# | A janela de revisão da remoção e a dos vestígios: nada avança sem um consentimento novo e explícito, e os vestígios começam todos por selecionar. |
| Fila e resultado | C# | Estado por app, barra de progresso, registo da sessão, resumo da limpeza. |

A página ficou igual à captura da 3.6 em `docs/images/uninstall-queue-dark.png`.

### Como foi testado

A desinstalação altera o sistema, por isso os testes estão separados em dois.

| Onde | O que corre | O que não corre |
| --- | --- | --- |
| Neste PC | Só leitura: listar as apps, filtrar, pesquisar, selecionar uma e abrir a revisão. O teste recua sempre em vez de confirmar. | Nenhuma remoção, análise ou limpeza. Nos modos de teste o motor recusa as três. |
| Actions, máquinas descartáveis | Uma app fictícia é registada, removida com um desinstalador de substituição, analisada e limpa, tudo pela fronteira que a janela usa. Mais os oito cenários de remoção da Fase 2. | A janela em si: o Actions não tem ambiente de trabalho interativo. |

Resultado no Actions, commit `d9c38b4`, igual nas duas imagens (Windows Server 2022 e 2025):

| Passo | Resultado |
| --- | --- |
| Remover | `Preparing…`, `Removing…`, `Verifying…`, `Success` |
| Analisar | Duas pastas oferecidas: a de instalação, como `Linked path`, e a de dados, como `Name match` |
| Limpar | As duas com `Success`; a cópia de segurança regista o que foi limpo |

Neste PC a página leu 210 apps instaladas, 165 de ambiente de trabalho e 45 da Store: o mesmo número que o motor tinha contado na Fase 2 e que coincidia com a 3.6.

## Passo 6: histórico, diagnósticos, erros internos e release

### A página de histórico e diagnósticos

Portei `Show-ManagerPage`, `Render-History` e `Show-Diagnostics` de `src/manager-ui.ps1` e `Show-ThirdPartyNotices` de `vexan_installers.ps1`.

| Parte | Onde ficou | O que faz |
| --- | --- | --- |
| Histórico | Motor Rust | As últimas 100 operações, da mais recente para a mais antiga. Para cada uma, o motor decide se a instalação pode ser revista de novo e se o registo pode ser aberto. |
| Registo detalhado | Motor Rust | Só é oferecido um registo que ainda exista e esteja dentro da pasta de registos da app. |
| Diagnósticos | Motor Rust, desde a Fase 2 | Texto para rever, com caminhos, credenciais e endereços removidos. Nada é enviado. |
| Licenças e créditos | Motor Rust | O ficheiro de avisos, embutido. Passou a listar os 22 componentes Rust ligados ao motor, e a build falha se um deles não estiver lá com a sua versão. |
| Página, botões e janelas | C# | `app/History.cs`. |

### Um achado: o botão de repetir nunca aparece

A 3.6 oferece «Refresh & review installation again» a uma instalação falhada quando o inventário diz que a app **não está instalada**. Esse estado só existe com um inventário completo, que a 3.6 obtém pelo PowerShell 7 e pelo módulo Microsoft.WinGet.Client, quando o utilizador os tem.

A 4.0 lê apenas o `winget export`, que diz o que está instalado e não prova o que falta. Consequências, todas confirmadas no código e no teste da interface:

- O botão de repetir **nunca aparece**. O código existe e está testado no motor com um inventário completo construído no teste, mas na aplicação não há como lá chegar.
- Uma app que o WinGet não lista aparece como `Unknown`, nunca como `Not installed`.
- Quem usava a 3.6 sem o PowerShell 7 e o módulo já via exatamente isto. Quem os tinha perde informação.

Isto é a falta já registada desde a Fase 2 («a API COM do WinGet não está integrada»), agora com as consequências visíveis. O teste isolado da Fase 2 mostrou que a leitura por COM funciona num processo Rust se o ficheiro `.winmd` da Microsoft estiver ao lado do programa.

### Erros internos do motor

Até ao passo 5, um erro interno do motor terminava a app sem mensagem. Agora:

- Cada função da fronteira apanha a falha, guarda o motivo e o sítio, e devolve um resultado vazio que a janela reconhece.
- A janela regista o erro no registo da sessão, mostra um aviso e **continua aberta**.
- Uma falha dentro da fila de instalação ou de uma operação de desinstalação termina só essa operação, com um erro visível; o motor não fica preso como ocupado.

Para o poder testar, o motor tem uma falha deliberada que só funciona nos modos de teste.

### A release

| Peça | Estado |
| --- | --- |
| `build-windows.ps1` | Constrói a 4.0, com `BUILD-INFO.json` (versão do Rust incluída, 56 ficheiros de entrada com o seu SHA-256), avisos e somas de verificação. A assinatura opcional ficou como estava. |
| `.github/workflows/windows.yml` | Corre as verificações do catálogo e dos idiomas, os testes do motor, a build, o teste de movimento, o autoteste e o empacotamento. O trabalho de publicação passou a responder ao ramo `release/4.0.0`. |
| `scripts/package-release.ps1` | O registo `CI-reliability.txt` deu lugar a `CI-engine.txt`, o dos testes do motor. |
| `tests/elastic-motion.ps1` | Adaptado ao executável da 4.0. Passa nas duas formas, sem janela e com janela. |
| `tests/reliability.ps1` | Não adaptado: testa os ajudantes C# da 3.6. As mesmas regras são testadas na 4.0 pelos testes do motor e pelo oráculo. |
| Notas e documentação | `docs/releases/4.0.0.md`, `CHANGELOG.md`, `README.md`, `docs/DEVELOPING.md`, `docs/VALIDATION.md`. |
| Versão | 4.0.0 no motor, no executável e no manifesto. |

Nada foi publicado. Não toquei em `main` nem em nenhum ramo `release/*`.

### Resultado no Actions

No commit `2cf87e2`, os dez trabalhos terminaram: nove com sucesso e o de publicação ignorado, como esperado fora de `release/4.0.0`.

| Trabalho | Resultado |
| --- | --- |
| Build de release e empacotamento (`headless`, Windows Server 2022) | Sucesso: testes do motor, build, teste de movimento, autoteste, ZIP portátil e ZIP de fontes com as somas verificadas |
| Aplicação 4.0, nas duas imagens | Autoteste 31 de 31; a 3.6.0 publicada atualizou-se para a 4.0.0.0 |
| Motor Rust, nas duas imagens | Oráculo: 1552 casos, 1532 idênticos, 0 por explicar. App fictícia removida, analisada e limpa pela fronteira. Sumatra PDF instalado pela fila no Windows Server 2025 |
| Funções puras e observações da 3.6, nas duas imagens | Reproduzidas byte a byte |

Os executáveis construídos no Actions têm 3 940 864 e 3 940 352 bytes; o deste PC tem 3 942 912.

## O que não foi testado

Tudo o que sei que não foi verificado na 4.0, junto num só sítio.

### Pela janela

- **Nenhuma remoção real.** No teu PC os testes recuam sempre e o motor recusa remover; o Actions não tem ambiente de trabalho. Remover, analisar vestígios e limpar só foram exercidos pela fronteira do motor.
- **A janela de revisão dos vestígios e o resumo da limpeza** nunca foram abertos num teste.
- **Parar a meio** uma fila de instalação ou uma remoção, e **fechar a janela** enquanto uma fila corre.
- **Uma instalação real.** Na janela a fila só correu com o WinGet de substituição. As páginas das apps guiadas são registadas, não abertas.
- **As janelas de ficheiro do Windows:** guardar e carregar seleções, guardar um instantâneo, guardar os diagnósticos.
- **«Open detailed log».** O teste confirma quando o botão aparece; não carrega nele, porque abriria o Bloco de notas.
- **Repetir uma instalação falhada.** O botão não pode aparecer nesta versão (ver o passo 6), por isso o caminho que vai dele até à seleção nunca correu.
- **Atualizações:** verificar, descarregar e «Restart and update» a partir das definições.
- **Gravar definições em modo normal.** A gravação só foi testada no motor, numa pasta temporária.
- **O aviso de erro interno numa fila de instalação.** Foi testado com um botão de teste e numa operação de desinstalação; o mesmo caminho na fila de instalação não.
- **Aspeto e acessibilidade:** alto contraste; mudança de tema ou de cor do Windows com a app aberta; 48 dos 51 idiomas; animações (só os limites matemáticos e os estados finais são testados); leitores de ecrã reais; atalhos de teclado (Ctrl+F, F1); DPI e vários monitores; janela no tamanho mínimo.
- **Os testes de interface da 3.6 não têm equivalente na 4.0:** `scrolling`, `appearance`, `backdrop`, `startup-opening`, `cleanup-ui`, `uninstall-queue` e `screenshots` conduzem a aplicação PowerShell e não foram adaptados.

### No motor e no sistema

- **Remoções de apps verdadeiras.** Só apps fictícias com um desinstalador de substituição. Os cenários reais da 3.5 no Windows Sandbox (7-Zip, Notepad++) não foram repetidos.
- **Registos da máquina (`HKLM`), vista de 32 bits, MSI e apps da Store** na remoção. Os cenários são todos do utilizador atual.
- **Um desinstalador que eleva pelo UAC e lança um processo filho**, contra o motor Rust. O cenário manual existe em `oracle/manual/` e só correu com a 3.6.
- **Parar uma remoção a meio.** Não há teste que o cubra, nem no motor.
- **Instalações reais além de uma.** Só o Sumatra PDF, no Windows Server 2025. Falhas reais do WinGet, dependências reais e pedidos de reinício não foram provocados.
- **O inventário completo.** Não existe nesta versão; o estado «Not installed» nunca ocorre.
- **Windows 10**, outros PCs, outras versões do WinGet. A imagem do Windows Server 2022 não tem WinGet.
- **Os teus dados reais da 3.6.** Um arranque normal leu as tuas definições. O teu histórico e as tuas seleções guardadas não foram lidos pela 4.0.
- **A divergência 4 da Fase 2** (aceitar os termos da origem ao verificar) não tem cobertura do oráculo, e a fila de instalação não foi comparada com uma gravação da 3.6.
- **Fuzzing.**

### Na release

- **A publicação.** O trabalho `publish-stable` só corre com um push para `release/4.0.0`, que é teu. Nunca correu para a 4.0.
- **O caminho da 3.6 que consulta o GitHub e descarrega a release.** Só pode ser exercido com a 4.0 publicada. O passo seguinte, aplicar a atualização, está provado.
- **A assinatura de código** que `build-windows.ps1` aceita como opção, e **a build a partir do ZIP de fontes**, sem Git.
- **Os testes de interface no Actions.** Precisam de um ambiente de trabalho e só correram no teu PC.
- **Os modos de teste num caminho comprido.** Guardam a cache ao lado do executável e falham quando o caminho passa o limite do Windows. Encontrei-o hoje nesta pasta de trabalho; o modo normal usa a pasta do utilizador e não é afetado.
- **As medições** vêm de um só PC, e as do passo 6 foram feitas com outra configuração de ecrã. O primeiro arranque depois de reiniciar o PC nunca foi medido.

## Otimização do arranque

Medi primeiro onde o tempo se gastava, depois testei cada corte em separado.

Onde estavam os 594 ms:

| Etapa | Tempo |
| --- | --- |
| Do processo criado até ao início do programa | 30 ms |
| Carregar o motor Rust | 12 ms |
| Iniciar o WPF e carregar a janela | 175 ms |
| Construir os 325 cartões | 113 ms |
| Mostrar a janela e desenhar o primeiro fotograma | 225 ms |

O que testei:

| Mudança | Efeito | Aplicada |
| --- | --- | --- |
| Criar a janela de sistema antes de construir os cartões, para o WPF iniciar a placa gráfica em paralelo | Cerca de 130 ms a menos | Sim |
| Preencher o interior de um cartão só quando ele chega perto do ecrã, e ler o catálogo em registos simples em vez de JSON | Cartões de 113 para 46 ms | Sim |
| Carregar o motor e ler o catálogo noutro fio enquanto o WPF inicia | Cerca de 10 ms a menos | Sim |
| Extrair o motor por fluxo em vez de o carregar todo em memória | 15 MB a menos no pico | Sim |
| Desligar a luz ambiente ou o desfoque dos painéis | Nenhum | Não |
| Desenhar por software em vez de usar a placa gráfica | 336 ms e 76 MB | Não: decisão tua, ver abaixo |

Nenhuma das mudanças aplicadas altera o que se vê. A captura de ecrã depois da otimização é igual à de antes.

Onde estão os 444 ms agora:

| Etapa | Tempo |
| --- | --- |
| Do processo criado até ao início do programa | 30 ms |
| Iniciar o WPF e carregar a janela | 176 ms |
| Construir os cartões e as categorias | 45 ms |
| Mostrar a janela e desenhar o primeiro fotograma | 166 ms |

O que resta é quase todo do próprio WPF: iniciá-lo, e esperar que a placa gráfica fique pronta, o que demora cerca de 165 ms desde que a janela de sistema existe.

### A memória

| Momento | Working set |
| --- | --- |
| Início do programa | 20 MB |
| WPF iniciado e janela carregada, ainda sem conteúdo | 52 MB |
| Cartões construídos | 62 MB |
| Primeiro fotograma desenhado | 100 MB |

A memória gerida pelo .NET é de 8 MB. Os 38 MB entre os cartões e o primeiro fotograma são da placa gráfica e do desenho. Com a placa gráfica não vejo como chegar aos 80 MB.

### Desenho por software: a única forma de cumprir os 80 MB

Numa variante de teste, não aplicada, mandei o WPF desenhar por software: 336 ms e 76 MB. Cumpre os dois limites.

O custo é que as animações elásticas e o desfoque dos painéis passam a ser desenhados pelo processador. Não medi a fluidez, e num PC mais fraco do que este a diferença pode notar-se. A 3.6 usa a placa gráfica.

## Um erro meu, encontrado e corrigido

A pesquisa do protótipo WPF da Fase 3, que tinha passado para este executável, não era a da 3.6: partia o texto em palavras e escondia os cartões sem os reordenar, o que podia deixar cartões em branco depois de uma pesquisa. Substituí-a pela lógica de `Update-Filter` da 3.6. O teste de interface novo cobre este caso.

## Verificações

| Verificação | Onde correu | Resultado |
| --- | --- | --- |
| Autoteste (`--self-test`) | Neste PC | 31 de 31 |
| Teste do histórico e dos diagnósticos por UI Automation (`app/tests/history-ui.ps1`) | Neste PC | 23 de 23; 19 de 19 sem ler o WinGet |
| Falha interna do motor: comunicada e não fatal, na fronteira, numa operação e na janela | Neste PC | Passa |
| Teste de movimento sobre o executável da 4.0 (`tests/elastic-motion.ps1`), sem janela e com janela | Neste PC | Passa |
| Build de release (`build-windows.ps1`) e autoteste do executável resultante | Neste PC | Constrói; 31 de 31 |
| Teste da desinstalação por UI Automation, só de leitura (`app/tests/uninstall-ui.ps1`) | Neste PC | 17 de 17 |
| Desinstalação pela fronteira do motor: os modos de teste só leem | Neste PC | Passa |
| Teste da fila por UI Automation, com o WinGet de substituição (`app/tests/queue-ui.ps1`) | Neste PC | 19 de 19 |
| Fila pela fronteira do motor, com o WinGet de substituição: execução, recusa, paragem | Neste PC | Passa |
| Teste da biblioteca por UI Automation (`app/tests/library-ui.ps1`) | Neste PC | 27 de 27 |
| Teste das definições por UI Automation (`app/tests/settings-ui.ps1`) | Neste PC | 15 de 15 |
| Motor: formatação, lints e testes, incluindo 19 testes novos de definições, idiomas e biblioteca | Neste PC | Limpos |
| Um arranque em modo normal, com as definições reais deste utilizador | Neste PC | Abriu; 0 ms de processador em 10 s de repouso; ficheiro de definições intacto |
| Tudo o anterior no Actions | Ver a última execução do ramo | — |

O teste da biblioteca conduz a janela por fora, como um leitor de ecrã: confirma que os 325 cartões existem e têm nome, que um cartão fora do ecrã só é preenchido quando se chega a ele, que a pesquisa deixa só os cartões certos e desenhados, que a seleção sobrevive à pesquisa, que a dependência aparece antes da app que precisa dela, e que remover uma linha limpa a seleção. Desde o passo 3 cobre também: uma app seleciona o que exige e isso conta; remover uma dependência remove quem dependia dela; a janela de detalhes; o filtro por categoria; um perfil incluído; e a vista de instaladas, que neste PC mostrou as mesmas 25 apps que o motor tinha encontrado na Fase 2.

O teste das definições abre a página, muda o idioma para português e para árabe, confirma os textos traduzidos e que a navegação passa para o lado direito em árabe, muda o tema e a cor de destaque, e confirma que a seleção feita antes sobrevive a tudo isso. No fim confirma que o ficheiro de definições do utilizador não foi tocado.

## A ponte de atualização

Era a decisão em aberto desde a Fase 0. O atualizador da 3.6 só aceita um `1nstall.exe` que seja um assembly .NET chamado `1nstall` com a versão da release. Com a interface em WPF, o executável da 4.0 já é isso. Não é preciso stub nem release-ponte.

| Verificação | Onde correu | Resultado |
| --- | --- | --- |
| A condição de identidade de `update-helper.cs` aplicada ao executável da 4.0 | Neste PC e no Actions | Aceite: `1nstall` 4.0.0.0 contra a release 4.0.0 |
| A mesma condição aplicada ao executável da 3.6, como controlo | Neste PC | Recusado, como esperado |
| O executável publicado da 3.6.0 a correr o seu próprio passo `--apply-update` contra a 4.0 | Actions, Windows Server 2022 e 2025 | Substituiu-se pela 4.0, guardou a cópia anterior, e a 4.0 resultante passou o autoteste |

O que este teste não cobre: a parte da 3.6 que consulta a API do GitHub e descarrega a release. Essa só pode ser exercitada com uma release 4.0 publicada.

## Objetivo da Fase 0

| Limite | Objetivo | 4.0 agora |
| --- | --- | --- |
| Pronta e ociosa | abaixo de 500 ms | 473 ms no passo 5; 390 ms nas condições do passo 6 |
| Pico de working set | abaixo de 80 MB | 113 MB no passo 5; 87 MB nas condições do passo 6 |
| Executável | abaixo de 12 MB | 3,9 MB |
| Dependências | só Windows e WinGet | .NET Framework 4.8, que vem com o Windows 10 e 11. O Windows PowerShell ainda é chamado para listar as apps da Store |

A janela de abertura da 3.6 mostra o primeiro fotograma aos 445 ms. A 4.0 mostra a janela principal completa aos 479 ms. Deixou de haver razão para a portar.

## Correção a relatórios anteriores

Na Fase 0 escrevi que o relógio de arranque da 3.6 excluía a criação do processo, e repeti-o na Fase 3. Está errado: o relógio da 3.6 soma o tempo desde que o Windows criou o processo (`launcher.cs:21-28`). Os números não mudam; a comparação entre a 3.6 e os protótipos é direta. Os dois relatórios foram corrigidos e a correção está assinalada neles.

## O que falta

A interface da 3.6 é comandada por 79 funções PowerShell, em cerca de 2 500 linhas, que passaram para C# em seis passos, com a lógica no motor Rust.

| Passo | Conteúdo | Estado |
| --- | --- | --- |
| 1 | Executável único, fronteira com o motor, ponte de atualização, modos de teste, arranque otimizado | Feito |
| 2 | Definições, tema, cor de destaque, vidro e os 51 idiomas, incluindo os dois da direita para a esquerda | Feito |
| 3 | Biblioteca completa: filtros por categoria, vistas, perfis, detalhes, guardar e carregar seleções | Feito |
| 4 | Fila de instalação: confirmação, progresso, registos, cancelamento | Feito |
| 5 | Desinstalação: lista de apps, fila, análise e limpeza de vestígios, cópias de segurança | Feito |
| 6 | Histórico, diagnósticos, erros internos do motor, e a release: script de build, CI, testes da 3.6 adaptados, notas | Feito |

Os passos 4 e 5 só podem ser testados neste PC com o WinGet e o desinstalador de substituição. Instalações e remoções reais continuam a correr apenas no Actions.

## Limites

A lista completa do que não foi testado está na secção «O que não foi testado».

- **Um só PC.** Os tempos e a memória foram medidos numa máquina topo de gama. A memória da placa gráfica depende do controlador.
- **As compilações não são reprodutíveis bit a bit.** As duas imagens do Actions produziram executáveis do mesmo tamanho com SHA-256 diferentes.
- **O executável não é assinado**, tal como o da 3.6.
- **Nenhuma remoção foi conduzida pela janela.** No teu PC o teste recua sempre; no Actions não há ambiente de trabalho. A remoção, a análise e a limpeza estão testadas pela fronteira do motor, não pelos botões.
- **A janela de revisão dos vestígios não foi aberta em nenhum teste**, porque só aparece depois de uma remoção real.
- **Parar a meio de uma fila não foi conduzido pela interface.** O programa de substituição termina de imediato, por isso não há tempo para carregar no botão; a paragem está testada no motor.
- **Guardar e carregar seleções não foi conduzido pela interface.** As janelas de escolha de ficheiro do Windows não se deixam conduzir de forma fiável; a leitura e a escrita dos ficheiros estão testadas no motor.
- **Os testes de interface precisam de um ambiente de trabalho interativo** e por isso só correm neste PC, não no Actions.
- **Não verifiquei:** o alto contraste; a app a seguir uma mudança de tema ou de cor do Windows enquanto está aberta; o descarregamento e a aplicação de uma atualização a partir da página; gravar definições pela interface em modo normal (a gravação só foi testada no motor, numa pasta temporária); e o aspeto dos outros 48 idiomas.

## Decisões que preciso de ti

A memória ficou decidida em 2026-11-18: aceitas cerca de 100 MB com a placa gráfica, como a 3.6 desenha.

1. **O inventário completo do WinGet**, descrito no passo 6: integrá-lo antes de publicar, ou publicar a 4.0 sem ele, como as notas da versão já dizem.
2. **A diferença de acessibilidade nos cartões**, descrita no passo 3: aprovar ou reverter.
3. **As fontes da 3.6 que a 4.0 já não usa** (`vexan_installers.ps1`, `src/launcher.cs`, `src/startup.cs`, `src/ui-helper.cs`, `src/ui.csproj`, `src/settings.ps1`, `src/manager-ui.ps1` e os testes que as conduzem): manter ou remover. `src/package-helper.cs` e `src/uninstall-helper.cs` têm de ficar enquanto o oráculo existir.
4. **Publicar.** Juntar `v4/app` a `main` e fazer o push de `release/4.0.0` são passos teus.
