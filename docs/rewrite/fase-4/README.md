# Fase 4 — Interface, migração e release

Estado em 2026-11-18, depois de dois dos seis passos e de uma ronda de otimização do arranque. O código está no ramo `v4/app`, nas pastas `app/` e `engine/ffi/`. A 3.6 na raiz do repositório continua intocada e a compilar.

## Resumo

Escolheste a interface WPF sobre o motor Rust. Existe um `1nstall.exe` 4.0 num único ficheiro, sem PowerShell, e está provado que a 3.6 se atualiza para ele sem release intermédia. Com as definições, o tema e os 51 idiomas já incluídos, fica pronto em 467 ms, abaixo do limite de 500 ms, com o aspeto e as animações intactos. O limite de memória de 80 MB não é atingido: fica em 110 MB.

A fase não está concluída: estão ligados a biblioteca de instalação e as definições, e ainda não instala nem remove nada.

## O executável da 4.0

| Medida | 3.6.0 | Passo 1, antes de otimizar | Passo 1, otimizado | Passo 2 |
| --- | --- | --- | --- | --- |
| Tamanho | 2 699 264 bytes | 3 098 624 bytes | 3 064 320 bytes | 3 130 880 bytes |
| Pronta e ociosa, a quente | 1 996 ms | 594 ms | 444 ms | 467 ms |
| Primeira execução, com extração do motor | 2 425 ms | 763 ms | 501 ms | 563 ms |
| Pico de working set | 242 MB | 105 MB | 101 MB | 110 MB |
| Em repouso após 8 s (working set / privada) | não medido | não medido | 101 / 104 MB | 113 / 124 MB |
| Precisa, além do Windows | .NET Framework 4.8, PowerShell 5.1 | .NET Framework 4.8 | .NET Framework 4.8 | .NET Framework 4.8 |

Medido neste PC com a régua da Fase 0, mediana de 10 arranques a quente. No passo 2 os 10 arranques ficaram entre 459 e 479 ms.

**Estes números ainda vão subir um pouco.** Faltam as páginas de desinstalação, histórico e perfis.

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
| Autoteste (`--self-test`) | Neste PC | 14 de 14 |
| Teste da biblioteca por UI Automation (`app/tests/library-ui.ps1`) | Neste PC | 13 de 13 |
| Teste das definições por UI Automation (`app/tests/settings-ui.ps1`) | Neste PC | 15 de 15 |
| Motor: formatação, lints e testes, incluindo 12 testes novos de definições e idiomas | Neste PC | Limpos |
| Um arranque em modo normal, com as definições reais deste utilizador | Neste PC | Abriu; 0 ms de processador em 10 s de repouso; ficheiro de definições intacto |
| Tudo o anterior no Actions | Ver a última execução do ramo | — |

O teste da biblioteca conduz a janela por fora, como um leitor de ecrã: confirma que os 325 cartões existem e têm nome, que um cartão fora do ecrã só é preenchido quando se chega a ele, que a pesquisa deixa só os cartões certos e desenhados, que a seleção sobrevive à pesquisa, que a dependência aparece antes da app que precisa dela, e que remover uma linha limpa a seleção.

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
| Pronta e ociosa | abaixo de 500 ms | 467 ms |
| Pico de working set | abaixo de 80 MB | 110 MB |
| Executável | abaixo de 12 MB | 3,1 MB |
| Dependências | só Windows e WinGet | .NET Framework 4.8, que vem com o Windows 10 e 11 |

A janela de abertura da 3.6 mostra o primeiro fotograma aos 445 ms. A 4.0 mostra a janela principal completa aos 467 ms. Deixou de haver razão para a portar.

## Correção a relatórios anteriores

Na Fase 0 escrevi que o relógio de arranque da 3.6 excluía a criação do processo, e repeti-o na Fase 3. Está errado: o relógio da 3.6 soma o tempo desde que o Windows criou o processo (`launcher.cs:21-28`). Os números não mudam; a comparação entre a 3.6 e os protótipos é direta. Os dois relatórios foram corrigidos e a correção está assinalada neles.

## O que falta

A interface da 3.6 é comandada por 79 funções PowerShell, em cerca de 2 500 linhas, que têm de passar para C#. O motor Rust já tem a lógica; falta expô-la pela fronteira e ligá-la à janela.

| Passo | Conteúdo | Estado |
| --- | --- | --- |
| 1 | Executável único, fronteira com o motor, ponte de atualização, modos de teste, arranque otimizado | Feito |
| 2 | Definições, tema, cor de destaque, vidro e os 51 idiomas, incluindo os dois da direita para a esquerda | Feito |
| 3 | Biblioteca completa: filtros por categoria, vistas, perfis, detalhes, guardar e carregar seleções | Por fazer |
| 4 | Fila de instalação: confirmação, progresso, registos, cancelamento | Por fazer |
| 5 | Desinstalação: lista de apps, fila, análise e limpeza de vestígios, cópias de segurança | Por fazer |
| 6 | Histórico, diagnósticos, verificação de atualizações, e a release: script de build, CI, testes da 3.6 adaptados, notas | Por fazer |

Os passos 4 e 5 só podem ser testados neste PC com o WinGet e o desinstalador de substituição. Instalações e remoções reais continuam a correr apenas no Actions.

## Limites deste passo

- **Um só PC.** Os tempos e a memória foram medidos numa máquina topo de gama. A memória da placa gráfica depende do controlador.
- **As compilações não são reprodutíveis bit a bit.** As duas imagens do Actions produziram executáveis do mesmo tamanho com SHA-256 diferentes.
- **O executável não é assinado**, tal como o da 3.6.
- **Os botões de vista e de histórico não existem ainda**, e o botão Desinstalar ainda não faz nada.
- **Os testes de interface precisam de um ambiente de trabalho interativo** e por isso só correm neste PC, não no Actions.
- **Não verifiquei:** o alto contraste; a app a seguir uma mudança de tema ou de cor do Windows enquanto está aberta; o descarregamento e a aplicação de uma atualização a partir da página; gravar definições pela interface em modo normal (a gravação só foi testada no motor, numa pasta temporária); e o aspeto dos outros 48 idiomas.

## Decisões que preciso de ti

A memória ficou decidida em 2026-11-18: aceitas cerca de 100 MB com a placa gráfica, como a 3.6 desenha.

1. **A ordem dos passos 3 a 6**, se quiseres outra.
