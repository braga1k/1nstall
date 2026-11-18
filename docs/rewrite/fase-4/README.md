# Fase 4 — Interface, migração e release

Estado em 2026-11-18, depois de quatro dos seis passos e de uma ronda de otimização do arranque. O código está no ramo `v4/app`, nas pastas `app/` e `engine/ffi/`. A 3.6 na raiz do repositório continua intocada e a compilar.

## Resumo

Escolheste a interface WPF sobre o motor Rust. Existe um `1nstall.exe` 4.0 num único ficheiro, sem PowerShell, e está provado que a 3.6 se atualiza para ele sem release intermédia. Com a biblioteca, a fila de instalação, as definições, o tema e os 51 idiomas já incluídos, fica pronto em 473 ms, abaixo do limite de 500 ms, com o aspeto e as animações intactos. O limite de memória de 80 MB não é atingido: fica em 116 MB.

A fase não está concluída: a 4.0 já instala, mas ainda não desinstala, e faltam o histórico e a release.

## O executável da 4.0

| Medida | 3.6.0 | Passo 1, antes de otimizar | Passo 1, otimizado | Passo 2 | Passo 3 | Passo 4 |
| --- | --- | --- | --- | --- | --- | --- |
| Tamanho | 2 699 264 bytes | 3 098 624 bytes | 3 064 320 bytes | 3 130 880 bytes | 3 231 744 bytes | 3 277 312 bytes |
| Pronta e ociosa, a quente | 1 996 ms | 594 ms | 444 ms | 467 ms | 479 ms | 473 ms |
| Primeira execução, com extração do motor | 2 425 ms | 763 ms | 501 ms | 563 ms | 569 ms | 559 ms |
| Pico de working set | 242 MB | 105 MB | 101 MB | 110 MB | 113 MB | 116 MB |
| Em repouso após 8 s (working set / privada) | não medido | não medido | 101 / 104 MB | 113 / 124 MB | 116 / 129 MB | 109 / 125 MB |
| Precisa, além do Windows | .NET Framework 4.8, PowerShell 5.1 | .NET Framework 4.8 | .NET Framework 4.8 | .NET Framework 4.8 | .NET Framework 4.8 | .NET Framework 4.8 |

Medido neste PC com a régua da Fase 0, mediana de 10 arranques a quente. No passo 4 os 10 arranques ficaram entre 468 e 483 ms.

**Estes números ainda vão subir um pouco, e a margem para os 500 ms é de 27 ms.** Faltam as páginas de desinstalação e de histórico. A partir do passo 3 a app pergunta ao WinGet o que está instalado logo que a janela abre, como a 3.6 faz; isso corre noutro processo e não entra no pico de memória acima.

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
| Autoteste (`--self-test`) | Neste PC | 22 de 22 |
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
| Pronta e ociosa | abaixo de 500 ms | 479 ms |
| Pico de working set | abaixo de 80 MB | 113 MB |
| Executável | abaixo de 12 MB | 3,1 MB |
| Dependências | só Windows e WinGet | .NET Framework 4.8, que vem com o Windows 10 e 11 |

A janela de abertura da 3.6 mostra o primeiro fotograma aos 445 ms. A 4.0 mostra a janela principal completa aos 479 ms. Deixou de haver razão para a portar.

## Correção a relatórios anteriores

Na Fase 0 escrevi que o relógio de arranque da 3.6 excluía a criação do processo, e repeti-o na Fase 3. Está errado: o relógio da 3.6 soma o tempo desde que o Windows criou o processo (`launcher.cs:21-28`). Os números não mudam; a comparação entre a 3.6 e os protótipos é direta. Os dois relatórios foram corrigidos e a correção está assinalada neles.

## O que falta

A interface da 3.6 é comandada por 79 funções PowerShell, em cerca de 2 500 linhas, que têm de passar para C#. O motor Rust já tem a lógica; falta expô-la pela fronteira e ligá-la à janela.

| Passo | Conteúdo | Estado |
| --- | --- | --- |
| 1 | Executável único, fronteira com o motor, ponte de atualização, modos de teste, arranque otimizado | Feito |
| 2 | Definições, tema, cor de destaque, vidro e os 51 idiomas, incluindo os dois da direita para a esquerda | Feito |
| 3 | Biblioteca completa: filtros por categoria, vistas, perfis, detalhes, guardar e carregar seleções | Feito |
| 4 | Fila de instalação: confirmação, progresso, registos, cancelamento | Feito |
| 5 | Desinstalação: lista de apps, fila, análise e limpeza de vestígios, cópias de segurança | Por fazer |
| 6 | Histórico, diagnósticos, verificação de atualizações, e a release: script de build, CI, testes da 3.6 adaptados, notas | Por fazer |

Os passos 4 e 5 só podem ser testados neste PC com o WinGet e o desinstalador de substituição. Instalações e remoções reais continuam a correr apenas no Actions.

## Limites deste passo

- **Um só PC.** Os tempos e a memória foram medidos numa máquina topo de gama. A memória da placa gráfica depende do controlador.
- **As compilações não são reprodutíveis bit a bit.** As duas imagens do Actions produziram executáveis do mesmo tamanho com SHA-256 diferentes.
- **O executável não é assinado**, tal como o da 3.6.
- **O botão de histórico não existe ainda**, e o botão Desinstalar ainda não faz nada.
- **Parar a meio de uma fila não foi conduzido pela interface.** O programa de substituição termina de imediato, por isso não há tempo para carregar no botão; a paragem está testada no motor.
- **Uma falha interna do motor termina a app sem mensagem.** O motor está compilado para abortar em caso de erro interno. Fica para o passo 6 fazê-lo devolver o erro à janela.
- **Guardar e carregar seleções não foi conduzido pela interface.** As janelas de escolha de ficheiro do Windows não se deixam conduzir de forma fiável; a leitura e a escrita dos ficheiros estão testadas no motor.
- **Os testes de interface precisam de um ambiente de trabalho interativo** e por isso só correm neste PC, não no Actions.
- **Não verifiquei:** o alto contraste; a app a seguir uma mudança de tema ou de cor do Windows enquanto está aberta; o descarregamento e a aplicação de uma atualização a partir da página; gravar definições pela interface em modo normal (a gravação só foi testada no motor, numa pasta temporária); e o aspeto dos outros 48 idiomas.

## Decisões que preciso de ti

A memória ficou decidida em 2026-11-18: aceitas cerca de 100 MB com a placa gráfica, como a 3.6 desenha.

1. **A diferença de acessibilidade nos cartões**, descrita no passo 3: aprovar ou reverter.
2. **A ordem dos passos 4 a 6**, se quiseres outra.
