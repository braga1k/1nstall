# Fase 4 — Interface, migração e release

Estado em 2026-11-19, depois dos seis passos, de uma ronda de otimização do arranque e de uma ronda de testes antes do lançamento (passo 7). O código está no ramo `v4/app`, nas pastas `app/` e `engine/`. As fontes da 3.6 continuam na raiz, como referência do oráculo; `build-windows.ps1` passou a construir a 4.0.

## Resumo

Escolheste a interface WPF sobre o motor Rust. Existe um `1nstall.exe` 4.0 num único ficheiro, sem PowerShell, e está provado que a 3.6 se atualiza para ele sem release intermédia. Com todas as páginas da 3.6 incluídas, fica pronto em 473 ms, abaixo do limite de 500 ms, com o aspeto e as animações intactos. O limite de memória de 80 MB não é atingido: fica em 113 MB.

Os seis passos estão feitos e a **4.0.0 foi publicada em 2026-11-19**, a partir do commit `e23d1af`, por ordem tua. As decisões que estavam em aberto foram tomadas no mesmo dia e estão no fim deste relatório. A ronda de testes do passo 7 encontrou um erro grave herdado da 3.6 na procura de vestígios, que está corrigido, e mais dois erros herdados, também corrigidos.

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

### Uma diferença intencional, aprovada

Na 3.6 um cartão só reage a cliques. Um leitor de ecrã que ative o cartão pela ação própria de acessibilidade muda o interruptor, mas a app não regista a seleção. Na 4.0 o cartão reage à mudança em si, seja por rato, teclado ou tecnologia de apoio. Para quem usa rato ou teclado nada muda. Aprovada em 2026-11-19, e estendida aos dois interruptores das Definições (passo 7).

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

### Um achado: o botão de repetir nunca aparecia

A 3.6 oferece «Refresh & review installation again» a uma instalação falhada quando o inventário diz que a app **não está instalada**. Esse estado só existe com um inventário completo, que a 3.6 obtém pelo PowerShell 7 e pelo módulo Microsoft.WinGet.Client, quando o utilizador os tem.

No fim do passo 6 a 4.0 lia apenas o `winget export`, que diz o que está instalado e não prova o que falta: o botão de repetir nunca aparecia, e uma app que o WinGet não lista ficava `Unknown`, nunca `Not installed`. Quem usava a 3.6 sem o PowerShell 7 e o módulo já via isto; quem os tinha perdia informação.

**Resolvido em 2026-11-19, por decisão tua:** o motor repõe o caminho opcional da 3.6 (`Structured` e `Inventory` de `src/package-helper.cs`). Com o PowerShell 7 em `Program Files` e o módulo instalado, o inventário é completo; sem eles, cai no `winget export`, com as mesmas mensagens. A 4.0 nunca instala nenhum dos dois. O teste do histórico dá ao motor um inventário completo feito pelo teste e segue o botão de repetir até à seleção. A leitura direta pela API COM, sem PowerShell, continua por fazer.

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

## Passo 7: os testes antes do lançamento

Pediste que testasse tudo o que a secção «O que não foi testado» listava. Esta secção diz o que passou a estar testado, onde, e o que isso encontrou. O que continua por testar está na secção seguinte.

### Um erro grave, herdado da 3.6, encontrado numa limpeza real

Numa sessão real com a 4.0, uma app estava instalada em `C:\Program Files\Common Files\OFX\Plugins\`, a pasta que todos os plug-ins OpenFX partilham. A regra de procura de vestígios, portada da 3.6 sem alterações (`Names`, em `src/uninstall-helper.cs:405`), aceitava o nome da pasta de instalação de uma app verificada como nome do produto, fosse qual fosse. «Plugins» passou a ser um nome dessa app, e a revisão de vestígios ofereceu, como `Name match` dela, as pastas e chaves de registo chamadas «Plugins» de outros quatro programas. A limpeza confirmada levou três pastas para a Reciclagem e três chaves de registo, com cópia.

Nada se perdeu: as pastas foram repostas da Reciclagem e as chaves a partir das cópias `.reg` que a limpeza guarda. A 3.6 publicada tem o mesmo erro.

A correção, em `engine/core/src/uninstall.rs`:

- o nome da pasta de instalação só conta como nome do produto quando partilha o nome do produto (um contém o outro);
- palavras que dão nome a pastas partilhadas (`plugins`, `vst3`, `components`, `shared`, `common`, `tools`, `library` e semelhantes) nunca são nome de produto.

É uma diferença intencional em relação à 3.6, a sétima da lista da Fase 2. Muda cinco casos gravados do oráculo, registados em `engine/oracle-divergences.json`. O efeito do outro lado: quando a pasta de instalação tem um nome sem relação com o do produto, essa pasta e os vestígios de executáveis dentro dela deixam de ser oferecidos. Os testes novos em `engine/core/tests/properties.rs` reproduzem o caso real com nomes inventados e fixam os casos que a mesma sessão resolveu bem.

### Outros achados

| Achado | Origem | O que fiz |
| --- | --- | --- |
| Uma limpeza que falhou ficou no histórico como `Failed` com o motivo vazio: algumas falhas da Reciclagem do Windows não trazem texto | 4.0 | Corrigido: o motivo passa a ter sempre texto e o código do Windows |
| A opção de assinatura de `build-windows.ps1` exigia um servidor de carimbo de tempo `https://`, que o `Set-AuthenticodeSignature` do Windows PowerShell 5.1 recusa. Nunca pôde assinar | 3.6 | Corrigido: pede `http://`. Uma build assinada com um certificado de teste passa no Actions |
| Uma fila de instalação terminada por erro interno do motor dizia «Queue finished · 0 failed» | 4.0, passo 6 | Corrigido: a linha de estado diz que terminou por erro interno |
| Os modos de teste falhavam numa pasta de caminho comprido | 4.0 | Corrigido: nesse caso a cache do motor vai para a pasta temporária. Autoteste 31 de 31 a partir de um caminho de 219 caracteres |
| Ao mudar diretamente entre dois idiomas cuja tradução só difere em maiúsculas (eslovaco «Téma», húngaro «téma»), o texto fica com a grafia do primeiro até reiniciar. Acontece em três idiomas | 3.6: compara os textos sem distinguir maiúsculas | Não alterei. O teste assinala-o numa nota |
| Os dois interruptores das Definições (cor de destaque e atualizações automáticas) escutavam o clique. Mudados pela ação de alternar da automação, que algumas ferramentas de acessibilidade usam, mudavam no ecrã mas não eram gravados | 3.6 | Corrigido em 2026-11-19, por decisão tua: reagem à mudança em si, como os cartões. O teste do modo normal confirma que gravam das duas maneiras |
| Nos diagnósticos, um caminho só é removido se começar por uma letra de unidade ou por `\\` | 3.6 | Não alterei. A janela já pede para rever o texto antes de o partilhar |
| No tamanho mínimo da janela, a sugestão da caixa de pesquisa fica cortada («Search apps · Ctrl+») | 3.6: é o mesmo XAML | Não alterei |
| Numa máquina onde os termos da origem do WinGet nunca foram aceites, `winget export` não responde, e a app fica sem inventário até à primeira instalação | Comportamento conhecido desde a Fase 1 | Nada; visto de novo no Actions |

### O que passou a estar testado neste PC

Tudo em modo de teste, sem tocar no perfil do utilizador e sem instalar nem remover nada.

| Teste | O que cobre | Resultado |
| --- | --- | --- |
| `app/tests/dialogs-ui.ps1` | As janelas de ficheiro do Windows: guardar a seleção, cancelar, carregar com pré-visualização, recusar um ficheiro danificado com o motivo, um pacote fora do catálogo, guardar os diagnósticos tal como foram revistos, e o instantâneo das apps instaladas, que volta a carregar | 26 de 26 |
| `app/tests/queue-ui.ps1`, três partes novas | Parar a fila a meio (o instalador em curso acaba, a app seguinte fica «Cancelled · not started»); fechar a janela com a fila a correr (a janela fica até o instalador acabar); erro interno dentro da fila | 36 de 36 |
| `app/tests/window-ui.ps1` | Tamanho mínimo (para em 1040 × 540 com os controlos dentro da janela, nas páginas de instalar e desinstalar); maximizar, restaurar e minimizar; um nome em cada controlo, nas quatro páginas; os 51 idiomas contra `locales.json`, com os dois da direita para a esquerda espelhados; os dois temas desenhados | 18 de 18 |
| `engine/harness/tests/hostile_files.rs` | Trinta mil cópias danificadas dos ficheiros que o motor lê (definições, vista, histórico de operações, histórico de remoções, seleções guardadas): nenhuma faz o motor falhar, um histórico ilegível nunca é reescrito, uma seleção danificada só oferece apps do catálogo | 5 de 5 |
| `engine/harness/tests/install_sequence.rs` | As linhas de comando que uma instalação envia ao WinGet, comparadas com a 3.6 a correr ao vivo com o mesmo WinGet de substituição: cinco instalações, mesmos comandos e mesmos resultados; a exportação que verifica difere só na opção `--accept-source-agreements` | Passa |
| `engine/harness/tests/real_profile.rs` | Os ficheiros reais de um utilizador da 3.6, lidos pelas classes da 3.6 e pelo motor Rust: 35 operações e 14 apps removidas, com a mesma impressão digital | Idênticos |

O teste dos ficheiros danificados gera os danos a partir de uma semente fixa: cortes, bits trocados, pedaços de JSON fora do sítio, repetições, ruído, aninhamento profundo e UTF-16. Não é fuzzing guiado por cobertura.

### O que uma sessão real do autor acrescentou

No mesmo dia, a 4.0 foi usada em modo normal num PC com Windows 11: uma instalação real pelo WinGet, verificada, e catorze remoções reais pela janela, com pedidos do UAC, apps registadas na máquina e um MSI. Treze terminaram com sucesso à primeira; uma devolveu um código de erro e foi dada como removida na verificação seguinte. A revisão de vestígios e a limpeza correram até ao fim, com cópias de segurança. Foi esta sessão que mostrou o erro das pastas partilhadas. Li os registos; não conduzi a sessão.

### O que passou a estar testado no Actions

Os testes de interface correm no Actions: as máquinas têm ambiente de trabalho. Há um trabalho novo, `Window tests`, nas duas imagens, e um trabalho `release-checks`.

Em modo normal, em máquinas descartáveis (`app/tests/disposable-ui.ps1`):

- **O tema do Windows com a app aberta:** a janela passa de escura a clara e de volta quando o tema das apps muda no Windows.
- **Alto contraste ligado com a app aberta:** a janela continua desenhada e todas as páginas abrem; ao desligar, volta ao tema que o Windows repõe.
- **Definições:** tema e idioma gravados; o interruptor das atualizações gravado a cada toque da tecla de espaço; nenhum ficheiro temporário deixado; o arranque seguinte abre no idioma e no tema gravados; a vista da biblioteca é lembrada.
- **«Check now»:** responde «1nstall is up to date.».
- **Remoção pela janela:** uma app fictícia é selecionada, revista e removida; a revisão de vestígios abre, oferece só as duas pastas dela, nada vem escolhido, o consentimento sozinho não chega, «Select linked paths» escolhe só a pasta de instalação registada, «Select all» escolhe tudo; a limpeza termina com o resumo, as pastas saem do sítio, a cópia de segurança regista os itens e o histórico mostra a remoção e cada limpeza.
- **Parar a meio e fechar a janela:** com duas apps na fila e um desinstalador que lança um processo filho, «Stop» é aceite, a janela não fecha enquanto o desinstalador trabalha, a primeira app é removida, a segunda fica por remover, e a janela fecha depois.

Uma atualização pelas Definições (`app/tests/update-ui.ps1`): uma build do mesmo código numerada 3.5.0 encontra a última release publicada, descarrega-a, verifica-a, oferece «Restart and update», substitui-se por ela e guarda a cópia anterior. Até à publicação essa release era a 3.6.0; desde então é a 4.0.0, e o teste compara com a soma de verificação que a própria release anuncia.

O teclado, com teclas reais (`window-ui.ps1 -Keyboard`): Ctrl+F vai para a pesquisa, escrever filtra, espaço seleciona um cartão, F1 abre os detalhes, Esc fecha-os, Tab avança, Ctrl+F na página de desinstalar vai para a pesquisa dela, e Alt+F4 fecha a aplicação.

No motor (`uninstall_boundary.rs`): uma app fictícia registada na máquina, na vista de 32 bits, com um desinstalador que é lançado elevado, devolve de imediato e deixa o trabalho a um processo filho, é removida, analisada e limpa; e uma fila de duas apps em que se pede para parar durante a primeira termina com a primeira removida e a segunda intacta.

Na release (`scripts/release-checks.ps1`): o ZIP de fontes, sozinho e sem Git, constrói a aplicação a partir dos mesmos ficheiros da release e o executável passa o autoteste; a build assina com um certificado de teste, a assinatura fica válida e com carimbo de tempo, e o executável assinado passa o autoteste e continua aceite pela condição de identidade do atualizador da 3.6.

Apps reais, pela janela, no Windows Server 2025 (`disposable-ui.ps1 -Real`), com o WinGet 1.11.510:

- **Instalação:** 7-Zip, Notepad++, PuTTY e WinSCP selecionados na biblioteca e instalados pela fila. A fila terminou com «0 failed», cada app ficou «Success» com a versão verificada, e o WinGet lista as quatro. O 7-Zip já vinha na imagem: o WinGet respondeu «já instalado» e a verificação confirmou-o.
- **«Open detailed log»:** abre o Bloco de notas no registo dessa instalação.
- **Remoção:** as quatro apps selecionadas na página de desinstalar e removidas em fila pelos seus próprios desinstaladores: um executável registado na máquina (7-Zip), um NSIS que se relança a si próprio (Notepad++), um MSI (PuTTY) e um Inno Setup do utilizador atual (WinSCP). Um ajudante do teste respondeu aos diálogos dos desinstaladores, como faria a pessoa. As quatro terminaram em «Success» e os quatro registos desapareceram do Windows.
- **Vestígios:** a revisão ofereceu quatro itens, todos de apps acabadas de remover: a pasta de dados do Notepad++, as chaves `Software\7-Zip` e `Software\Notepad++`, e um vestígio do WinSCP na lista de saltos. O teste recuou sem limpar.
- **Uma app da Microsoft Store** (Feedback Hub, que vinha na imagem) removida pela janela: «Success», e o pacote deixou de existir para o utilizador.

Nas primeiras corridas esta parte não terminava. A causa era do teste: a aplicação tinha lançado o desinstalador e esperava pelo diálogo dele, como está desenhada, e o ajudante não encontrava o botão.

### Resultado no Actions

No commit `201d8fe` (antes da reescrita do ramo, `c65b3bd`), depois de seis corridas. As cinco primeiras serviram para acertar os testes novos com o ambiente do Actions; cada falha foi investigada e nenhuma era da aplicação, salvo a opção de assinatura, corrigida.

| Trabalho | Windows Server 2022 | Windows Server 2025 |
| --- | --- | --- |
| Motor Rust: 77 testes, oráculo, cenários de remoção | 77 a passar; oráculo 1552 casos, 0 por explicar, 11 divergências declaradas | igual; e o Sumatra PDF instalado pela fila |
| Aplicação: build, autoteste, a 3.6.0 atualiza-se para a 4.0 | 31 de 31; passa | 31 de 31; passa |
| Biblioteca | 24 de 24 (sem WinGet) | 27 de 27 |
| Definições | 15 de 15 | 15 de 15 |
| Página de desinstalação, só leitura | 17 de 17 | 17 de 17 |
| Histórico e diagnósticos | 19 de 19 (sem WinGet) | 23 de 23 |
| Fila com o WinGet de substituição | 36 de 36 | 36 de 36 |
| Janelas de ficheiro e «Open detailed log» | 23 de 23 | 25 de 25 |
| Janela, idiomas, temas e teclado | 28 de 28 | 28 de 28 |
| Atualização pelas Definições | 9 de 9 | 9 de 9 |
| Modo normal: tema e alto contraste do Windows, definições, remoção e limpeza, parar a meio | 34 de 34 | 34 de 34 |
| Apps reais: instalar, remover, app da Store | sem WinGet nesta imagem | 15 de 15 |
| Verificação da release (`release-checks`) | 11 de 11 | não corre nesta imagem |

Os resultados do Windows Server 2022 para os testes de janela são os da corrida anterior (`8c81715`, antes `b934236`), com o mesmo código da aplicação; na última corrida esse trabalho ainda decorria quando li os resultados.

Arranque numa máquina do Actions, sem placa gráfica, em três corridas: 2,8 a 3,4 s no primeiro arranque; depois mediana entre 261 e 362 ms; pico de working set de 98 MB.

Depois das decisões de 2026-11-19, no commit `ca2d743`, tudo o anterior passou de novo nas duas imagens, com o teste do histórico em 27 verificações (inclui o botão de repetir) e o do modo normal em 36 (os interruptores das Definições gravam das duas maneiras). Duas notas dessa corrida:

- No Windows Server 2022 o GitHub não respondeu à verificação de atualizações, por limite de pedidos por endereço, e a atualização pelas Definições não pôde ser exercida aí. No Server 2025 passou, 9 de 9.
- No Windows Server 2025 o módulo Microsoft.WinGet.Client instalou-se, mas o `Get-WinGetPackage` respondeu «Failed to create instance: -2147023174» (o serviço do WinGet não arranca naquela máquina), e a aplicação usou o `winget export`, como está desenhada. O inventário completo verdadeiro fica, por isso, sem prova numa máquina real. A mensagem do PowerShell 7 chegava ilegível, em CLIXML; passou a ser pedida em texto simples, e foi assim que se leu a causa na corrida seguinte (`e23d1af`).

No mesmo dia, uma segunda sessão real do autor com a build final: sete remoções pela janela e uma limpeza de 25 vestígios. Conferi cada item contra o estado do PC: os sete registos desapareceram, os 25 itens pertenciam todos às apps removidas, e nada de outros programas foi oferecido.

As corridas leem-se nas anotações de cada trabalho. As imagens da janela em cada estado ficam no artefacto `window-pictures-*`.

## O que não foi testado

Tudo o que sei que continua por verificar na 4.0, depois do passo 7.

### Pela janela

- **Repetir uma instalação falhada com o inventário verdadeiro.** O caminho do botão até à seleção está testado com um inventário completo feito pelo teste. Com o PowerShell 7 e o módulo verdadeiros, o inventário completo é pedido no Actions; ver o resultado da corrida.
- **Leitores de ecrã reais.** O teste confirma que cada controlo tem nome e que cada cartão tem descrição, que é o que um leitor lê. Nenhum leitor de ecrã foi usado.
- **As animações à vista.** São testados os limites matemáticos e os estados finais; ninguém as avaliou a olho nesta ronda.
- **DPI diferente de 100 %, vários monitores e ecrã tátil.** Este PC e as máquinas do Actions estão a 100 % com um só ecrã.
- **A mudança da cor de destaque do Windows com a app aberta.** O tema e o alto contraste foram testados; a cor de destaque não.
- **O teclado para lá dos atalhos listados no passo 7:** a ordem completa do Tab e o uso da app só com teclado, do princípio ao fim.
- **Os botões que abrem outros programas:** «Open logs», «Open backups», os endereços do GitHub e do donativo, e as páginas das apps guiadas em modo normal.
- **Os testes de interface da 3.6 sem equivalente:** os atributos nativos do fundo acrílico (`backdrop`), os casos-limite do scroll (`scrolling`) e a janela de abertura, que não foi portada.
- **A remoção de apps reais neste PC, por um teste.** Os testes daqui recuam sempre; as remoções reais pela janela correram no Actions e na sessão real do passo 7.

### No motor e no sistema

- **O pedido do UAC, de forma automática.** As máquinas do Actions já correm elevadas e não o mostram. Foi visto a funcionar na sessão real descrita no passo 7.
- **Um pedido de reinício real, uma falha real do WinGet e dependências reais.** As instalações reais feitas terminaram todas com sucesso; as falhas só foram provocadas com o WinGet de substituição.
- **O inventário completo num PC com o PowerShell 7 e o módulo já instalados pelo utilizador.** Este PC não tem o PowerShell 7.
- **Windows 10.** Não há onde o testar. O que há: um PC com Windows 11 e as imagens Windows Server 2022 e 2025 do Actions. A do Server 2022 não tem WinGet.
- **Seleções guardadas por um utilizador real da 3.6.** O histórico e as definições reais foram lidos; não procurei ficheiros de seleções no disco.
- **Fuzzing guiado por cobertura.** Há testes de propriedades e ficheiros danificados gerados por semente fixa.
- **Outros desinstaladores reais.** Foram removidas quatro apps (um executável da máquina, um NSIS, um MSI, um Inno Setup) e uma app da Store. O motor espera, sem limite de tempo, por tudo o que um desinstalador lança, como a 3.6; um desinstalador que deixe um programa aberto mantém a fila à espera até esse programa fechar. Não o vi acontecer nestas quatro.

### Na release

- **Um certificado de assinatura verdadeiro.** A opção de assinar foi testada com um certificado feito no momento. A release continua sem assinatura, e o workflow não tem passo para assinar na nuvem.
- **O primeiro arranque depois de reiniciar o PC.** Não foi medido, por decisão tua de não reiniciar este PC.
- **As medições com placa gráfica** vêm de um só PC. As máquinas do Actions não têm placa gráfica.
- **As compilações não são reprodutíveis bit a bit:** a build do ZIP de fontes e a da release têm o mesmo tamanho e SHA-256 diferentes.

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
| Autoteste (`--self-test`) | Neste PC e no Actions | 31 de 31 |
| Janelas de ficheiro por UI Automation (`app/tests/dialogs-ui.ps1`) | Neste PC e no Actions | 26 de 26; 23 e 25 no Actions, conforme há ou não inventário |
| Janela: tamanho, nomes, idiomas, temas (`app/tests/window-ui.ps1`) | Neste PC | 18 de 18; 28 de 28 no Actions, com o teclado |
| Modo normal em máquina descartável (`app/tests/disposable-ui.ps1`) | Actions, duas imagens | 34 de 34 |
| Atualização pelas Definições (`app/tests/update-ui.ps1`) | Actions, duas imagens | 9 de 9 |
| Build pelo ZIP de fontes, assinatura de teste e arranque (`scripts/release-checks.ps1`) | Actions | 11 de 11 |
| Teste do histórico e dos diagnósticos por UI Automation (`app/tests/history-ui.ps1`) | Neste PC | 23 de 23; 19 de 19 sem ler o WinGet |
| Falha interna do motor: comunicada e não fatal, na fronteira, numa operação e na janela | Neste PC | Passa |
| Teste de movimento sobre o executável da 4.0 (`tests/elastic-motion.ps1`), sem janela e com janela | Neste PC | Passa |
| Build de release (`build-windows.ps1`) e autoteste do executável resultante | Neste PC | Constrói; 31 de 31 |
| Teste da desinstalação por UI Automation, só de leitura (`app/tests/uninstall-ui.ps1`) | Neste PC e no Actions | 17 de 17 |
| Desinstalação pela fronteira do motor: os modos de teste só leem | Neste PC | Passa |
| Teste da fila por UI Automation, com o WinGet de substituição (`app/tests/queue-ui.ps1`) | Neste PC e no Actions | 36 de 36 |
| Fila pela fronteira do motor, com o WinGet de substituição: execução, recusa, paragem | Neste PC | Passa |
| Teste da biblioteca por UI Automation (`app/tests/library-ui.ps1`) | Neste PC e no Actions | 27 de 27; 24 sem WinGet |
| Teste das definições por UI Automation (`app/tests/settings-ui.ps1`) | Neste PC e no Actions | 15 de 15 |
| Motor: formatação, lints e 77 testes | Neste PC e no Actions | Limpos; 77 a passar |
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
- **Os números de arranque numa máquina sem placa gráfica** (Actions, Windows Server 2022, 4 processadores): cerca de 3 s no primeiro arranque, depois mediana de 317 a 362 ms, com 98 MB de pico.
- **Os testes de interface conduzem a janela por UI Automation.** Dizem o que a janela expõe e faz, não o que uma pessoa vê: o aspeto só foi verificado por imagens em poucos estados.

## Decisões

Tomadas por ti; as de 2026-11-19 seguiram as minhas recomendações.

| Decisão | Data | O que ficou |
| --- | --- | --- |
| Memória | 2026-11-18 | Aceitas cerca de 100 MB com a placa gráfica, como a 3.6 desenha |
| A regra das pastas partilhadas (passo 7) | 2026-11-19 | Mantém-se, como diferença intencional em relação à 3.6 |
| O inventário completo do WinGet (passo 6) | 2026-11-19 | Reposto o caminho opcional da 3.6, com o PowerShell 7 e o módulo quando existem |
| A ação de alternar da automação (passos 3 e 7) | 2026-11-19 | Aprovada nos cartões e estendida aos dois interruptores das Definições |
| As fontes da 3.6 que a 4.0 já não usa | 2026-11-19 | Removidas depois de publicar, num commit próprio: a aplicação PowerShell, o lançador e os testes de interface que a conduziam. Ficam `src/package-helper.cs`, `src/uninstall-helper.cs` e os dois testes de remoção que o oráculo corre, e `src/ui-helper.cs` com `src/ui.csproj`, de que o protótipo da Fase 3 depende. Tudo o resto está na etiqueta `v3.6.0` |
| Os nomes de programas de um PC real no histórico do ramo | 2026-11-19 | O ramo `v4/app` foi reescrito a partir de `eeade08`, com o mesmo conteúdo ficheiro a ficheiro: o primeiro commit do passo 7 e os seus testes usam nomes inventados. Os commits anteriores à reescrita deixaram de pertencer ao ramo |

Continuam contigo:

1. **Limpar do GitHub os commits anteriores à reescrita do ramo**, que ainda se abrem pelo endereço direto: apagar as corridas antigas do Actions e pedir a limpeza ao suporte do GitHub.

## A publicação

Em 2026-11-19, com a tua ordem expressa, depois de a corrida do Actions sobre `e23d1af` passar toda nas duas imagens:

1. `main` avançou de `80e584f` para `e23d1af`, sem forçar.
2. O ramo `release/4.0.0` foi criado no mesmo commit, e o trabalho `publish-stable` construiu, empacotou, criou a release em rascunho, verificou os ficheiros e publicou a `v4.0.0` às 15:18 UTC.

Conferido depois, com os ficheiros descarregados da release:

| Verificação | Resultado |
| --- | --- |
| Os dez ficheiros listados em `SHA256SUMS.txt` | Todos com o SHA-256 anunciado |
| `BUILD-INFO.json` | Versão 4.0.0, commit `e23d1af`, fontes limpas; o SHA-256 do executável coincide |
| O executável publicado | 3 953 152 bytes; assembly `1nstall` 4.0.0.0; autoteste 31 de 31 neste PC; sem assinatura |
| O ZIP portátil | Contém o mesmo executável |
| O que o atualizador da 3.6 lê na API do GitHub | Última release `v4.0.0`, publicada, com o `1nstall.exe` e o seu SHA-256 |
| Uma 3.6 verdadeira, no PC do autor, com atualizações automáticas | Descarregou a 4.0 três minutos depois da publicação, com o SHA-256 da release, aplicou-a sem erro e a 4.0 arrancou |
