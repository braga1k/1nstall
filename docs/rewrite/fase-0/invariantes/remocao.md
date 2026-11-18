## Invariantes (remoção de apps e limpeza de resíduos) — v3.6.0

Abreviaturas: `UH` = `src/uninstall-helper.cs`; `VX` = `vexan_installers.ps1`; `MU` = `src/manager-ui.ps1`. "SelfTest" = asserções em `UH:764-797`, executadas por `tests/reliability.ps1:120` e `tests/uninstall.ps1:7`.

### A. Inventário

**U-01**
- Statement: As apps desktop são enumeradas em HKCU e HKLM, cada uma nas vistas 64 e 32 bits, sob `Software\Microsoft\Windows\CurrentVersion\Uninstall`.
- Source: UH:136 (constante em UH:90)
- Snippet: `foreach (bool machine in new[] { false, true }) foreach (bool view32 in new[] { false, true })`
- Test: tests/uninstall.ps1:12-13 (só valida Name/Id não vazios)
- Confidence: alta

**U-02**
- Statement: Entradas sem `DisplayName` (vazio/whitespace) são ignoradas.
- Source: UH:148
- Snippet: `if (key == null || String.IsNullOrWhiteSpace(Text(key, "DisplayName"))) continue;`
- Test: sem teste
- Confidence: alta

**U-03**
- Statement: No inventário visível (includeHidden=false) excluem-se entradas com `SystemComponent`=="1", `ParentKeyName` não vazio ou `ReleaseType` a conter `Update|Hotfix` (case-insensitive); o inventário de protecção (includeHidden=true) inclui-as.
- Source: UH:149
- Snippet: `Regex.IsMatch(Text(key, "ReleaseType"), "Update|Hotfix", RegexOptions.IgnoreCase)`
- Test: sem teste
- Confidence: alta

**U-04**
- Statement: Entradas HKCU são deduplicadas entre vistas por `RegistryPath` (fica a primeira, 64 bits); entradas HKLM mantêm-se distintas por Id `HKLM64:`/`HKLM32:`+subchave.
- Source: UH:171 (formato do Id em UH:151)
- Snippet: `GroupBy(a => !a.Machine ? "HKCU:" + a.RegistryPath : a.Id, StringComparer.OrdinalIgnoreCase)`
- Test: sem teste
- Confidence: alta

**U-05**
- Statement: `CanRemove` é verdadeiro só se `GetCommand` aceitar o comando de desinstalação da entrada.
- Source: UH:162
- Snippet: `try { GetCommand(app); app.CanRemove = true; } catch { app.CanRemove = false; }`
- Test: sem teste
- Confidence: alta

**U-06**
- Statement: O inventário Store usa `Get-AppxPackage` (só utilizador actual, sem `-AllUsers`), exclui `IsFramework`, `IsResourcePackage` e `NonRemovable`, com timeout de 60000 ms.
- Source: UH:178
- Snippet: `Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage -and -not $_.NonRemovable }`
- Test: sem teste
- Confidence: alta

**U-07**
- Statement: Pacotes "sparse" de integração de shell (`AllowExternalContent`=true e nenhuma Application com `AppListEntry` ≠ 'none') não são listados como apps removíveis.
- Source: UH:184 (cálculo em UH:178)
- Snippet: `if (row.ContainsKey("ShellComponent") && Convert.ToBoolean(row["ShellComponent"])) continue;`
- Test: sem teste
- Confidence: alta

**U-08**
- Statement: `PackageFullName` e `PackageFamilyName` têm de corresponder a `^[A-Za-z0-9._-]+$`, senão o pacote é descartado.
- Source: UH:186
- Snippet: `!Regex.IsMatch(id, @"^[A-Za-z0-9._-]+$") || !Regex.IsMatch(family, @"^[A-Za-z0-9._-]+$")`
- Test: sem teste
- Confidence: alta

**U-09**
- Statement: Falha do inventário Store gera apenas um aviso e o inventário desktop é devolvido na mesma.
- Source: UH:191
- Snippet: `result.Warnings.Add("Microsoft Store apps could not be read: " + e.Message);`
- Test: sem teste
- Confidence: alta

**U-10**
- Statement: O PowerShell auxiliar é lançado pelo caminho absoluto em System32 com `-NoProfile -NonInteractive -EncodedCommand`; em timeout o processo é morto e lança-se `TimeoutException`; exit code ≠ 0 lança erro com o stderr.
- Source: UH:128 (argumentos em UH:122; caminho em UH:91)
- Snippet: `if (!process.WaitForExit(timeout)) { process.Kill(); throw new TimeoutException(`
- Test: sem teste
- Confidence: alta

### B. Validação do comando de desinstalação

**U-11**
- Statement: Para entradas MSI (`WindowsInstaller`=="1") o `UninstallString` é ignorado: o nome da subchave tem de passar `Guid.TryParse`, senão o comando é recusado.
- Source: UH:225
- Snippet: `if (!Guid.TryParse(code, out guid)) throw new InvalidOperationException(`
- Test: UH:785 (SelfTest)
- Confidence: alta

**U-12**
- Statement: O comando MSI é exactamente `<System32>\msiexec.exe /x {guid-normalizado-minúsculas}`, sem `/qn`, `/quiet` nem `/norestart`.
- Source: UH:226
- Snippet: `"msiexec.exe"), "/x {" + guid.ToString() + "}");`
- Test: UH:784 (SelfTest)
- Confidence: alta

**U-13**
- Statement: Num comando entre aspas, o executável é o argv[0] de `CommandLineToArgvW` e os argumentos são o texto bruto após a primeira aspa de fecho (não re-tokenizados, nada acrescentado); sem aspa de fecho é recusado.
- Source: UH:234 (argv[0] em UH:231-233)
- Snippet: `int end = command.IndexOf('"', 1); if (end < 0) throw new InvalidOperationException(`
- Test: UH:781 (SelfTest)
- Confidence: alta

**U-14**
- Statement: Num comando sem aspas, o executável é o prefixo mais curto que termina em `.exe` seguido de espaço ou fim; se não houver, recusa com "No executable uninstaller".
- Source: UH:240-241
- Snippet: `var match = Regex.Match(command, @"^(.+?\.exe)(?=\s|$)", RegexOptions.IgnoreCase);`
- Test: UH:782 (SelfTest)
- Confidence: alta

**U-15**
- Statement: O executável tem de ser caminho "rooted", não começar por `\\` (UNC), existir em disco e terminar em `.exe`.
- Source: UH:244
- Snippet: `!System.IO.Path.IsPathRooted(exe) || exe.StartsWith(@"\\") || !File.Exists(exe)`
- Test: sem teste (só o caminho feliz em UH:781)
- Confidence: alta

**U-16**
- Statement: Recusam-se executáveis cujo nome (sem extensão) seja cmd, powershell, pwsh, wscript, cscript, rundll32, reg ou mshta.
- Source: UH:245
- Snippet: `@"^(cmd|powershell|pwsh|wscript|cscript|rundll32|reg|mshta)$", RegexOptions.IgnoreCase`
- Test: sem teste
- Confidence: alta

### C. Execução da remoção

**U-17**
- Statement: Antes de lançar, o registo é relido do zero e procurado por Id; o comando executado vem dessa leitura fresca, nunca do inventário/histórico em memória.
- Source: UH:343 (uso em UH:349)
- Snippet: `var current = Desktop(new AppInventory(), false).FirstOrDefault(a => a.Id == app.Id);`
- Test: sem teste directo (tests/uninstall-process.ps1:54 passa por este caminho)
- Confidence: alta

**U-18**
- Statement: Se o registo já não existir na releitura, o resultado é "Success" sem lançar nada e sem marcar nenhuma flag de verificação (logo nunca habilita limpeza).
- Source: UH:344
- Snippet: `"Exact registration already absent; ownership cannot be established for cleanup."`
- Test: sem teste
- Confidence: alta

**U-19**
- Statement: Location/Name/Publisher são sobrescritos pelo registo fresco, `IdentityVerified`=true, e `OwnershipVerified` só é true se a Location fresca for não vazia e a pasta existir antes da desinstalação.
- Source: UH:348 (UH:346-347)
- Snippet: `!String.IsNullOrWhiteSpace(current.Location) && Directory.Exists(current.Location);`
- Test: tests/uninstall.ps1:44-46 (flags simuladas), tests/uninstall.ps1:56-59
- Confidence: alta

**U-20**
- Statement: O desinstalador é lançado com `UseShellExecute=true` e verbo `runas` apenas quando o registo é HKLM; registos HKCU correm sem pedido de elevação.
- Source: UH:350 (UH:349)
- Snippet: `if (app.Machine) start.Verb = "runas";`
- Test: sem teste (fixtures só HKCU)
- Confidence: alta

**U-21**
- Statement: A remoção Store revalida o Id com `^[A-Za-z0-9._-]+$`, injecta-o como literal com aspas simples duplicadas e executa `Get-AppxPackage | Where PackageFullName -eq … -and -not NonRemovable -and -not IsFramework | Remove-AppxPackage -ErrorAction Stop` (utilizador actual, timeout 180000 ms).
- Source: UH:338 (validação UH:336; `Literal` UH:101)
- Snippet: `-and -not $_.NonRemovable -and -not $_.IsFramework } | Remove-AppxPackage -ErrorAction Stop`
- Test: sem teste
- Confidence: alta

**U-22**
- Statement: A fila é estritamente sequencial e só avança quando o processo raiz e todos os descendentes seguidos terminaram (polling de 100 ms, sem timeout).
- Source: UH:310-311
- Snippet: `if (tracked.Values.All(p => p.HasExited)) return;`
- Test: tests/uninstall-process.ps1:57
- Confidence: alta

**U-23**
- Statement: Um processo só é seguido como descendente se o pai estiver seguido e o seu `StartTime` não for anterior ao nascimento registado do pai (para a raiz, o instante do lançamento).
- Source: UH:298 (filtro de pai em UH:292)
- Snippet: `if (born < parents[(int)entry.Parent]) continue;`
- Test: tests/uninstall-process.ps1:57-60 (árvore raiz→filho→neto)
- Confidence: alta

**U-24**
- Statement: Protecção contra reutilização de PID: descarta-se um candidato nascido depois de o pai seguido ter saído, e o handle do processo é aberto e retido no momento em que é aceite.
- Source: UH:300 e UH:302-303
- Snippet: `if (parent.HasExited && born > parent.ExitTime.ToUniversalTime()) continue;`
- Test: sem teste específico de reutilização de PID
- Confidence: média (lógica clara; comportamento real com processos elevados não verificado)

**U-25**
- Statement: O código nunca mata processos do editor; o único `Kill()` do ficheiro é o do PowerShell auxiliar em timeout (UH:128).
- Source: UH:267 (comentário; regra cumprida por ausência de Kill em UH:268-315)
- Snippet: `// Observe only descendants born during this launch; never kill publisher processes.`
- Test: tests/uninstall-process.ps1:69 (Stop espera pelo filho)
- Confidence: alta

**U-26**
- Statement: Se o snapshot Toolhelp falhar, a remoção lança erro ("verify removal manually") em vez de assumir conclusão.
- Source: UH:277
- Snippet: `"Cannot track the publisher uninstaller; verify removal manually."`
- Test: sem teste
- Confidence: alta

**U-27**
- Statement: Exit code 3010 ou 1641 do processo raiz ⇒ "Restart required", grava `RestartRequestedAt = BootTime`, não verifica o registo e retém a limpeza.
- Source: UH:358
- Snippet: `if (process.ExitCode == 3010 || process.ExitCode == 1641) { app.RestartRequestedAt = BootTime;`
- Test: sem teste (tests/process-fixture.cs só é usado por tests/reliability.ps1 para o helper de pacotes)
- Confidence: alta

**U-28**
- Statement: Exit code ≠ 0 do processo raiz ⇒ "Cancelled" se 1602 ou 1223, caso contrário "Failed"; em ambos não há verificação nem limpeza.
- Source: UH:359
- Snippet: `item.Outcome = process.ExitCode == 1602 || process.ExitCode == 1223 ? "Cancelled" : "Failed";`
- Test: sem teste (tests/uninstall-process.ps1:72 mostra que o 1602 de um descendente é ignorado)
- Confidence: alta

**U-29**
- Statement: Excepções: `Win32Exception` com NativeErrorCode 1223 (UAC recusado) ⇒ "Cancelled"; `TimeoutException` ⇒ "Unknown"; qualquer outra ⇒ "Failed".
- Source: UH:369
- Snippet: `NativeErrorCode == 1223 ? "Cancelled" : e is TimeoutException ? "Unknown" : "Failed"`
- Test: sem teste
- Confidence: alta

**U-30**
- Statement: Exit code 0 não é sucesso: só é "Success" (e `RemovalVerified=true`) se um inventário fresco mostrar o registo exacto ausente; se ainda registado ⇒ "Manual action required".
- Source: UH:365-366
- Snippet: `else if (Registered(app, after)) { item.Outcome = "Manual action required";`
- Test: tests/uninstall-process.ps1:72 e :60
- Confidence: alta

**U-31**
- Statement: Para apps Store, se o inventário de verificação tiver avisos, o resultado fica "Unknown" e a limpeza é retida.
- Source: UH:364
- Snippet: `if (app.Kind == "Microsoft Store" && after.Warnings.Count > 0) { item.Message =`
- Test: sem teste
- Confidence: alta

**U-32**
- Statement: "Registado" para desktop = a chave exacta abre no mesmo hive e vista; um `RegistryPath` vazio ou fora de `…\Uninstall\` conta como ainda registado (fail-closed).
- Source: UH:251-253
- Snippet: `!app.RegistryPath.StartsWith(Arp + "\\", StringComparison.OrdinalIgnoreCase)) return true;`
- Test: tests/uninstall.ps1:69-73
- Confidence: alta

**U-33**
- Statement: "Registado" para Store = existe no inventário um pacote com o mesmo PackageFullName OU a mesma PackageFamily.
- Source: UH:250
- Snippet: `return inventory.Apps.Any(a => a.Id == app.Id || a.PackageFamily == app.PackageFamily);`
- Test: sem teste
- Confidence: alta

**U-34**
- Statement: Stop é uma flag (reposta a false no início de cada `RemoveAsync`) lida apenas entre apps: as seguintes ficam "Cancelled / Not started"; a app em curso nunca é interrompida.
- Source: UH:329 (reset em UH:322)
- Snippet: `item.Outcome = "Cancelled"; item.Message = "Not started: stop after current requested.";`
- Test: tests/uninstall-process.ps1:69
- Confidence: alta

**U-35**
- Statement: Porta de reinício: a app está "à espera de reinício" enquanto |RestartRequestedAt − BootTime actual| < 2 minutos (BootTime = UtcNow − GetTickCount64); bloqueia scan e limpeza.
- Source: UH:104 (uso em UH:612 e UH:687)
- Snippet: `Math.Abs(app.RestartRequestedAt - BootTime) < TimeSpan.TicksPerMinute * 2`
- Test: UH:775-777 (SelfTest)
- Confidence: alta

### D. Histórico de remoções

**U-36**
- Statement: As apps da fila são gravadas em `%LOCALAPPDATA%\1nstall\uninstall-history.json` antes e depois da remoção (substituição por Id), mantendo só as últimas 100.
- Source: UH:206 (chamadas em UH:324, UH:373, UH:623; caminho UH:97)
- Snippet: `Json().Serialize(history.Skip(Math.Max(0, history.Count - 100)).ToList())`
- Test: tests/uninstall-process.ps1:59
- Confidence: alta

**U-37**
- Statement: Ao carregar, um histórico > 1048576 bytes ou ilegível é tratado como lista vazia (sem erro).
- Source: UH:198-199
- Snippet: `if (new FileInfo(HistoryFile).Length > 1048576) return new List<InstalledApp>();`
- Test: sem teste
- Confidence: alta

**U-38**
- Statement: `Selected` é deliberadamente excluído da serialização (`[ScriptIgnore]`); todas as outras propriedades públicas (incl. Command, Location, RegistryPath e as três flags de verificação) são persistidas.
- Source: UH:43
- Snippet: `[ScriptIgnore] public bool Selected { get { return selected; }`
- Test: tests/uninstall-process.ps1:59
- Confidence: alta

**U-39**
- Statement: Só apps presentes no histórico do 1nstall são alvo de scan de resíduos (alvos = `LoadHistory()`, recarregado após cada remoção).
- Source: VX:1309-1310 (também VX:1015 e VX:1110)
- Snippet: `$script:uninstallTargets=@([OneInstallUninstall]::LoadHistory())`
- Test: VX:1839 (smoke embutido: Remove → Scan automático)
- Confidence: alta

### E. Condições para scan de resíduos

**U-40**
- Statement: O conjunto de protecção ("active") = todas as entradas ARP incluindo ocultas + apps Store; se a leitura ARP de protecção tiver qualquer aviso, o scan aborta sem oferecer nada.
- Source: UH:606-607
- Snippet: `"Installed-app protection could not be verified. No leftover scan was offered."`
- Test: sem teste
- Confidence: alta

**U-41**
- Statement: Uma app à espera de reinício não é analisada.
- Source: UH:612
- Snippet: `result.Messages.Add(app.Name + ": restart Windows before scanning leftovers."); continue; }`
- Test: sem teste (a porta em si: UH:775-777)
- Confidence: alta

**U-42**
- Statement: Uma app ainda registada não é analisada.
- Source: UH:614
- Snippet: `if (Registered(app, inventory)) { result.Messages.Add(app.Name + ": still registered.`
- Test: tests/uninstall.ps1:69-73 (via CleanAsync)
- Confidence: alta

**U-43**
- Statement: Apps Store nunca têm limpeza manual (nem WindowsApps nem Packages): o scan termina com "Windows manages its package data".
- Source: UH:616
- Snippet: `result.Messages.Add(app.Name + ": removed; Windows manages its package data."); continue;`
- Test: sem teste
- Confidence: alta

**U-44**
- Statement: Sem `RemovalVerified` e sem (`IdentityVerified` ou `OwnershipVerified`) a limpeza é retida ("removal evidence is unavailable").
- Source: UH:627
- Snippet: `if (!app.RemovalVerified || !(app.IdentityVerified || app.OwnershipVerified))`
- Test: tests/uninstall.ps1:43-44
- Confidence: alta

**U-45**
- Statement: Verificação tardia: se a identidade/posse foi capturada e o registo está agora ausente, o scan marca `RemovalVerified`, persiste-o e emite "Success".
- Source: UH:619-626
- Snippet: `if (!app.RemovalVerified && (app.IdentityVerified || app.OwnershipVerified))`
- Test: tests/uninstall.ps1:77-79; tests/uninstall-queue.ps1:43-45
- Confidence: alta

### F. Descoberta de pastas

**U-46**
- Statement: Raízes de descoberta: Roaming AppData, Local AppData, `%USERPROFILE%\AppData\LocalLow`, ProgramData, Program Files, Program Files (x86) — nunca o disco inteiro.
- Source: UH:462-467
- Snippet: `Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @"AppData\LocalLow")`
- Test: tests/uninstall.ps1:50-51 (LocalAppData)
- Confidence: alta

**U-47**
- Statement: A pasta de instalação registada só é candidata se `OwnershipVerified` e passar `SafeDirectory`.
- Source: UH:631
- Snippet: `if (app.OwnershipVerified && SafeDirectory(full, app, active)) AddFolder(full, app, result, seen);`
- Test: tests/uninstall.ps1:48-54
- Confidence: alta

**U-48**
- Statement: A descoberta desce no máximo 3 níveis abaixo de cada raiz (recursão enquanto `depth < 2`, a partir de 0).
- Source: UH:572
- Snippet: `else if (depth < 2 && !active.Any(a => !String.IsNullOrWhiteSpace(a.Location)`
- Test: tests/uninstall.ps1:25 e :50 (candidato a 3 níveis)
- Confidence: alta

**U-49**
- Statement: Limite de 20000 directorias por raiz e por app; ao excedê-lo incrementa `IncompleteChecks`, regista mensagem e pára essa raiz.
- Source: UH:566
- Snippet: `if (++count > 20000) { result.IncompleteChecks++;`
- Test: sem teste
- Confidence: alta

**U-50**
- Statement: A descoberta não entra em pontos de reparse, em pastas dentro da Location de uma app instalada, nem em pastas chamadas Microsoft, Windows, WindowsApps, Packages, Common Files ou 1nstall.
- Source: UH:567 e UH:572
- Snippet: `@"^(Microsoft|Windows|WindowsApps|Packages|Common Files|1nstall)$", RegexOptions.IgnoreCase`
- Test: sem teste
- Confidence: alta

**U-51**
- Statement: Normalização de nomes: `Token` remove tudo o que não é letra/dígito Unicode e passa a minúsculas invariantes; todas as correspondências são igualdade exacta de tokens, nunca substring.
- Source: UH:379
- Snippet: `Regex.Replace(name ?? "", @"[^\p{L}\p{N}]", "").ToLowerInvariant();`
- Test: UH:767 (SelfTest)
- Confidence: alta

**U-52**
- Statement: Um nome só é "produto" se o token tiver ≥ 3 caracteres e não for genérico (application(s), app(s), bin, current, x64, x86, software, microsoft, windows, programs, commonfiles, packages, data, cache, temp, 1nstall, launcher, update, uninstall, installer, install, setup, client, public, user, users).
- Source: UH:380
- Snippet: `return Token(name).Length >= 3 && !Regex.IsMatch(Token(name), @"^(application|applications|app`
- Test: sem teste directo
- Confidence: alta

**U-53**
- Statement: Ao nome da app retira-se o sufixo de arquitectura entre parênteses e tudo a partir do primeiro token de versão/arquitectura; nomes com `\/:*?"<>|` são rejeitados.
- Source: UH:384-386
- Snippet: `if (Product(name) && !Regex.IsMatch(name, @"[\\/:*?""<>|]")) names.Add(name);`
- Test: UH:767 e UH:769 (SelfTest)
- Confidence: alta

**U-54**
- Statement: O nome da pasta-folha da Location só conta como nome da app se for "produto" e (token igual ao do nome, ou (identidade/posse verificada, ou folha ≥ 6 caracteres contida no nome) e o token do Publisher não contiver a folha) — protecção de raiz de fabricante.
- Source: UH:393
- Snippet: `app.IdentityVerified || app.OwnershipVerified || Token(leaf).Length >= 6 && Token(name).Contains(`
- Test: UH:771 (SelfTest)
- Confidence: alta

**U-55**
- Statement: `SafeDirectory` rejeita caminhos UNC, com menos de 8 caracteres ou inexistentes.
- Source: UH:404
- Snippet: `if (path.StartsWith(@"\\") || path.Length < 8 || !Directory.Exists(path)) return false;`
- Test: sem teste
- Confidence: alta

**U-56**
- Statement: Rejeita tudo o que esteja dentro da pasta Windows.
- Source: UH:406
- Snippet: `if (Inside(path, windows)) return false;`
- Test: sem teste
- Confidence: alta

**U-57**
- Statement: Rejeita tudo dentro de Documentos, Ambiente de Trabalho, Imagens, Música, Vídeos (pastas conhecidas) e de `%USERPROFILE%\Downloads` e `%USERPROFILE%\OneDrive` (nomes fixos).
- Source: UH:407-410
- Snippet: `if (Inside(path, home + "\\Downloads") || Inside(path, home + "\\OneDrive")) return false;`
- Test: UH:778 (SelfTest, só MyDocuments)
- Confidence: alta

**U-58**
- Statement: Rejeita o caminho se for exactamente a raiz da unidade, o perfil, Program Files, Program Files (x86), ProgramData, Local AppData ou Roaming AppData.
- Source: UH:411-412
- Snippet: `Full(root).Equals(path, StringComparison.OrdinalIgnoreCase)) return false;`
- Test: UH:778 (SelfTest, LocalApplicationData)
- Confidence: alta

**U-59**
- Statement: Rejeita qualquer caminho sob `<unidade do Windows>\Users` que não esteja dentro do perfil do utilizador actual (outros perfis, Public, Default).
- Source: UH:413-414
- Snippet: `if (Inside(path, users) && !Inside(path, home)) return false;`
- Test: sem teste
- Confidence: alta

**U-60**
- Statement: Rejeita tudo dentro de `Program Files\Common Files`, `Program Files (x86)\Common Files`, `Program Files\WindowsApps` e `%USERPROFILE%\AppData\Local\Packages`.
- Source: UH:415-416
- Snippet: `+ "\\WindowsApps", home + @"\AppData\Local\Packages" })`
- Test: sem teste
- Confidence: alta

**U-61**
- Statement: O token do nome da pasta tem de ser igual ao token de um dos nomes da app dona.
- Source: UH:417
- Snippet: `Names(owner).Any(n => Token(n) == Token(System.IO.Path.GetFileName(path`
- Test: UH:793 (SelfTest); tests/uninstall.ps1:48-51
- Confidence: alta

**U-62**
- Statement: Colisão: rejeita se alguma app instalada tiver um nome com o mesmo token ou um Publisher cujo token seja igual ao da pasta.
- Source: UH:419
- Snippet: `Names(a).Any(n => Token(n) == product) || Token(a.Publisher) == product`
- Test: sem teste para pastas (equivalente de registo em UH:769-770)
- Confidence: alta

**U-63**
- Statement: Rejeita se a Location de alguma app instalada estiver dentro da pasta ou a pasta dentro dessa Location.
- Source: UH:424
- Snippet: `if (Inside(path, location) || Inside(location, path)) return false;`
- Test: UH:794 (SelfTest)
- Confidence: alta

**U-64**
- Statement: Rejeita se a pasta ou qualquer antecessor até à raiz for ponto de reparse; qualquer excepção em `SafeDirectory` devolve false.
- Source: UH:426-427 (catch em UH:430)
- Snippet: `if ((parent.Attributes & FileAttributes.ReparsePoint) != 0) return false;`
- Test: sem teste
- Confidence: alta

**U-65**
- Statement: "Dentro de" é comparação ordinal case-insensitive com fronteira `\` (igual à raiz ou prefixo `raiz\`), pelo que `…\AppSibling` não está dentro de `…\App`.
- Source: UH:378
- Snippet: `path.StartsWith(root + "\\", StringComparison.OrdinalIgnoreCase); }`
- Test: UH:773 (SelfTest); tests/uninstall.ps1:64
- Confidence: alta

**U-66**
- Statement: Uma pasta candidata é percorrida por inteiro: mais de 20000 entradas ou qualquer ponto de reparse (ficheiro ou pasta) ⇒ não é oferecida, fica "folder kept" e conta como verificação incompleta.
- Source: UH:445-446 e UH:478
- Snippet: `result.Messages.Add(folder + ": linked files or scan limit; folder kept."); return; }`
- Test: UH:793 (SelfTest, caso positivo); sem teste do caso negativo
- Confidence: alta

**U-67**
- Statement: A confiança é "Linked path" só quando `OwnershipVerified` e a pasta é exactamente a Location registada; tudo o resto é "Name match"; nenhum item vem pré-seleccionado.
- Source: UH:479-481
- Snippet: `Confidence = recorded ? "Linked path" : "Name match",`
- Test: tests/uninstall.ps1:51-54
- Confidence: alta

### G. Descoberta no registo

**U-68**
- Statement: Procuram-se chaves de produto sob `Software` em HKCU/HKLM × 64/32 bits, até 3 níveis, com limite de 20000 chaves por hive/vista por app.
- Source: UH:595 (limite em UH:585; ciclo em UH:639-645)
- Snippet: `else if (depth < 2) DiscoverKeys(child, key, depth + 1, machine, view32, app,`
- Test: tests/uninstall.ps1:26 e :50
- Confidence: alta

**U-69**
- Statement: Nunca se entra nem se aceita qualquer componente chamado Microsoft, Windows, Classes, Policies, RegisteredApplications, Clients ou Wow6432Node.
- Source: UH:498 (uso em UH:586 e UH:489)
- Snippet: `@"^(Microsoft|Windows|Classes|Policies|RegisteredApplications|Clients|Wow6432Node)$"`
- Test: UH:769 (SelfTest: `Software\Microsoft\Windows` recusado)
- Confidence: alta

**U-70**
- Statement: Uma chave só é candidata se o caminho for `Software\` + 1 a 3 componentes com apenas letras, dígitos, espaço e `._()+-`.
- Source: UH:486
- Snippet: `@"^Software\\[\p{L}\p{N} ._()+-]+(?:\\[\p{L}\p{N} ._()+-]+){0,2}$", RegexOptions.IgnoreCase`
- Test: UH:770 (SelfTest: `" & bad` recusado)
- Confidence: alta

**U-71**
- Statement: A folha da chave tem de ter token igual a um nome da app dona (uma chave só com o nome do fabricante é recusada).
- Source: UH:488
- Snippet: `if (!Names(owner).Any(n => Token(n) == Token(leaf))) return false;`
- Test: UH:769 (SelfTest)
- Confidence: alta

**U-72**
- Statement: Colisão no registo: recusa se alguma app instalada tiver nome ou Publisher com token igual ao da folha.
- Source: UH:490
- Snippet: `Names(a).Any(n => Token(n) == Token(leaf)) || Token(a.Publisher) == Token(leaf)`
- Test: UH:770 (SelfTest)
- Confidence: alta

**U-73**
- Statement: Valores de rasto só são considerados em 7 chaves fixas (AppCompatFlags\Layers, Compatibility Assistant\Store, Search\JumplistData, MuiCache, FeatureUsage\AppBadgeUpdated, FeatureUsage\AppSwitched, UserAssist\{CEBFF5CD-…}\Count) e o nome do valor não pode ser vazio nem conter `"`, CR, LF ou NUL.
- Source: UH:539 (lista em UH:499-507)
- Snippet: `value.IndexOfAny(new[] { '"', '\r', '\n', '\0' }) >= 0) return false;`
- Test: UH:773 (SelfTest: `" /f` recusado)
- Confidence: alta

**U-74**
- Statement: Para rastos, a Location da app tem de existir como dado, não estar dentro de Windows e não ser exactamente o perfil, Program Files, Program Files (x86), ProgramData, Local ou Roaming AppData.
- Source: UH:542-546
- Snippet: `location.Equals(Full(Environment.GetFolderPath(special)), StringComparison.OrdinalIgnoreCase)`
- Test: sem teste
- Confidence: alta

**U-75**
- Statement: O caminho descodificado do valor (ROT13 em UserAssist, sufixos `.FriendlyAppName`/`.ApplicationCompany` removidos, GUID de pasta conhecida resolvido) tem de ser "rooted", não UNC e terminar em `.exe`.
- Source: UH:547 (descodificação UH:519-535)
- Snippet: `|| path.StartsWith(@"\\") || !path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))`
- Test: UH:774 (SelfTest)
- Confidence: alta

**U-76**
- Statement: O valor só é candidato se o executável estiver dentro da Location, a folha da Location for um nome da app, e o executável já NÃO existir em disco.
- Source: UH:549
- Snippet: `|| !Inside(path, location) || File.Exists(path)) return false;`
- Test: UH:773 (SelfTest); tests/uninstall.ps1:63-64
- Confidence: alta

**U-77**
- Statement: Recusa o rasto se alguma app instalada partilhar um token de nome com a dona ou tiver Location sobreposta.
- Source: UH:550-552
- Snippet: `Names(a).Any(n => Names(owner).Any(o => Token(o) == Token(n)`
- Test: UH:773 (SelfTest); tests/uninstall.ps1:65
- Confidence: alta

**U-78**
- Statement: Valores de rasto exigem `OwnershipVerified` tanto no scan como na limpeza.
- Source: UH:654 e UH:699
- Snippet: `if (app.OwnershipVerified && SafeRegistryValue(key, value, app, active) && seen.Add(`
- Test: sem teste directo
- Confidence: alta

### H. Limpeza

**U-79**
- Statement: A limpeza aborta antes de apagar seja o que for se a leitura ARP de protecção tiver avisos.
- Source: UH:673
- Snippet: `"Installed-app protection could not be verified; cleanup stopped."`
- Test: sem teste
- Confidence: alta

**U-80**
- Statement: Antes de qualquer eliminação cria-se `%LOCALAPPDATA%\1nstall\Backups\yyyyMMdd-HHmmss-<8 hex>` e grava-se `items.json` com os itens pedidos; no fim grava-se `results.json`.
- Source: UH:674-676 e UH:719
- Snippet: `DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N").Substring(0, 8)`
- Test: tests/uninstall.ps1:81-85 (pasta e .reg)
- Confidence: alta

**U-81**
- Statement: Antes de cada item, as apps desktop instaladas são relidas; se a releitura tiver avisos, o item falha.
- Source: UH:684-685
- Snippet: `"Shared-app protection could not be refreshed."`
- Test: sem teste
- Confidence: alta

**U-82**
- Statement: Antes de cada item, a dona tem de estar `RemovalVerified`, com identidade ou posse verificada, não à espera de reinício e não registada; senão o item é bloqueado.
- Source: UH:687
- Snippet: `WaitingForRestart(item.Owner) || Registered(item.Owner, inventory)) throw`
- Test: tests/uninstall.ps1:68-74
- Confidence: alta

**U-83**
- Statement: Uma pasta só é apagada se, nesse momento, ainda estiver no âmbito de descoberta, passar `SafeDirectory` e `MeasureFolder` (sem reparse, ≤ 20000 entradas).
- Source: UH:691
- Snippet: `!DiscoveryFolder(item.Path, item.Owner) || !SafeDirectory(item.Path, item.Owner, active)`
- Test: tests/uninstall.ps1:72-73
- Confidence: alta

**U-84**
- Statement: Âmbito de descoberta = exactamente a Location verificada da dona, ou um caminho dentro de uma raiz de dados com no máximo 3 componentes abaixo dela.
- Source: UH:472-473
- Snippet: `Split(new[] { '\\' }, StringSplitOptions.RemoveEmptyEntries).Length <= 3);`
- Test: sem teste directo
- Confidence: alta

**U-85**
- Statement: Pastas vão só para a Reciclagem via `IFileOperation` com flags `0x00080000|0x20000000|0x00040000|0x00100000|0x0400|0x0010|0x0004` (RECYCLEONDELETE, ADDUNDORECORD, SHOWELEVATIONPROMPT, EARLYFAILURE, NOERRORUI, NOCONFIRMATION, SILENT); não existe caminho de eliminação permanente.
- Source: UH:753
- Snippet: `SetOperationFlags(0x00080000 | 0x20000000 | 0x00040000 | 0x00100000 | 0x0400 | 0x0010 | 0x0004);`
- Test: tests/uninstall.ps1:93-96
- Confidence: alta (quanto ao código; ver lista 3 sobre o comportamento da Shell)

**U-86**
- Statement: A reciclagem só é sucesso se a operação não foi abortada e a pasta já não existe no local original.
- Source: UH:756
- Snippet: `if (aborted || Directory.Exists(path)) throw new IOException(`
- Test: tests/uninstall.ps1:82
- Confidence: alta

**U-87**
- Statement: Um item de registo é revalidado no momento (`SafeRegistry` para chaves; `OwnershipVerified` + `SafeRegistryValue` para valores).
- Source: UH:699
- Snippet: `: !item.Owner.OwnershipVerified || !SafeRegistryValue(item.Path, item.ValueName,`
- Test: sem teste directo
- Confidence: alta

**U-88**
- Statement: Antes de apagar faz-se `reg.exe export "<chave>" "<guid>.reg" /y /reg:32|64` (reg.exe de System32, sem elevação).
- Source: UH:702 (caminho de reg.exe em UH:92)
- Snippet: `"export " + QuoteArgument(key) + " " + QuoteArgument(backup) + " /y /reg:"`
- Test: tests/uninstall.ps1:84-92 (exporta e restaura)
- Confidence: alta

**U-89**
- Statement: Se o export devolver exit ≠ 0, o ficheiro não existir ou tiver menos de 10 bytes, a chave/valor não é apagado ("Registry backup failed; key was kept").
- Source: UH:704
- Snippet: `process.ExitCode != 0 || !File.Exists(backup) || new FileInfo(backup).Length < 10)`
- Test: sem teste do caso de falha
- Confidence: alta

**U-90**
- Statement: Por cada item de registo acrescenta-se a `RESTORE.txt` a chave, a vista e o comando `reg.exe import` (com nota "as administrator" para HKLM).
- Source: UH:705
- Snippet: `File.AppendAllText(System.IO.Path.Combine(result.BackupFolder, "RESTORE.txt"),`
- Test: tests/uninstall.ps1:87
- Confidence: alta

**U-91**
- Statement: A eliminação é `reg.exe delete "<chave>" [/v "<valor>"] /f /reg:32|64`: com `ValueName` apaga-se só esse valor, nunca a chave.
- Source: UH:706
- Snippet: `(item.ValueName == null ? "" : " /v " + QuoteArgument(item.ValueName)) + " /f /reg:"`
- Test: tests/uninstall.ps1:86 (valor irmão preservado)
- Confidence: alta

**U-92**
- Statement: A eliminação no registo só pede elevação (`runas`) para itens HKLM; exit ≠ 0 é falha "cancelled or failed; backup is available".
- Source: UH:708-709
- Snippet: `if (item.Machine) delete.Verb = "runas";`
- Test: sem teste (fixtures HKCU)
- Confidence: alta

**U-93**
- Statement: Depois de apagar, reabre-se a chave: se a chave (ou o valor, na eliminação de valor) ainda existir, o item falha como não verificado.
- Source: UH:710-712
- Snippet: `remaining.GetValueNames().Contains(item.ValueName, StringComparer.OrdinalIgnoreCase)`
- Test: tests/uninstall.ps1:82-83
- Confidence: alta

**U-94**
- Statement: Cada item é isolado: uma falha dá "Cancelled" (Win32 1223) ou "Failed" a esse item e a limpeza continua com os seguintes.
- Source: UH:717
- Snippet: `((Win32Exception)e).NativeErrorCode == 1223 ? "Cancelled" : "Failed"; outcome.Message = e.Message;`
- Test: tests/uninstall.ps1:72-73 (todos bloqueados, nenhum Success)
- Confidence: alta

### I. UI (fila, revisão, consentimento, histórico)

**U-95**
- Statement: Só pode correr uma operação de remoção/scan/limpeza/inventário de cada vez; iniciar outra lança erro.
- Source: VX:1094 (bloqueio de controlos em VX:1096)
- Snippet: `if ($script:uninstallTask) { throw 'A removal operation is already running.' }`
- Test: VX:1784 (smoke embutido); tests/uninstall-queue.ps1:22
- Confidence: alta

**U-96**
- Statement: O plano de remoção inclui apenas apps do inventário actual que estejam seleccionadas, com `CanRemove`, e cujo estado na fila não seja 'Success'.
- Source: VX:1381
- Snippet: `Where-Object { $_.Selected -and $_.CanRemove -and $script:uninstallStates[$_.Id] -ne 'Success' }`
- Test: tests/uninstall-queue.ps1:45
- Confidence: alta

**U-97**
- Statement: A remoção só arranca se o diálogo de revisão for aprovado.
- Source: VX:1382
- Snippet: `if ($plan.Count -gt 0 -and (Show-RemovalReview $plan)) { Start-UninstallQueue $plan }`
- Test: VX:1825 (smoke embutido)
- Confidence: alta

**U-98**
- Statement: No diálogo de revisão o botão de acção nasce desactivado e só é activado com a caixa de consentimento marcada e, para resíduos, com pelo menos um item seleccionado.
- Source: VX:1242 (VX:1193, VX:1236-1237, VX:1243)
- Snippet: `$go.IsEnabled=(-not $Leftovers -or @($Items | Where-Object Selected).Count -gt 0)`
- Test: VX:1246-1260 (smoke embutido); tests/cleanup-ui.ps1:16 e :36
- Confidence: alta

**U-99**
- Statement: "Select linked paths" marca apenas itens com Confidence 'Linked path'; os itens são postos a `Selected=$false` ao abrir o diálogo (VX:1235).
- Source: VX:1212
- Snippet: `$row.Child.IsChecked=$row.Child.Tag.Confidence -eq 'Linked path'`
- Test: tests/cleanup-ui.ps1:16
- Confidence: alta

**U-100**
- Statement: A limpeza só é chamada com os itens que o utilizador seleccionou no diálogo aprovado, e só se forem > 0.
- Source: VX:1324-1326
- Snippet: `Set-UninstallTask ([OneInstallUninstall]::CleanAsync($chosen)) 'Clean'`
- Test: VX:1843 (smoke embutido: sem consentimento não arranca)
- Confidence: alta

**U-101**
- Statement: O botão Stop limita-se a activar a flag e desactivar-se; fechar a janela durante uma operação é cancelado e activa a mesma flag.
- Source: VX:1384 e VX:1393-1396
- Snippet: `$eventArgs.Cancel=$true; [OneInstallUninstall]::StopRequested=$true`
- Test: sem teste da UI (a flag: tests/uninstall-process.ps1:68-69)
- Confidence: alta

**U-102**
- Statement: Se uma app com estado 'Success' reaparecer num inventário posterior, o estado é rebaixado para 'Manual action required'.
- Source: VX:1292
- Snippet: `{ Set-UninstallStage $app.Id 'Manual action required' }`
- Test: sem teste
- Confidence: alta

**U-103**
- Statement: Se a tarefa de remoção falhar, as apps ainda em Queued/Preparing/Removing/Verifying passam a 'Unknown' (nunca a sucesso) e a UI é desbloqueada.
- Source: VX:1343
- Snippet: `{ Set-UninstallStage $app.Id 'Unknown' } }`
- Test: tests/uninstall-queue.ps1:68-70
- Confidence: alta

**U-104**
- Statement: O resumo só diz 'Cleanup complete' se nenhum item falhou; caso contrário 'Cleanup needs attention'.
- Source: VX:1335
- Snippet: `$(if ($failed -eq 0) { 'Cleanup complete' } else { 'Cleanup needs attention' })`
- Test: tests/cleanup-ui.ps1:62-65
- Confidence: alta

**U-105**
- Statement: Remoções e limpezas são registadas no histórico de operações com acção, Id, origem 'Windows registration', nome, resultado, mensagem, exit code e caminho do log — sem Kind nem Path do resíduo.
- Source: VX:1301 e VX:1306 (VX:1312 para verificação tardia)
- Snippet: `[OneInstallPackages]::Record('Cleanup',$item.Id,'Windows registration',$item.Name,$item.Outcome,`
- Test: sem teste
- Confidence: média (o lado `Record` pertence a outro ficheiro; só li `src/package-helper.cs:223-240`)

**U-106**
- Statement: A página de histórico mostra no máximo os últimos 100 registos e só oferece "Open detailed log" se o ficheiro existir e o caminho resolvido estiver dentro de `$logDir`.
- Source: MU:191 (limite em MU:177)
- Snippet: `.StartsWith([IO.Path]::GetFullPath($logDir)+'\',[StringComparison]::OrdinalIgnoreCase)`
- Test: sem teste
- Confidence: alta

**U-107**
- Statement: Não se pode navegar para a página de histórico (nem mudar de modo) enquanto houver instalação ou operação de remoção em curso.
- Source: MU:153 (igual em VX:1136)
- Snippet: `if ($script:busy -or $script:uninstallTask) { return }`
- Test: sem teste
- Confidence: alta

---

## Lista 1 — Comportamentos que parecem acidentais, inconsistentes ou bugs (não copiar às cegas)

1. **Descendentes elevados provavelmente falham.** `child.StartTime`/`child.Handle` (UH:297, UH:302) lançam `Win32Exception` (acesso negado) para processos elevados quando o 1nstall corre `asInvoker` (`src/app.manifest:5`); os catch em UH:305-306 só apanham `ArgumentException`/`InvalidOperationException`, pelo que a excepção sobe até UH:369 e dá "Failed". Não testado (fixtures só HKCU). Não confirmei por execução.
2. **Sem timeout** na espera pelo desinstalador (UH:274-312) nem em `reg.exe` (UH:704, UH:709): um descendente que nunca saia (updater, serviço, browser aberto pelo desinstalador) bloqueia a fila, e a janela não fecha (VX:1393-1396).
3. `StopRequested` não é lido por `ScanAsync`/`CleanAsync`, embora fechar a janela o active (VX:1395): fechar durante a limpeza não pára os itens restantes.
4. Só conta o exit code do processo raiz (UH:357); 1602/1223/3010 devolvidos por um descendente são ignorados. Um cancelamento num bootstrapper aparece como "Manual action required" (fixado em tests/uninstall-process.ps1:72).
5. Com 3010/1641 não se verifica o registo (UH:358): fica "Restart required" mesmo que a app já tenha saído; `RestartRequestedAt` nunca é limpo, a porta depende de relógio de parede ±2 min (UH:103-104), logo um acerto de hora > 2 min abre-a.
6. Filtros Store inconsistentes: inventário exclui `IsResourcePackage` (UH:178), remoção não (UH:338).
7. `WindowsInstaller`=1 com subchave não-GUID torna a app não removível mesmo com `UninstallString` válido (UH:222-225). `msiexec` não está na lista de bloqueio (UH:245), logo uma entrada não-MSI com `"…\msiexec.exe" /I{GUID}` é executada tal e qual; `MsiExec.exe /X{…}` sem caminho é recusado como "missing" (UH:244).
8. Regex sem aspas (UH:240) pára no primeiro `.exe` seguido de espaço e não tenta candidatos mais longos; mesma ambiguidade de caminhos sem aspas do CreateProcess.
9. No ramo com aspas, executável e argumentos vêm de dois parsers diferentes (UH:231-235) que podem discordar em entradas malformadas.
10. `Names` corta tudo a partir do primeiro token numérico (UH:385): "Foo 2 Bar" vira "Foo", alargando o nome usado para igualar pastas/chaves. A lista de termos genéricos (UH:380) é só inglesa.
11. A Location de recurso vem de `DisplayIcon` ou da pasta do desinstalador (UH:158-160) e é tratada como "Recorded installation folder"/"Linked path" (UH:479-482) — pode ser `Package Cache\{GUID}` ou uma raiz de fabricante. A protecção de raiz de fabricante depende só de o token do Publisher conter o nome da pasta (UH:393).
12. Pastas pessoais com nomes fixos (UH:410): `OneDrive - <Org>`, Downloads relocalizado, Saved Games, Favorites, etc. não estão cobertos.
13. `path.Length < 8` (UH:404) é um número mágico sem justificação no código.
14. Se o inventário Store falhar, as apps Store ficam fora de `active` e o scan/limpeza de apps desktop prossegue (UH:606, UH:672); na limpeza a lista Store nunca é refrescada por item (UH:686).
15. Uma excepção em `MeasureFolder` (ex.: acesso negado) dentro de `AddFolder` aborta a enumeração das pastas irmãs desse nível (UH:570 → catch UH:577).
16. `seen` é verificado depois de medir (UH:478-480): pastas duplicadas são medidas duas vezes e podem contar duas verificações incompletas.
17. O teste de "export vazio" é só `< 10 bytes` (UH:704); um .reg só com cabeçalho passaria. Para eliminação de um valor exporta-se a chave de rasto inteira (ex.: UserAssist) — privacidade e restauro mais largo do que o apagado.
18. Histórico de remoções: escrita não atómica (UH:206), ficheiro corrompido/grande é tratado como vazio e depois sobrescrito (UH:198-206), em contraste com `src/package-helper.cs:231-235`. As flags de verificação são lidas de um JSON editável pelo utilizador e voltam a ser confiadas (VX:1015, VX:1309). Sem lock entre chamadas a `Remember`.
19. Cada scan percorre todas as entradas do histórico (até 100), não só a fila actual (VX:1309-1310): custo elevado e resíduos antigos reoferecidos sempre.
20. Um pedido UAC por cada item HKLM (UH:708) e potencialmente por cada pasta protegida; sem agrupamento.
21. `ScanAsync` tem efeitos laterais: marca `RemovalVerified` e grava histórico (UH:621-623).
22. Chaves de registo são apagadas (subárvore inteira, incl. HKLM) só por igualdade de nome, sem exigir `OwnershipVerified` (UH:484-492, UH:699).
23. Janela TOCTOU entre a validação (UH:691) e a reciclagem (UH:692): o caminho é passado como string.
24. `items.json` serializa o `Owner` completo (Command, caminhos) (UH:676); não vi nenhum código que apague pastas de backup antigas.
25. "Success" quando o registo já estava ausente (UH:344) não fez nada e nunca permite limpeza; a UI trata-o como sucesso normal.

## Lista 2 — Dependências de comportamento Windows/.NET/PowerShell que o Rust não dá de graça

1. `Guid.TryParse` aceita vários formatos (com/sem chavetas, 32 hex, parênteses) — UH:225.
2. `CommandLineToArgvW` para argv[0] — UH:231; `QuoteArgument` assume as regras de parsing do CRT — UH:210-219.
3. `Environment.ExpandEnvironmentVariables` — UH:228, UH:377; `RegistryKey.GetValue` expande `REG_EXPAND_SZ` por omissão e `Convert.ToString` converte DWORD — UH:99-100.
4. `Path.GetFullPath` (resolve `..`, pontos/espaços finais; lança em caminhos inválidos, o que alimenta os `catch { return false; }`) — UH:377; `Path.IsPathRooted` aceita `C:foo` e `\foo` — UH:244, UH:547. `std::fs::canonicalize` não é equivalente (resolve links, prefixo `\\?\`).
5. `Environment.GetFolderPath(SpecialFolder.*)` respeita redireccionamento e devolve "" se indisponível; em UH:408 isso faz `Full("")` lançar e `SafeDirectory` devolver false para tudo (fail-closed implícito).
6. `RegistryKey.OpenBaseKey(…, RegistryView)` (KEY_WOW64_32KEY/64KEY) — UH:138, UH:252, UH:495, UH:641, UH:710.
7. `Process.Start` com `UseShellExecute`+`Verb="runas"` (ShellExecuteEx; `Win32Exception` 1223 no cancelamento; pode devolver null) — UH:349-355, UH:707-709.
8. `Process.StartTime/ExitTime/HasExited/Handle/ExitCode` e retenção de handle pelo objecto — UH:296-303, UH:310, UH:357; layout de `PROCESSENTRY32W` — UH:256-261.
9. `GetTickCount64` + relógio de parede para BootTime — UH:102-103.
10. `FileAttributes.ReparsePoint` cobre junctions, symlinks e também placeholders de nuvem/AppExecLinks — UH:427, UH:446, UH:567; enumeração lazy `Directory.EnumerateFileSystemEntries` — UH:443.
11. COM `IFileOperation` em thread STA, `SHCreateItemFromParsingName` — UH:724-763; `SHLoadIndirectString` — UH:114; `SHGetKnownFolderPath` — UH:528.
12. `JavaScriptSerializer`: `[ScriptIgnore]`, `MaxJsonLength = 4194304`, serializa getters (`Detail`) e campos públicos — UH:98, UH:198, UH:206, UH:676.
13. Regex .NET com `\p{L}\p{N}`, `RegexOptions.IgnoreCase` e `ToLowerInvariant` — UH:379-386, UH:486; ordenação `CurrentCultureIgnoreCase` — UH:192.
14. Módulo Appx do PowerShell 5.1 (`Get-AppxPackage`, `Get-AppxPackageManifest`, `Remove-AppxPackage`) via `powershell.exe` — UH:178, UH:338.
15. `reg.exe export/delete` com `/reg:32|64` e formato .reg — UH:702, UH:706.
16. `volatile bool` + `ConcurrentQueue` lidos por `DispatcherTimer` de 200 ms e diálogo modal WPF `ShowDialog` — UH:93-96, VX:1017-1018, VX:1271-1279.
17. Bitness do processo: num processo 32 bits `ProgramFiles` == `ProgramFilesX86`, o que muda raízes e protecções — UH:411, UH:415, UH:466-467.

## Lista 3 — O que não consegui determinar pelo código

1. **Âmbito:** a fila, o diálogo de revisão e a confirmação de limpeza não estão em `src/manager-ui.ps1` (que só tem a página de histórico e guardas, MU:152-197) mas em `vexan_installers.ps1:1005-1399`; li essas linhas e as do smoke embutido (VX:1778-1848), não o resto do ficheiro.
2. Se `IFileOperation` com RECYCLEONDELETE + NOCONFIRMATION elimina permanentemente quando o item não cabe na Reciclagem ou o volume não a tem (discos amovíveis locais não são bloqueados); o código só verifica que a pasta desapareceu (UH:756), não que está na Reciclagem.
3. O comportamento real do seguimento de processos com descendentes elevados (Lista 1, ponto 1) — análise estática apenas.
4. Se o 1nstall corre elevado na prática e com que bitness (dependem de `src/launcher.cs`/`startup.cs`, fora do meu âmbito; o manifesto diz `asInvoker`).
5. O que `OneInstallPackages.Record/History/Diagnostics` persistem ou expõem para além do que li em `src/package-helper.cs:223-240`, e o que vai para `$logPath` (as mensagens com caminhos são escritas no log em VX:1022 e VX:1299).
6. Se existe retenção/limpeza das pastas em `1nstall\Backups` (não há nos ficheiros lidos).
7. Se o CI executa `tests/uninstall.ps1` e `tests/uninstall-process.ps1` (ambos exigem `-DisposableEnvironment`; não li `.github/workflows/windows.yml`).
8. `tests/process-fixture.cs` não exercita o helper de desinstalação (só é referenciado por `tests/reliability.ps1:31`), pelo que o mapeamento 3010/1641/1223 da remoção não tem teste.