# Desempenho — prévia 0.2.1

Nota de 0.2.2: os cliques ignorados nas margens foram reproduzidos e corrigidos separadamente. As medições abaixo são da 0.2.1 e não medem a área de clique nem constituem uma nova medição da 0.2.2. Ver `VALIDATION.md`.

04/10/2026, M4 Pro / 24 GiB / macOS 26.5.2. Pedido de Vitor: rapidez mantendo as animações; Install → Uninstall parecia esperar pelo fim da transição.

## Alterações

- A pedido posterior de Vitor, Uninstall passou da grelha para uma lista vertical de linhas de 70 pontos, tomando `docs/images/3.5/uninstall-dark.png` como referência. Usa LazyVStack para construir as linhas visíveis.
- A posição do rato deixou de ser estado da raiz e um valor de ambiente enviado a todas as superfícies. Um tracking view AppKit, sem capturar cliques, atualiza apenas gradientes Core Animation nas superfícies próximas e visíveis. Não há timer em repouso.
- Eliminados os GeometryReaders por superfície. Os estilos já não observam todas as alterações do AppModel: recebem apenas paleta, redução de movimento e permissão da luz.
- Removida a substituição de toda a página por identidade com uma hierarquia de saída sobreposta. O destino entra imediatamente, com deslocação de cinco pontos e opacidade 0,92 → 1 durante 200 ms. Outra navegação reinicia a entrada sem aguardar pela anterior. O realce do botão continua animado localmente.
- A animação da seleção reage aos conjuntos efetivos de apps, sem ser reativada apenas por mudar entre os dois conjuntos ao navegar.
- Navegar reutiliza o inventário recente por 30 segundos, sem iniciar uma nova leitura a cada clique. Atualização explícita e verificações de operações continuam a ler o inventário.
- Mantidos pressão, hover, gradientes, profundidade, cápsula entre cartão/seleção, expansão, entrada e brilho de sucesso. Movimento reduzido prevalece.

## Comparação reproduzível

Duas execuções release da 0.2.0 (commit `4955f33e76c7c09f4def93b0bc72b0c05cd8bb38`, apenas instrumentado) e duas do binário 0.2.1 entregue. Mesma janela NSHostingView de 1240 × 840 pontos, mesmo catálogo de 15 entradas e 200 bundles fictícios. Hover físico suprimido em ambas as versões para evitar que a posição do cursor no ambiente de trabalho altere o ensaio; a luz segue os pontos internos idênticos. Sem instalações e sem escrita de preferências ou estado real. A leitura cronometrada do inventário real é independente das fases e só regista a quantidade.

Cada fase tem 120 passos com espera pedida de 16 ms; navegação tem 24 passos, alternando Install/Uninstall/Settings com espera de 80 ms, inferior à duração da animação. A luz da nova versão tem de possuir camadas visíveis para o ensaio passar; não basta desativá-la. A execução anterior conserva o código original de UI, acrescentando apenas contadores e a mesma sequência. A comparação final inclui a mudança intencional de grelha para lista em Uninstall; não isola o efeito dessa mudança do restante trabalho.

Valores: mediana das duas execuções, segundos de CPU do processo por fase; valores negativos na última coluna indicam redução.

| Fase | 0.2.0 | 0.2.1 | Variação |
|---|---:|---:|---:|
| idle | 0.045 | 0.060 | +33.2% |
| install-pointer | 1.935 | 0.062 | -96.8% |
| uninstall-pointer | 1.646 | 0.081 | -95.1% |
| settings-pointer | 0.764 | 0.069 | -91.0% |
| search | 2.284 | 2.654 | +16.2% |
| selection | 2.010 | 2.193 | +9.1% |
| navigation | 1.689 | 1.376 | -18.6% |

120 movimentos em Install: avaliações da raiz **120 → 0**; superfícies **6960 → 0**. Uninstall: raiz **120 → 0**; superfícies **6360 → 0**. O efeito luminoso continua a atualizar as camadas, com zero recálculos SwiftUI nessas fases.

A melhoria robusta concentra-se na luz. A navegação deixa de reter a página de saída e os testes verificam a interrupção antes do fim; o número de CPU não mede diretamente essa resposta. Pesquisa/seleção não apresentam melhoria consistente nestas execuções. Há variação entre ensaios; a redução de avaliações dos estilos não elimina o custo de reconstruir os cartões visíveis. Duas repetições não constituem uma caracterização estatística de todos os cenários.

Os intervalos medianos/p95/máximos nos JSON incluem a espera pedida e a ocupação do executor. **Não são FPS, latência entre clique e píxel, nem duração de abertura pelo Finder.** CPU exclui WindowServer/GPU. As Command Line Tools estavam disponíveis; Xcode completo/Instruments não foi instalado nem utilizado. A instrumentação começa em `main`, pelo que também não mede o carregador anterior ao processo.

## Executar

```sh
swift build --package-path macos -c release --product 1nstall
macos/.build/release/1nstall --benchmark /caminho/resultado.json
macos/.build/release/1nstall --render-checks
```

`--render-checks` confirma o destino e a animação aos 40 ms, interrompe com novo destino antes dos 200 ms, escreve pesquisa durante a entrada, verifica redução de movimento, movimento/visibilidade da luz, passagem de cliques e preservação do estado real. São testes da composição real com modelo isolado, complementados pela verificação nativa; não são síntese de input do sistema.

`--trace-interactions` é opcional para diagnóstico manual: regista aceitação de navegação e idade do evento AppKit, além das primeiras atualizações nativas da luz. O evento corrente pode ser anterior à ação (ou estar ausente em ações de acessibilidade); a sua idade não representa latência entre clique e píxel. Não cria telemetria, ficheiros ou comunicações externas por si.

Dados brutos, registo da compilação e verificações acompanham a entrega em `validation/`. O trabalho seguinte continua a incluir catálogo maior, remoção anterior à prévia e avaliação mais ampla de fluidez/acessibilidade.

Referências técnicas: [Apple — desempenho SwiftUI](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance), [WWDC25 — Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/). A separação de atualizações decorativas frequentes e a medição de recálculos seguem estas recomendações; os números acima são medições locais.
