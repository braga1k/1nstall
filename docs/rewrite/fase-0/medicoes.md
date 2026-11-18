# Fase 0 — Medições de base da 1nstall 3.6.0

Medido em 2026-11-18 com o `1nstall.exe` da release `v3.6.0`. O SHA-256 do ficheiro descarregado é igual ao digest publicado (`90428e1e…8508c`).

## Resultados

13 execuções de `1nstall.exe --startup-test`, todas com código de saída 0.

| Métrica | Primeira execução | Mediana das 10 a quente | Intervalo a quente |
| --- | --- | --- | --- |
| Primeiro fotograma da janela de abertura (`FirstFrameMs`) | 676 ms | 445,5 ms | 438 a 468 ms |
| Janela principal pronta a mostrar (`BeforeShowMs`) | 2 073 ms | 1 707 ms | 1 694 a 1 726 ms |
| Conteúdo desenhado (`RenderMs`) | 2 363 ms | 1 931,5 ms | 1 912 a 1 951 ms |
| **Pronta e ociosa (`READY`)** | **2 405 ms** | **1 962 ms** | 1 943 a 1 980 ms |
| Pico de working set | 241,1 MB | 238,5 MB | 237,5 a 243,2 MB |
| Pico de memória privada | 260,1 MB | 259,1 MB | 258,8 a 260,4 MB |
| Vida total do processo de teste | 3 380 ms | 2 844 ms | 2 794 a 2 867 ms |

Tamanho do executável: 2 699 264 bytes.

As duas execuções seguintes com a cache de DLL apagada deram `READY` de 2 070 e 2 041 ms: reextrair os dois DLL custa cerca de 100 ms.

## Máquina

Um PC de secretária topo de gama com Windows 11. Os detalhes do hardware ficam fora do repositório.

## Como ler estes números

- **Só servem para comparar neste PC.** É uma máquina muito acima da média; num portátil comum os tempos serão bem maiores. A comparação com a 4.0 tem de ser feita na mesma máquina, ou num runner de CI fixo.
- **Não é um arranque a frio verdadeiro.** A primeira execução (2 405 ms) é a mais próxima: exe acabado de copiar, DLL por extrair, análise do antivírus incluída. Mas não houve reinício, por isso o .NET e o WPF já estavam na cache de disco do Windows.
- **O relógio é o da própria app.** É criado dentro do launcher (`launcher.cs:26`) e passado ao script (`:133`), por isso exclui a criação do processo e o arranque do CLR. A «vida total do processo» é medida de fora e inclui também o fecho.
- **O modo de teste não é igual a um arranque normal.** Força inglês e tema escuro, não lê `settings.json` e não verifica atualizações (`settings.ps1:9-10`).
- **A memória é o pico até ao estado pronto**, não o consumo após uso prolongado.

## Dois comportamentos observados ao medir

1. **A 3.6 não arranca em modo de teste a partir de um caminho longo.** Nesse modo a cache fica em `<pasta do exe>\runtime-cache\<sha256>\`, e com a pasta do exe já comprida o caminho passa os 260 caracteres: `PathTooLongException` em `Launcher.CacheAssembly`, código de saída 1. Em arranque normal a cache vai para `%LOCALAPPDATA%\1nstall\Runtime`, pelo que só afeta os testes. A medição foi repetida a partir de um caminho de 124 caracteres.
2. **O modo de teste escreve fora da pasta do exe.** As execuções criaram `%LOCALAPPDATA%\1nstall\Runtime\d1b5a4fb…\1nstall.Helpers.dll` (85 504 bytes), apesar de `launcher.cs:43` apontar a cache para `runtime-cache` em modo de teste. A causa é `launcher.cs:64`, que carrega a janela de abertura com o modo de teste fixo a `false`. É o mesmo ficheiro que um arranque normal da 3.6.0 criaria; ficou no sítio.

## Repetir a medição

O script está em [verificacao/medir-arranque.ps1](verificacao/medir-arranque.ps1). Aceita qualquer executável que suporte `--startup-test` e escreva o mesmo formato de log, o que permite medir a 4.0 com a mesma régua.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File fase-0\verificacao\medir-arranque.ps1 -Exe C:\caminho\curto\1nstall.exe -Out medicoes.json -Fresh 3 -Warm 10
```

## Objetivo da 4.0

Aceite em 2026-11-18. Vale **neste PC e com esta régua**:

| Métrica | 3.6.0 | Objetivo da 4.0 |
| --- | --- | --- |
| Pronta e ociosa, a quente | 1 962 ms | abaixo de 500 ms |
| Pico de working set | 238,5 MB | abaixo de 80 MB |
| Tamanho do executável | 2,7 MB | abaixo de 12 MB |
| Dependências em runtime | .NET Framework 4.8, PowerShell 5.1; PowerShell 7 e Microsoft.WinGet.Client para o inventário completo | nenhuma além do Windows e do WinGet |

Os limiares são um objetivo, não uma medição: dependem do toolkit de interface escolhido na Fase 3, e passam a ser um dos critérios dessa escolha. O tamanho deverá **subir**, porque a 3.6 se apoia em runtimes que já vêm com o Windows e um binário Rust traz tudo consigo.

### Consequência: a janela de abertura deixa de ser precisa

A animação de abertura da 3.6 existe só para mascarar o tempo de carregamento (confirmado pelo autor). A própria máscara demora 445,5 ms a mostrar o primeiro fotograma. Se a 4.0 estiver pronta em menos de 500 ms, a janela principal aparece tão depressa como hoje aparece a máscara.

Por isso a abertura **não é portada**: `src/startup.cs` e os invariantes S-54 a S-57 ficam fora da 4.0. É a primeira entrada da lista de divergências intencionais. Se a Fase 3 não atingir o limiar com nenhum toolkit, esta decisão reabre-se.
