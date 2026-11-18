Nota de âmbito: além dos ficheiros pedidos li na íntegra `src/manager-ui.ps1` (277 linhas), porque `vexan_installers.ps1:1404-1405` faz dot-source dele e é lá que estão o inventário da biblioteca e a importação efetiva (redefine `Load-UserProfile`). Li também `tests/process-fixture.cs`, `tests/manager-ui.ps1` e `tests/catalog.py`. Nada foi executado nem alterado no repositório. Os snippets dos invariantes foram comparados literalmente com as linhas indicadas (comparação ordinal de texto, comprimento 30–100).

Abreviaturas: V = `vexan_installers.ps1`, P = `src/package-helper.cs`, M = `src/manager-ui.ps1`, R = `tests/reliability.ps1`.

## Invariantes

### Catálogo, plano e seleção

**I-01** — O catálogo vem embebido (`@@CATALOG@@`); só se o marcador não tiver sido substituído é lido de `$ResourceRoot\catalog.json` em UTF-8, sem validação de esquema em execução normal.
- Fonte: V:15 (condição em V:14) · Snippet: `Get-Content (Join-Path $ResourceRoot 'catalog.json') -Raw -Encoding UTF8`
- Teste: sem teste · Confiança: alta

**I-02** — Ordenação do catálogo: nomes começados por dígito (0), por letra (1), outros (2), depois por Name.
- Fonte: V:25 · Snippet: `if ($_.Name -match '^\p{Nd}') { 0 } elseif ($_.Name -match '^\p{L}') { 1 } else { 2 }`
- Teste: tests/manager-ui.ps1:55 · Confiança: alta

**I-03** — `Get-Plan` rejeita chave desconhecida e ciclo de dependências, e devolve dependências antes dos dependentes, sem duplicados.
- Fonte: V:43 e V:44 · Snippets: `if (-not $byKey.ContainsKey($key)) { throw "Unknown application: $key" }` / `if ($visiting.ContainsKey($key)) { throw "Dependency cycle at: $key" }`
- Teste: R:87, R:88, R:89; V:92-96 (SelfTest) · Confiança: alta

**I-04** — A validação do catálogo e dos perfis (chaves únicas, IDs únicos, exatamente um de Ids/Url, Requires existentes, 4 grupos, 20 perfis) só corre com `-SelfTest`, não no arranque normal.
- Fonte: V:89 (bloco V:71-104) · Snippet: `throw 'Each app needs exactly one installation method.'`
- Teste: tests/smoke.ps1:7; tests/catalog.py:24 · Confiança: alta

**I-05** — A UI só arranca em Windows de 64 bits e em thread STA (V:131).
- Fonte: V:130 · Snippet: `-not [Environment]::Is64BitOperatingSystem) { throw 'Requires 64-bit Windows.' }`
- Teste: sem teste · Confiança: alta

**I-06** — Selecionar um cartão adiciona a app e todas as dependências transitivas.
- Fonte: V:641 · Snippet: `if ($card.IsChecked) { foreach ($item in @(Get-Plan @($key))) { $selected[$item.Key]=$true } }`
- Teste: V:1516-1518 (smoke) · Confiança: alta

**I-07** — Remover uma app remove, iterativamente, todas as selecionadas cujos Requires deixaram de estar selecionados.
- Fonte: V:522 (ciclo V:519-524) · Snippet: `@($item.Requires | Where-Object { -not $selected.ContainsKey($_) }).Count)`
- Teste: V:1485-1486, V:1519-1521 (smoke) · Confiança: alta

**I-08** — Com a fila ocupada a seleção não muda: clique em cartão ignorado, `Remove-SelectedApp` (V:516) e `Apply-Profile` (V:715) retornam, cartões desativados (V:892).
- Fonte: V:639 · Snippet: `if ($card -isnot [Windows.Controls.CheckBox] -or $script:syncing -or $script:busy) { return }`
- Teste: V:1487-1488 (parcial) · Confiança: alta

**I-09** — `Set-Selection` substitui (não funde) a seleção pelo plano das chaves; limpa primeiro (V:529) e só depois calcula o plano.
- Fonte: V:530 · Snippet: `foreach ($app in @(Get-Plan $Keys)) { $selected[$app.Key] = $true }`
- Teste: V:1507-1513 (smoke) · Confiança: alta (ver lista 2, ponto 4)

**I-10** — A instalação só arranca se `Confirm-Plan` devolver true (V:900), e o botão «Start installation» só fica ativo com a caixa «I accept the app licenses and WinGet source terms.» marcada.
- Fonte: V:813 · Snippet: `$agree.Add_Checked({ $go.IsEnabled=$true }); $agree.Add_Unchecked({ $go.IsEnabled=$false })`
- Teste: V:827 (asserção dentro do diálogo, chamada em V:1744) · Confiança: alta

**I-11** — Instalar só está disponível com seleção não vazia e fila parada.
- Fonte: V:477 · Snippet: `$ui.Install.IsEnabled = ($selected.Count -gt 0 -and -not $busy)`
- Teste: V:1515 · Confiança: alta

### Localização do WinGet

**I-12** — `FindWinGet`: primeiro `%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe`, depois cada entrada de PATH (com Trim e sem aspas, `ArgumentException` ignorada); devolve "" se não existir.
- Fonte: P:78 e P:86 · Snippets: `Environment.SpecialFolder.LocalApplicationData), @"Microsoft\WindowsApps\winget.exe");` / `string candidate = Path.Combine(entry.Trim().Trim('"'), "winget.exe");`
- Teste: R:36, R:39 · Confiança: alta

**I-13** — O WinGet é resolvido uma única vez no arranque (V:351); se faltar e o plano tiver apps automáticas, mostra aviso, abre `ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1` e aborta o plano inteiro (V:901-904); nunca instala o WinGet.
- Fonte: V:903 · Snippet: `Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'`
- Teste: sem teste · Confiança: alta

### Linha de comandos e lançamento de processos

**I-14** — Comando exato: `install --id "<id>" --exact --source "<source>" --no-upgrade --accept-source-agreements --accept-package-agreements --disable-interactivity`; não há `--silent`, `--scope`, `--force`, `--version` nem `--override`.
- Fonte: P:113 e P:114 · Snippets: `return "install --id " + Quote(id) + " --exact --source " + Quote(source) +` / `" --no-upgrade --accept-source-agreements --accept-package-agreements --disable-interactivity";`
- Teste: R:51-52 · Confiança: alta

**I-15** — `Arguments` lança exceção antes de qualquer processo se o ID ou a origem forem inválidos.
- Fonte: P:112 · Snippet: `if (!ValidId(id) || !ValidSource(source)) throw new ArgumentException("Invalid package identity.");`
- Teste: R:50 (4 casos) · Confiança: alta

**I-16** — ID válido: não nulo, até 200 caracteres, regex `^[A-Za-z0-9][A-Za-z0-9.+_-]*$`.
- Fonte: P:94 · Snippet: `id != null && id.Length <= 200 && Regex.IsMatch(id, @"^[A-Za-z0-9][A-Za-z0-9.+_-]*$");`
- Teste: R:50, R:67, R:115 · Confiança: alta (ver lista 2, ponto 7)

**I-17** — Origem válida: exatamente "winget" ou "msstore", sensível a maiúsculas.
- Fonte: P:95 · Snippet: `return source == "winget" || source == "msstore";`
- Teste: sem teste direto · Confiança: alta

**I-18** — A fila instala sempre com a origem literal 'winget'; msstore nunca é instalado pela fila.
- Fonte: V:875 · Snippet: `$result=[OneInstallPackages]::Install($Winget,$id,'winget',$app.Name,$LogDir,[Action]{`
- Teste: R:92-94 · Confiança: alta

**I-19** — `Quote` rejeita null e NUL, coloca sempre aspas e duplica barras invertidas antes de aspas e no fim (regras de CommandLineToArgvW; P:104, P:108).
- Fonte: P:99 · Snippet: `if (value == null || value.IndexOf('\0') >= 0) throw new ArgumentException("Invalid argument.");`
- Teste: R:42-46, R:47 · Confiança: alta

**I-20** — Invariante imposto pelo teste: o comando nunca contém `--all`, `--force`, `--include-pinned`, `--allow-reboot`, e não existe `UpdateAsync` (R:53).
- Fonte: R:52 · Snippet: `$command -notmatch '--all|--force|--include-pinned|--allow-reboot'`
- Teste: R:52, R:53; tests/manager-ui.ps1:307 · Confiança: alta

**I-21** — Processos lançados sem shell, sem janela, com stdout/stderr redirecionados em UTF-8; sem diretório de trabalho definido, sem verbo de elevação, sem alterar ambiente.
- Fonte: P:118 · Snippet: `UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true`
- Teste: R:43-49 (indireto) · Confiança: alta

**I-22** — Os dois pipes são lidos em paralelo para não bloquear.
- Fonte: P:122 · Snippet: `var output = p.StandardOutput.ReadToEndAsync(); var error = p.StandardError.ReadToEndAsync();`
- Teste: R:48-49 (200000 caracteres em cada) · Confiança: alta

**I-23** — Com timeout > 0 excedido, mata só o processo e lança `TimeoutException`; timeout 0 espera sem limite.
- Fonte: P:123 · Snippet: `if (timeout > 0 && !p.WaitForExit(timeout)) { p.Kill(); p.WaitForExit(); throw new TimeoutException(`
- Teste: sem teste · Confiança: alta

**I-24** — Saída e erro truncados a 1048576 caracteres, com sufixo `\n[truncated]`.
- Fonte: P:126 · Snippet: `o.Length > 1048576 ? o.Substring(0, 1048576) + "\n[truncated]" : o`
- Teste: sem teste · Confiança: alta

**I-25** — A instalação corre com timeout 0: a aplicação nunca mata um instalador em curso.
- Fonte: P:265 · Snippet: `var r = Run(exe, Arguments(id, source), 0);`
- Teste: R:101-109 · Confiança: alta

### Códigos de saída e resultado

**I-26** — «Restart required»: 3010, 1641, 0x8A150109, 0x8A15010A, 0x8A15010B.
- Fonte: P:209 · Snippet: `code == 3010 || code == 1641 || h == 0x8A150109 || h == 0x8A15010A || h == 0x8A15010B`
- Teste: R:70, R:71, R:73 · Confiança: alta

**I-27** — «Cancelled»: 1602, 1223, 0x800704C7, 0x8A150005, 0x8A15010C, 0x8A150077.
- Fonte: P:210 · Snippet: `h == 0x800704C7 || h == 0x8A150005 || h == 0x8A15010C || h == 0x8A150077) return "Cancelled";`
- Teste: R:70 (1602), R:74 · Confiança: alta

**I-28** — 0, 0x8A150061 e 0x8A15010D dão «Unknown»: sucesso de saída nunca equivale a instalado, tem de ser verificado.
- Fonte: P:211 · Snippet: `if (code == 0 || h == 0x8A150061 || h == 0x8A15010D) return "Unknown";`
- Teste: R:70, R:76 · Confiança: alta

**I-29** — «Manual action required»: 0x8A150076, 0x8A150041, 0x8A150046; qualquer outro código dá «Failed» (P:213).
- Fonte: P:212 · Snippet: `if (h == 0x8A150076 || h == 0x8A150041 || h == 0x8A150046) return "Manual action required";`
- Teste: R:70 (1603 → Failed), R:72; os três HRESULT sem teste · Confiança: alta

**I-30** — Explicações: 0x8A150008/0x8A150107 rede; 0x8A150068 pin («1nstall will not override it», P:219); 0x8A150104/0x8A150110 dependência (P:220); resto mensagem genérica com código decimal e hex (P:221).
- Fonte: P:218 · Snippet: `if (h == 0x8A150008 || h == 0x8A150107) return "Download/network failure.`
- Teste: R:75 (0x8A150107) · Confiança: alta

**I-31** — Só há «Success» quando, após resultado «Unknown», um inventário novo devolve estado começado por «Installed ·» para esse ID e origem exatos; caso contrário fica «Unknown» com mensagem. O callback `verifying` é chamado antes (P:270).
- Fonte: P:272 (inventário em P:271) · Snippet: `{ outcome = "Success"; message = "Exact package identity verified: " + state; }`
- Teste: R:76, R:77-79 · Confiança: alta

**I-32** — «Restart required», «Cancelled», «Manual action required» e «Failed» nunca são reescritos pela verificação: esta só corre dentro de `if (outcome == "Unknown")` (P:268).
- Fonte: P:267 · Snippet: `string outcome = Outcome(r.ExitCode), message = Explain(r.ExitCode);`
- Teste: R:73, R:74 · Confiança: alta

**I-33** — Qualquer exceção na instalação (incluindo executável inexistente) é registada como «Failed» com código -1.
- Fonte: P:277 · Snippet: `catch (Exception e) { return Record("Install", id, source, name, "Failed", e.Message, -1, log); }`
- Teste: R:80 · Confiança: alta

**I-34** — Toda a instalação é gravada no histórico com resultado, mensagem, código e caminho do log.
- Fonte: P:275 · Snippet: `return Record("Install", id, source, name, outcome, message, r.ExitCode, log);`
- Teste: R:95-97 (indireto) · Confiança: alta

### Fila, Stop e apps guiadas

**I-35** — App com vários IDs: para no primeiro ID cujo resultado não seja «Success».
- Fonte: V:877 · Snippet: `if ($result.Outcome -ne 'Success') { break }`
- Teste: sem teste (só há um caso no catálogo: VCRedist, 12 IDs) · Confiança: alta

**I-36** — Agregação por app, por precedência: Failed > Cancelled > Restart required > Manual action required > Unknown (mostrado «Unknown · refresh to verify») > Success.
- Fonte: V:880 · Snippet: `elseif ($states -contains 'Cancelled') { 'Cancelled' } elseif ($states -contains 'Restart required')`
- Teste: sem teste direto · Confiança: alta

**I-37** — Uma app só corre se cada Requires tiver resultado exatamente 'Success' nesta mesma execução; senão fica «Manual action required · dependency not verified», é registada (V:857) e não corre.
- Fonte: V:853 · Snippet: `Where-Object { -not $outcomes.ContainsKey($_) -or $outcomes[$_] -ne 'Success' })`
- Teste: R:92-97 · Confiança: alta

**I-38** — Stop é verificado apenas no início de cada app (V:848); as restantes ficam «Cancelled · not started» e são registadas com Id = chave do catálogo, Source 'catalog', código 0.
- Fonte: V:850 · Snippet: `'Cancelled','Not started: stop after current requested.',0,$null) | Out-Null`
- Teste: R:98-99, R:109 · Confiança: alta

**I-39** — O botão Stop só ativa a flag; nunca mata nem interrompe o instalador corrente.
- Fonte: V:927 · Snippet: `if ($script:busy) { $script:control.Stop=$true; $ui.Cancel.IsEnabled=$false;`
- Teste: R:101-108 (worker); UI sem teste · Confiança: alta

**I-40** — Fechar a janela com a fila ativa é cancelado (V:999), pede Stop (V:1000) e manda esperar.
- Fonte: V:1001 · Snippet: `'Wait for the current installer to finish, then close this window.'`
- Teste: sem teste · Confiança: alta

**I-41** — App guiada: emite o URL, estado «Manual install pending · official website», resultado «Manual action required», registo com Source 'guided'; nunca «Success», logo bloqueia dependentes.
- Fonte: V:865 (bloco V:861-867) · Snippet: `Opening a website does not prove installation.',0,$null) | Out-Null`
- Teste: sem teste · Confiança: alta

**I-42** — O URL aberto na fila é o campo `Url` do catálogo tal como está, via ShellExecute, sem validação de esquema em runtime; o https só é garantido por tests/catalog.py.
- Fonte: V:940 · Snippet: `try { Start-Process $event.Text }`
- Teste: tests/catalog.py:28-30 (dados, não código) · Confiança: alta

**I-43** — No diálogo de detalhes, o site só abre se corresponder a `^https://[^\s]+$` (botão ativo só com `^https://`, M:89).
- Fonte: M:90 · Snippet: `if ([string]$sender.Tag -match '^https://[^\s]+$') { Start-Process ([string]$sender.Tag) }`
- Teste: sem teste (tests/manager-ui.ps1:306 abre o diálogo, não clica) · Confiança: alta

**I-44** — O worker corre noutro runspace, recebe o script como texto e comunica só por fila concorrente de eventos e por hashtable sincronizada `Stop` (V:906-907).
- Fonte: V:914 · Snippet: `$null=$script:job.AddScript($worker.ToString()).AddArgument($plan).AddArgument($winget)`
- Teste: R:101-104 · Confiança: alta

**I-45** — No fim da fila (poll de 250 ms, V:930): 'Queued' passa a 'Not started'; 'Installing*', 'Preparing*', 'Verifying*' passam a 'Failed · operation interrupted'; depois refresca o inventário (V:959).
- Fonte: V:951 · Snippet: `if ($statuses[$key] -eq 'Queued') { $statuses[$key]='Not started' }`
- Teste: sem teste (V:1463 só verifica temporizador parado em repouso) · Confiança: alta

**I-46** — O sinal de sucesso global só aparece se todos os estados forem exatamente 'Success' e não tiver havido Stop.
- Fonte: V:957 · Snippet: `@($statuses.Values | Where-Object { $_ -ne 'Success' }).Count -eq 0 -and -not $script:control.Stop`
- Teste: sem teste do predicado (tests/manager-ui.ps1:445-446 testa só a animação) · Confiança: alta

**I-47** — Exceção no worker gera evento 'error'; 'done' é sempre emitido no finally (V:886).
- Fonte: V:885 · Snippet: `} catch { Emit 'error' '' $_.Exception.Message }`
- Teste: sem teste · Confiança: alta

### Inventário

**I-48** — O inventário estruturado exige PowerShell 7 no caminho fixo `%ProgramFiles%\PowerShell\7\pwsh.exe`; se faltar lança erro («1nstall never installs prerequisites automatically», P:134).
- Fonte: P:133 · Snippet: `Environment.SpecialFolder.ProgramFiles), @"PowerShell\7\pwsh.exe");`
- Teste: sem teste · Confiança: alta

**I-49** — pwsh é chamado com `-NoLogo -NoProfile -NonInteractive -EncodedCommand <Base64 UTF-16LE>`, com `Import-Module Microsoft.WinGet.Client -MinimumVersion 1.7.0`, timeout 90000 ms; saída ≠ 0 lança `IOException` (P:142).
- Fonte: P:140 e P:141 · Snippets: `Import-Module Microsoft.WinGet.Client -MinimumVersion 1.7.0 -ErrorAction Stop;` / `Convert.ToBase64String(Encoding.Unicode.GetBytes(code)), 90000);`
- Teste: sem teste · Confiança: alta

**I-50** — A consulta é `Get-WinGetPackage` projetado em Id, Name, Source, InstalledVersion (P:150); JSON limitado a 4194304 e profundidade 20 (P:76); registo com Id ou Name nulos invalida tudo; só então `Complete = true`.
- Fonte: P:152 · Snippet: `if (result.Packages.Any(p => p.Id == null || p.Name == null)) throw new IOException(`
- Teste: sem teste · Confiança: alta

**I-51** — Fallback perante qualquer falha: `winget export --output "<temp>" --include-versions --disable-interactivity` (90000 ms); rejeitado se saída ≠ 0, ficheiro ausente ou > 4194304 bytes (P:163); resultado `Partial`; o temporário `%TEMP%\1nstall-inventory-<guid>.json` é sempre apagado (P:169).
- Fonte: P:162 · Snippet: `"export --output " + Quote(temp) + " --include-versions --disable-interactivity", 90000);`
- Teste: sem teste do processo (parsing em R:64-68) · Confiança: alta

**I-52** — `ParseExport`: sem `Sources` falha; cada origem precisa de `SourceDetails.Name` e `Packages`; origens que não sejam winget/msstore são ignoradas (P:183); um único ID inválido rejeita o export inteiro.
- Fonte: P:186 · Snippet: `if (!ValidId(package.PackageIdentifier)) throw new IOException("Invalid exported identity.");`
- Teste: R:64, R:67, R:68 · Confiança: alta

**I-53** — Sem IDs (app guiada) ou sem inventário completo/parcial, o estado é «Unknown».
- Fonte: P:194 · Snippet: `if (ids == null || ids.Length == 0 || (!inventory.Complete && !inventory.Partial)) return "Unknown";`
- Teste: R:55, R:63 · Confiança: alta

**I-54** — A correspondência é só por ID (sem distinguir maiúsculas) e origem exata; nunca pelo nome apresentado.
- Fonte: P:198 · Snippet: `String.Equals(p.Id, id, StringComparison.OrdinalIgnoreCase) && p.Source == source`
- Teste: R:58-60 · Confiança: alta

**I-55** — Mais de um registo para o mesmo ID e origem dá «Unknown · multiple registrations».
- Fonte: P:199 · Snippet: `if (matches.Length > 1) return "Unknown · multiple registrations";`
- Teste: R:61-62; tests/manager-ui.ps1:293-295 · Confiança: alta

**I-56** — «Not installed» só com inventário `Complete` e nenhum ID encontrado; caso contrário «Unknown · omitted or partially installed».
- Fonte: P:203 · Snippet: `if (absent) return inventory.Complete && versions.Count == 0 ? "Not installed" :`
- Teste: R:57, R:60, R:66 · Confiança: alta

**I-57** — Todos os IDs presentes: «Installed · v1 / v2» (P:204); versão vazia ou `unknown|latest|n/a|<...>` aparece como «version unknown» (P:201).
- Fonte: P:96 · Snippet: `!Regex.IsMatch(version, @"^(unknown|latest|n/a|<.*>)$", RegexOptions.IgnoreCase)`
- Teste: R:59, R:65 (só versão conhecida) · Confiança: alta

**I-58** — O estado da biblioteca é sempre calculado com origem 'winget' sobre os IDs do catálogo.
- Fonte: M:25 · Snippet: `$state=[OneInstallPackages]::InstalledState($script:libraryInventory,[string[]]$app.Ids,'winget')`
- Teste: tests/manager-ui.ps1:286-292 · Confiança: alta

**I-59** — O refrescamento do inventário é de voo único, corre em `Task.Run` (P:173), é consultado a cada 250 ms (M:260) e dispara ao abrir a janela (M:276), no fim da fila (V:959) e após remoções (V:1308).
- Fonte: M:17 · Snippet: `if ($script:libraryTask -or $SmokeTest) { return }`
- Teste: sem teste · Confiança: alta

**I-60** — Repetir a partir do histórico: botão só para registo Install/Failed/winget (M:183) com uma única app de catálogo e estado «Not installed» (M:185); o clique refresca o inventário e só volta a selecionar se continuar «Not installed»; nunca instala sozinho.
- Fonte: M:268 · Snippet: `'Retry withheld: app is installed or its current identity/state is unknown.'`
- Teste: sem teste · Confiança: alta

### Histórico, logs e redação

**I-61** — Histórico em `%LOCALAPPDATA%\1nstall\operations.json` (P:77, P:92); cada escrita guarda só os últimos 500 registos, por ficheiro temporário e `File.Replace`/`File.Move` sob lock (P:235).
- Fonte: P:234 · Snippet: `Json().Serialize(rows.Skip(Math.Max(0, rows.Count - 500)).ToList()), Encoding.UTF8);`
- Teste: sem teste do limite · Confiança: alta

**I-62** — Histórico ilegível, com registos inválidos (P:251) ou maior que 4194304 bytes (P:249) nunca é sobrescrito; o registo novo leva a nota «History could not be saved».
- Fonte: P:231 · Snippet: `if (HistoryError != null) throw new IOException(HistoryError + " Existing history was preserved.");`
- Teste: R:121-125 · Confiança: alta

**I-63** — Log por instalação em `<logs>\<guid>.log`, com stdout + CRLF + stderr em UTF-8, sem redação.
- Fonte: P:266 (nome em P:264) · Snippet: `File.WriteAllText(log, r.Output + "\r\n" + r.Error, Encoding.UTF8);`
- Teste: sem teste · Confiança: alta

**I-64** — Pasta de logs `%LOCALAPPDATA%\1nstall\Logs`; log de sessão `session-yyyyMMdd-HHmmss-<PID>.log` (V:350); falha de escrita não é fatal (V:357).
- Fonte: V:348 · Snippet: `Join-Path $env:LOCALAPPDATA '1nstall\Logs'`
- Teste: sem teste · Confiança: alta

**I-65** — A redação só é aplicada em `Diagnostics()` (últimos 100 registos, P:293). Padrões (P:282-288): caminhos Windows/UNC e `/Users/`, `/home/` → `<path>`; `chave[:=]valor` para token, password, passwd, secret, authorization, api key, credential; `Bearer`; credenciais em URL; query string de URL; emails.
- Fonte: P:284 · Snippet: `(token|password|passwd|secret|authorization|api[_-]?key|credential)\s*[:=]\s*[^\r\n,;]+`
- Teste: R:118-119 · Confiança: alta

**I-66** — O diagnóstico nunca é enviado; só é gravado se o utilizador escolher um ficheiro.
- Fonte: M:201 · Snippet: `$dialog.Filter='Text (*.txt)|*.txt'; $dialog.FileName='1nstall-diagnostics.txt'`
- Teste: tests/manager-ui.ps1:313 (só abre) · Confiança: alta

**I-67** — «Open detailed log» só aparece se o caminho existir e estiver dentro da pasta de logs; abre com `notepad.exe` e argumento passado por `Quote` (M:193).
- Fonte: M:191 · Snippet: `.StartsWith([IO.Path]::GetFullPath($logDir)+'\',[StringComparison]::OrdinalIgnoreCase)`
- Teste: sem teste · Confiança: alta

### Perfis e importação/exportação

**I-68** — Exportar a seleção escreve `Version=1` e `Apps` = chaves de catálogo selecionadas, pela ordem do catálogo; recusa seleção vazia (V:757).
- Fonte: V:758 · Snippet: `Apps=@($catalog | Where-Object { $selected.ContainsKey($_.Key) } | ForEach-Object { $_.Key })}`
- Teste: V:1495-1499, V:1491 (smoke) · Confiança: alta

**I-69** — A importação efetiva é a de M:223 (substitui a de V:760) e passa sempre por `ReadSetup`.
- Fonte: M:224 · Snippet: `$setup=[OneInstallPackages]::ReadSetup($Path)`
- Teste: V:1498-1503 · Confiança: alta

**I-70** — Limite de 65536 bytes, no ficheiro e no texto em UTF-8 (P:302).
- Fonte: P:297 · Snippet: `if (new FileInfo(file).Length > 65536) throw new IOException("Setup file exceeds 64 KiB.");`
- Teste: R:117 · Confiança: alta

**I-71** — A raiz tem de ser objeto com `Version` inteiro e `Apps`.
- Fonte: P:304 · Snippet: `!root.ContainsKey("Version") || !(root["Version"] is int) || !root.ContainsKey("Apps")`
- Teste: R:115 ('malformed') · Confiança: alta

**I-72** — Só versões 1 e 2.
- Fonte: P:306 · Snippet: `if (version != 1 && version != 2) throw new IOException("Unsupported setup version.");`
- Teste: R:115 (Version 99) · Confiança: alta

**I-73** — Campos desconhecidos na raiz são rejeitados (só Version, Apps e, na v2, Kind).
- Fonte: P:307 · Snippet: `root.Keys.Any(k => k != "Version" && k != "Apps" && !(version == 2 && k == "Kind"))`
- Teste: R:115 ("Command") · Confiança: alta

**I-74** — A v2 exige `Kind` igual a "1nstall-selection".
- Fonte: P:308 · Snippet: `Convert.ToString(root["Kind"]) != "1nstall-selection"`
- Teste: sem teste negativo (positivo em R:113-114) · Confiança: alta

**I-75** — `Apps` tem de ser array com 1 a 500 itens.
- Fonte: P:310 · Snippet: `if (items == null || items.Length == 0 || items.Length > 500) throw new IOException(`
- Teste: R:115 ("Apps":"A"); limite 500 sem teste · Confiança: alta

**I-76** — v1: cada item é string que passa `ValidId`, sem duplicados (sem distinguir maiúsculas).
- Fonte: P:317 · Snippet: `if (!ValidId(key) || !seen.Add(key)) throw new IOException("Invalid or duplicate catalog key.");`
- Teste: R:115 (["A","A"]), R:116 · Confiança: alta

**I-77** — v2: cada item é objeto com exatamente Id, Source, Name, Version, todos strings.
- Fonte: P:323 · Snippet: `fields.Keys.Any(k => k != "Id" && k != "Source" && k != "Name" && k != "Version")`
- Teste: sem teste direto · Confiança: alta

**I-78** — v2: ID e origem válidos, Name até 200, Version até 100, sem caracteres de controlo `\x00-\x1f`, sem duplicado `Source:Id`.
- Fonte: P:325 · Snippet: `!ValidSource(entry.Source) || entry.Name.Length > 200 || entry.Version.Length > 100`
- Teste: R:115 (Id "--all"); restantes sem teste · Confiança: alta

**I-79** — v1: todas as chaves têm de existir no catálogo (`Get-Plan`) antes de qualquer alteração à seleção.
- Fonte: M:227 · Snippet: `$plan=@(Get-Plan ([string[]]$setup.Keys)) # validate before any selection mutation`
- Teste: V:1500-1503 · Confiança: alta

**I-80** — A importação mostra pré-visualização e só altera a seleção se o utilizador confirmar.
- Fonte: M:244 (retorno nulo em M:219-220) · Snippet: `if ($null -ne $keys) { Set-Selection ([string[]]$keys) }`
- Teste: sem teste do caminho de cancelamento · Confiança: alta

**I-81** — v2: uma entrada só é selecionável se exatamente uma app do catálogo tiver esse ID e a origem for 'winget'; as restantes aparecem desativadas (M:214, M:239). Um ficheiro importado nunca introduz na fila um ID fora do catálogo.
- Fonte: M:232 · Snippet: `$matches=@($catalog | Where-Object { $_.Ids -contains $entry.Id -and $entry.Source -eq 'winget' })`
- Teste: sem teste · Confiança: alta

**I-82** — Qualquer erro de importação é mostrado em caixa de mensagem e a seleção atual mantém-se.
- Fonte: V:787 · Snippet: `[Windows.MessageBox]::Show($window,$_.Exception.Message,'Could not import profile') | Out-Null`
- Teste: V:1501-1503 · Confiança: alta

**I-83** — `SaveSetup` (snapshot v2) aplica valores por omissão (Version nula → "Unknown", Name vazio → Id), limita a 64 KiB e revalida com `ParseSetup` antes de escrever.
- Fonte: P:336 · Snippet: `ParseSetup(json); // apply the same schema validation before writing an export`
- Teste: R:112-114 · Confiança: alta

**I-84** — O snapshot de instalados exige inventário completo ou parcial e inclui só pacotes com ID e origem válidos e estado «Installed ·» (M:250).
- Fonte: M:248 · Snippet: `if (-not $script:libraryInventory.Complete -and -not $script:libraryInventory.Partial)`
- Teste: sem teste · Confiança: alta

**I-85** — Preferência de vista (`preferences.json`): só lida se tiver até 4096 bytes (M:135) e `View` for 'All apps' ou 'Installed'; erros ignorados.
- Fonte: M:137 · Snippet: `if ($prefs.View -in @('All apps','Installed')) { $script:libraryView=$prefs.View }`
- Teste: sem teste · Confiança: alta

**I-86** — Abrir a pasta de logs usa `explorer.exe` com o caminho entre aspas simples de formatação (não usa `Quote`).
- Fonte: V:768 · Snippet: `Start-Process explorer.exe -ArgumentList ('"{0}"' -f $logDir)`
- Teste: sem teste · Confiança: alta

### Regras de outras fatias impostas em vexan_installers.ps1 (só referência)
- V:1094 uma única operação de remoção de cada vez; V:1136 e M:153 troca de modo bloqueada com fila ou remoção ativas.
- V:1381 só entram no plano de remoção apps `Selected`, `CanRemove` e com estado ≠ 'Success'; V:1242 e V:1246 consentimento novo obrigatório na revisão.
- V:1384 Stop de remoção só ativa `StopRequested`; V:1393-1396 fecho da janela cancelado durante remoção/verificação.
- V:1301, V:1306, V:1312 resultados de remoção e limpeza gravados no mesmo histórico.
- V:1102, V:1380, V:1386 `-SmokeTest` impede inventário e remoção reais.
- Autoatualização e definições: V:118-127 apenas carregam o código; nenhuma regra própria em vexan.

## Lista 1 — Regressões em tests/reliability.ps1

O total real é 56 (somas de `$tests`), confirmando a descrição.

| Linha | N.º | O que afirma | Alvo |
|---|---|---|---|
| 22-27 | 1 | 8 culturas resolvidas + idioma explícito prevalece | `Resolve-AppLanguage` (settings.ps1) |
| 36 | 1 | caminho explícito do WinGet encontrado | `FindWinGet` |
| 39 | 1 | fallback por PATH | `FindWinGet` |
| 42-46 | 1 | 6 argumentos difíceis chegam intactos ao processo | `Quote` + `Run` |
| 47 | 1 | citação igual à do helper de desinstalação | `QuoteArgument` vs `Quote` |
| 48-49 | 1 | 200000 caracteres em cada pipe sem bloqueio | `Run` |
| 50 | 4 | IDs maliciosos rejeitados (`App;Remove-Item`, `--all`, `$(malicious)`, `App ID`) | `Arguments` |
| 51-52 | 1 | tem `--exact` e `--no-upgrade`, sem flags de alargamento | `Arguments` |
| 53 | 1 | `UpdateAsync` não existe | `OneInstallPackages` |
| 55 | 1 | inventário indisponível → Unknown | `InstalledState` |
| 57 | 1 | inventário completo e ausente → Not installed | `InstalledState` |
| 59 | 1 | ID exato → `Installed · 1.0` | `InstalledState` |
| 60 | 1 | nome apresentado não conta | `InstalledState` |
| 62 | 1 | registo duplicado → Unknown | `InstalledState` |
| 63 | 1 | sem IDs → Unknown | `InstalledState` |
| 65 | 1 | export reconhece identidade | `ParseExport` + `InstalledState` |
| 66 | 1 | omissão em export parcial → Unknown | `InstalledState` |
| 67 | 1 | ID inválido no export rejeitado | `ParseExport` |
| 68 | 1 | export `{}` rejeitado | `ParseExport` |
| 70 | 5 | 0, 3010, 1641, 1602, 1603 | `Outcome` |
| 71 | 3 | 0x8A150109/A/B → Restart required | `Outcome` |
| 72 | 1 | 1603 → Failed | `Install` |
| 73 | 1 | 3010 mantém Restart required | `Install` |
| 74 | 1 | 1602 mantém Cancelled | `Install` |
| 75 | 1 | 0x8A150107 → Failed com «connectivity» | `Install` + `Explain` |
| 76 | 1 | saída 0 não vira instalado | `Install` |
| 77-79 | 1 | callback de verificação chamado uma vez, continua Unknown | `Install` |
| 80 | 1 | executável inexistente → Failed | `Install` |
| 87 | 1 | ordem transitiva C,B,A | `Get-Plan` |
| 88 | 1 | ciclo rejeitado | `Get-Plan` |
| 89 | 1 | dependência desconhecida rejeitada | `Get-Plan` |
| 92-97 | 1 | dependente não corre após falha; fica Manual action required | `$worker` |
| 98-99 | 1 | Stop regista os não iniciados como Cancelled | `$worker` |
| 100-109 | 1 | Stop não interrompe o instalador corrente nem inicia o seguinte | `$worker` |
| 111-114 | 1 | ida e volta do snapshot v2 | `SaveSetup`/`ReadSetup` |
| 115 | 6 | campo extra, Apps não-array, duplicado, ID `--all`, versão 99, texto inválido | `ReadSetup` |
| 116 | 1 | perfil v1 aceite | `ReadSetup` |
| 117 | 1 | 65537 bytes rejeitado | `ReadSetup` |
| 118-119 | 1 | redação de caminho, password, Bearer, email, query | `Redact` |
| 120 | 1 | autoteste da desinstalação | `OneInstallUninstall.SelfTest` |
| 121-125 | 2 | histórico corrompido (`malformed`, `[null]`) não é sobrescrito | `Record`/`History` |

## Lista 2 — Comportamentos acidentais, inconsistentes ou prováveis bugs

1. **URL guiado sem validação em runtime** (V:940), ao contrário do diálogo de detalhes (M:90). Com catálogo lido de disco (V:15), uma string arbitrária chega a ShellExecute.
2. **Duas definições de `Load-UserProfile`**: a de V:760-767 é substituída pela de M:223; a primeira é código morto em runtime e valida muito menos.
3. **Variáveis mortas** `$out` e `$err` no worker (V:872-873).
4. **`Set-Selection` limpa antes de validar** (V:529-530): uma chave inválida apagaria a seleção; só não acontece porque quem chama valida antes (M:227).
5. **Dois formatos de exportação**: «Save current selection» grava v1 por `ConvertTo-Json`, sem `ParseSetup` nem limite de tamanho (V:758); o snapshot grava v2 validado (P:331-337).
6. **Mensagem genérica em resultados não falhados**: `Explain` é chamado para qualquer código (P:267), logo 3010 fica com «Process returned 3010 / 0x00000BC2. Review detailed logs…» (P:221).
7. **`$` do regex .NET aceita `\n` final**: `ValidId("Foo.Bar\n")` é verdadeiro (P:94); num ficheiro v1 ou v2 importado passa a validação. O regex de Rust é mais estrito por omissão; decidir conscientemente.
8. **Texto contradiz o código**: a mensagem diz «uncorrelated apps remain Unknown» (P:154), mas um ID de catálogo ausente de um inventário completo dá «Not installed» (P:203). Uma app instalada que o WinGet não correlacione aparece como não instalada (confiança média: depende do que o módulo devolve).
9. **Fallback usa o caminho estático** `WinGetPath` (P:162) e não o `exe` passado a `Install` (P:265). M:4 iguala os dois em runtime, mas pode ficar "" se o WinGet faltar.
10. **Evento 'done' nunca é tratado** (V:886 contra o switch de V:935-944); o fim é detetado por `IsCompleted`.
11. **Stop não atua entre IDs da mesma app** (V:848 contra o ciclo de V:870): no VCRedist os 12 IDs continuam.
12. **Sem inventário, apps multi-ID instalam só o primeiro ID**: «Unknown» não é «Success», logo o `break` de V:877 dispara.
13. **Cada instalação com saída 0 corre um inventário completo** dentro do worker (P:271), até 90 s mais 90 s de fallback. O próprio teste R:76 e R:78 chama o inventário real da máquina.
14. **Aviso de WinGet em falta só depois do consentimento** (V:900-901), e aborta também as apps guiadas do plano.
15. **Resumo final incompleto**: só conta `Failed*` e `Manual*` (V:952-954); Unknown, Cancelled e Restart required não entram. Com Stop, a linha V:955 sobrescreve logo a V:954.
16. **Timeout mata só o processo**, não a árvore (P:123); pwsh ou winget filhos podem ficar vivos.
17. **Truncagem só depois de ler tudo para memória** (P:125-126).
18. **`winget export` sem `--accept-source-agreements`** (P:162), embora a mensagem de erro fale em «source agreements» (P:163). Não se percebe se é deliberado.
19. **Comparações de caixa inconsistentes**: origem sensível a maiúsculas (P:198), ID não; correspondência de IDs importados via `-contains`, insensível (M:232).
20. **Dependência com «Restart required» bloqueia os dependentes** como «Manual action required» (V:853). Parece intencional (APO/Peace), mas não está testado para esse caso.
21. **Logs brutos não são redigidos** (P:266, V:357, V:876); só o diagnóstico é (P:293).
22. **Teste regista ação 'Update'** apesar de a funcionalidade ter sido removida (tests/manager-ui.ps1:308).

## Lista 3 — Dependências de comportamento PowerShell/.NET/WPF

1. **`JavaScriptSerializer`** (P:76, P:303-304): `Version` tem de ser `int` (1.0 falha); chaves da raiz sensíveis a maiúsculas via `DeserializeObject`; limites 4194304 e profundidade 20. Tratamento de chaves duplicadas e de maiúsculas na desserialização tipada (P:151, P:176) não verificado.
2. **Regex .NET** (P:94, P:96, P:282-288, P:325): `$` antes de `\n` final, `(?i)`, `\b`; reproduzir e testar com os mesmos casos.
3. **BOM**: `Encoding.UTF8` escreve BOM (P:234, P:266, P:337) e `Set-Content -Encoding UTF8` do PS 5.1 também (V:758); `File.ReadAllText` remove-o (P:164, P:250, P:298). O leitor em Rust tem de tolerar BOM nos ficheiros existentes.
4. **Linha de comandos crua**: `ProcessStartInfo(exe, arguments)` (P:118) com citação manual (P:97-109). Em Rust usar `raw_arg` ou validar a citação de `Command` com os casos de R:42.
5. **ShellExecute implícito** em `Start-Process <uri>` (V:903, V:940, V:1352, V:315, M:90) e com `-ArgumentList` (V:768, V:1391, M:193).
6. **Runspace + fila concorrente + temporizador do dispatcher** (V:906-915, V:929-931, M:260): tipos partilhados no AppDomain e garantia de thread única da UI entre ticks e cliques.
7. **Hashtable sincronizada** como flag de Stop (V:907).
8. **Operadores PowerShell insensíveis a maiúsculas**: `-contains`, `-eq`, `-in`, `-like` (V:880, V:951-953, M:137, M:232) e chaves de hashtable (V:26-27, V:43), pelo que a chave de perfil "PEACE" resolve 'peace'.
9. **Peculiaridades de dados em PS 5.1**: enumeração de arrays JSON (V:24-25), `Sort-Object` dependente de cultura (V:25), `\p{Nd}`/`\p{L}`.
10. **Âmbito dinâmico** na função aninhada de `Get-Plan` (V:42-52) e veracidade de strings vazias e contagens (`if ($app.Url)` V:861, `$app.Ids.Count` V:489).
11. **Pastas conhecidas**: `GetFolderPath(LocalApplicationData/ProgramFiles)` (P:77-78, P:133) contra `$env:LOCALAPPDATA` (V:348, V:1390) — duas fontes para a mesma raiz; `ProgramFiles` depende da arquitetura do processo.
12. **Substituição atómica** com `File.Replace`/`File.Move` (P:235) e `lock` (P:75).
13. **`StartsWith` sensível à cultura** em «Installed ·» (P:272; V:548; M:26, M:239, M:250).
14. **`Path.GetFullPath`** para a verificação de contenção (M:191).
15. **Base64 de UTF-16LE** para `-EncodedCommand` (P:141).
16. **Formatos de data**: `DateTimeOffset.Now.ToString("o")` (P:225), `Get-Date -Format` (V:350, V:354).
17. **WPF**: diálogos modais com `DialogResult` (V:839, M:219), `MessageBox` (V:787, V:902), diálogos de ficheiro (V:770, V:782, M:201, M:256), cancelamento de `Closing` (V:999).
18. **HRESULT a partir de `int`**: `unchecked((uint)code)` (P:208).

## Lista 4 — O que não foi possível determinar pelo código

1. Os nomes simbólicos dos HRESULT (não constam do código) e se a lista cobre todos os códigos relevantes do WinGet.
2. Que código o WinGet devolve com `--no-upgrade` quando o pacote já está instalado; o código apenas trata 0x8A150061 e 0x8A15010D como «verificar».
3. Que `Source` e `Id` o `Get-WinGetPackage` devolve para pacotes não correlacionados (determina o ponto 8 da lista 2).
4. Se `--disable-interactivity` sem `--silent` impede UI dos instaladores ou UAC; nada nesta fatia pede elevação, e o manifesto do launcher é de outra fatia.
5. Se o binário distribuído substitui os marcadores `@@...@@` e se carrega `1nstall.Helpers.dll` pré-compilado (V:57-58) em vez do código-fonte: não li scripts de build nem o launcher.
6. O comportamento de `Set-UiValue`, `Convert-UiText`, `Initialize-AppSettings` e `Get-AppLightMode` (em `src/settings.ps1`, não lido). As comparações de estado usam literais ingleses sobre `$statuses`; não confirmei que a tradução não os altera.
7. O caminho `$nativeCards` (`dist/1nstall.UI.dll`, `OneInstall.NativeUI`, V:597-606) e `interface.xaml` não foram lidos; a criação de cartões nesse modo não foi verificada.
8. Se a ausência de `--accept-source-agreements` no `winget export` é deliberada.
9. Os testes do worker cobrem `Requires`, Stop e falha, mas não o ramo guiado (`Url`) nem apps multi-ID; esses comportamentos vêm só da leitura do código.
