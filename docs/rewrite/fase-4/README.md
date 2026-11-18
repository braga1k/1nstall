# Fase 4 — Interface, migração e release

Estado em 2026-11-18, depois do primeiro de seis passos. O código está no ramo `v4/app`, nas pastas `app/` e `engine/ffi/`. A 3.6 na raiz do repositório continua intocada e a compilar.

## Resumo

Escolheste a interface WPF sobre o motor Rust. O primeiro passo está feito: existe um `1nstall.exe` 4.0 num único ficheiro, sem PowerShell, e está provado que a 3.6 se atualiza para ele sem release intermédia. A fase não está concluída: só o ecrã da biblioteca de instalação está ligado, e ainda não instala nem remove nada.

## A ponte de atualização deixou de ser um problema

Era a decisão em aberto desde a Fase 0. O atualizador da 3.6 só aceita um `1nstall.exe` que seja um assembly .NET chamado `1nstall` com a versão da release. Com a interface em WPF, o executável da 4.0 já é isso, por natureza. Não é preciso stub nem release-ponte.

| Verificação | Onde correu | Resultado |
| --- | --- | --- |
| A condição de identidade de `update-helper.cs` aplicada ao executável da 4.0 | Neste PC e no Actions | Aceite: `1nstall` 4.0.0.0 contra a release 4.0.0 |
| A mesma condição aplicada ao executável da 3.6, como controlo | Neste PC | Recusado, como esperado |
| O executável publicado da 3.6.0 a correr o seu próprio passo `--apply-update` contra a 4.0 | Actions, Windows Server 2022 e 2025 | Substituiu-se pela 4.0, guardou a cópia anterior, e a 4.0 resultante passou o autoteste |

O executável da 3.6.0 usado no Actions foi descarregado da release e o seu SHA-256 conferido com o publicado.

O que este teste não cobre: a parte da 3.6 que consulta a API do GitHub e descarrega a release. Essa só pode ser exercitada com uma release 4.0 publicada.

## O executável da 4.0

| Medida | 3.6.0 | 4.0, primeiro passo |
| --- | --- | --- |
| Ficheiros distribuídos | 1 | 1 |
| Tamanho | 2 699 264 bytes | 3 098 624 bytes |
| Pronta e ociosa, a quente | 1 996 ms | 594 ms |
| Primeira execução, com extração do motor | 2 425 ms | 763 ms |
| Pico de working set | 242 MB | 105 MB |
| Pico de memória privada | 275 MB | 110 MB |
| Precisa, além do Windows | .NET Framework 4.8, PowerShell 5.1 | .NET Framework 4.8 |

Medido neste PC com a régua da Fase 0, mediana de 10 arranques a quente.

**Estes números vão piorar.** A 4.0 ainda só carrega a biblioteca de instalação; faltam as definições, os idiomas, o tema e as restantes páginas, que a 3.6 já carrega nos seus 1 996 ms.

Como é construído:

- **Um só assembly.** A interface compilada da 3.6 (`interface.xaml`), os seus ajudantes C# e o anfitrião novo ficam no mesmo `1nstall.exe`. A 3.6 extraía dois DLL; a 4.0 extrai um.
- **O motor Rust vai dentro do executável** e é extraído para a mesma cache imutável da 3.6, com o SHA-256 verificado antes de ser carregado. É carregado pelo caminho completo, sem procurar em pastas.
- **O passo de atualização é o da 3.6**, sem alterações.

Verificações do executável:

| Verificação | Resultado |
| --- | --- |
| Autoteste (`--self-test`), neste PC e nas duas imagens do Actions | 7 de 7 |
| Acessibilidade por UI Automation, neste PC | 325 cartões expostos; ligar o «7-Zip» funciona |
| Argumento desconhecido | Sai com código 1, como a 3.6 |
| Motor: formatação, lints e testes, nas duas imagens | Limpos; os resultados do oráculo não mudaram |

## Objetivo da Fase 0: tem de ser revisto

Com esta escolha, dois dos quatro limites aceites na Fase 0 não são atingidos:

| Limite | Objetivo | 4.0, primeiro passo |
| --- | --- | --- |
| Pronta e ociosa | abaixo de 500 ms | 594 ms |
| Pico de working set | abaixo de 80 MB | 105 MB |
| Executável | abaixo de 12 MB | 3,1 MB |
| Dependências | só Windows e WinGet | .NET Framework 4.8, que vem com o Windows 10 e 11 |

A decisão de não portar a janela de abertura dependia de a 4.0 ficar pronta em menos de 500 ms. Na 3.6 a janela de abertura mostra o primeiro fotograma aos 445 ms; a 4.0 mostra a janela principal completa aos 594 ms. A diferença é de 150 ms, e a 4.0 ainda vai ganhar peso. Fica como decisão tua.

## Correção a relatórios anteriores

Na Fase 0 escrevi que o relógio de arranque da 3.6 excluía a criação do processo, e repeti-o na Fase 3. Está errado: o relógio da 3.6 soma o tempo desde que o Windows criou o processo (`launcher.cs:21-28`). Os números não mudam; o que muda é a leitura: a comparação entre a 3.6 e os protótipos é direta. Os dois relatórios foram corrigidos e a correção está assinalada neles.

## O que falta

A interface da 3.6 é comandada por 79 funções PowerShell, em cerca de 2 500 linhas, que têm de passar para C#. O motor Rust já tem a lógica; falta expô-la pela fronteira e ligá-la à janela.

| Passo | Conteúdo | Estado |
| --- | --- | --- |
| 1 | Executável único, fronteira com o motor, ponte de atualização, modos de teste | Feito |
| 2 | Definições, tema, cor de destaque, vidro e os 51 idiomas, incluindo os dois da direita para a esquerda | Por fazer |
| 3 | Biblioteca completa: filtros por categoria, vistas, perfis, detalhes, guardar e carregar seleções | Por fazer |
| 4 | Fila de instalação: confirmação, progresso, registos, cancelamento | Por fazer |
| 5 | Desinstalação: lista de apps, fila, análise e limpeza de vestígios, cópias de segurança | Por fazer |
| 6 | Histórico, diagnósticos, verificação de atualizações, e a release: script de build, CI, testes da 3.6 adaptados, notas | Por fazer |

Os passos 4 e 5 só podem ser testados neste PC com o WinGet e o desinstalador de substituição. Instalações e remoções reais continuam a correr apenas no Actions.

## Limites deste passo

- **As compilações não são reprodutíveis bit a bit.** As duas imagens do Actions produziram executáveis do mesmo tamanho com SHA-256 diferentes.
- **O executável não é assinado**, tal como o da 3.6.
- **O texto está só em inglês** e o tema é fixo: escuro, com a cor de destaque do Windows.
- **Os botões de vista, histórico e definições não existem ainda**: na 3.6 são criados pelo script.

## Decisões que preciso de ti

1. **O objetivo de arranque e memória**: aceitar os valores do WPF (cerca de 600 ms e 105 MB, a subir um pouco) como novo objetivo, ou tentar otimizar antes de continuar.
2. **A janela de abertura**: continuar sem ela, ou portá-la.
3. **A ordem dos passos 2 a 6**, se quiseres outra.
