# 1nstall v3.6.0 — fatia SELF-UPDATE / LAUNCHER / SETTINGS / DISCO (extraído do código, tag v3.6.0, commit 80e584f)

Todos os snippets da Parte A foram verificados por pesquisa literal na linha citada (229 verificações, 0 falhas). Nada foi executado, compilado ou alterado no repositório.

**Achado que condiciona a v4.0:** a 3.6 só aceita um `1nstall.exe` que seja um assembly .NET com nome `1nstall` e versão igual à tag (S-17). Pela leitura do código, um PE nativo Rust publicado com esse nome é rejeitado por todas as 3.6 instaladas; não foi executado para confirmar.

## PARTE A — Invariantes

### Auto-update: descoberta e download
- **S-01** — A única chamada de descoberta é `GET https://api.github.com/repos/braga1k/1nstall/releases/latest`, com resposta limitada a 1 048 576 bytes. Fonte: src/update-helper.cs:62. Snippet: `Download("https://api.github.com/repos/braga1k/1nstall/releases/latest",1048576)`. Teste: sem teste. Confiança: alta.
- **S-02** — Todos os pedidos HTTP (API, checksums, exe) enviam `User-Agent: 1nstall-updater` e `Accept: application/vnd.github+json`, sem autenticação. Fonte: src/update-helper.cs:29. Snippet: `request.UserAgent="1nstall-updater"; request.Accept="application/vnd.github+json";`. Teste: sem teste. Confiança: alta.
- **S-03** — Timeout de ligação e de leitura/escrita de 20 000 ms cada. Fonte: src/update-helper.cs:30. Snippet: `request.Timeout=20000; request.ReadWriteTimeout=20000;`. Teste: sem teste. Confiança: alta.
- **S-04** — O URI final (após redireccionamentos) tem de ter esquema `https`, senão falha com "HTTPS required.". Fonte: src/update-helper.cs:32. Snippet: `if(response.ResponseUri.Scheme!="https") throw new IOException("HTTPS required.");`. Teste: sem teste. Confiança: alta.
- **S-05** — O tamanho é limitado por Content-Length e por contagem em streaming (buffer de 65 536). Fonte: src/update-helper.cs:37. Snippet: `if(output.Length+count>limit) throw new IOException("Download too large.");`. Teste: sem teste. Confiança: alta.
- **S-06** — TLS 1.2 é acrescentado (OR) aos protocolos por omissão; não há pinning nem callback de certificado. Fonte: src/update-helper.cs:60. Snippet: `ServicePointManager.SecurityProtocol|=SecurityProtocolType.Tls12;`. Teste: sem teste. Confiança: alta.
- **S-07** — A release é ignorada (sem erro) se `draft` ou `prerelease` forem true, ou se a tag não for mais nova. Fonte: src/update-helper.cs:64. Snippet: `if((bool)release["draft"] || (bool)release["prerelease"] || !IsNewer(tag,current)) return result;`. Teste: sem teste. Confiança: alta.
- **S-08** — A tag tem de casar com `^v?\d+\.\d+\.\d+$`; sufixos como `-beta` são rejeitados. Fonte: src/update-helper.cs:46. Snippet: `return Regex.IsMatch(tag??"",@"^v?\d+\.\d+\.\d+$") &&`. Teste: tests/manager-ui.ps1:406. Confiança: alta.
- **S-09** — Protecção contra downgrade: só actualiza se a tag for estritamente maior que Major.Minor.Build da versão actual (Revision ignorada). Fonte: src/update-helper.cs:48. Snippet: `next>new Version(installed.Major,installed.Minor,Math.Max(0,installed.Build));`. Teste: tests/manager-ui.ps1:406. Confiança: alta.
- **S-10** — A "versão actual" é o literal `'3.6.0'` no script (não a versão do assembly); raiz `%LOCALAPPDATA%\1nstall\Updates`; `download=$true` sempre. Fonte: src/settings.ps1:213. Snippet: `$script:updateTask=[OneInstallUpdate]::CheckAsync('3.6.0',$script:updateRoot,$true)`. Teste: sem teste. Confiança: alta.
- **S-11** — O binário é o asset cujo `name` é exactamente `1nstall.exe` (comparação ordinal); a sua ausência é erro. Fonte: src/update-helper.cs:67. Snippet: `if(Convert.ToString(asset["name"])=="1nstall.exe") executable=asset;`. Teste: sem teste. Confiança: alta.
- **S-12** — O ficheiro de checksums é o asset com `name` exactamente `SHA256SUMS.txt`. Fonte: src/update-helper.cs:68. Snippet: `if(Convert.ToString(asset["name"])=="SHA256SUMS.txt") checksums=asset;`. Teste: sem teste. Confiança: alta.
- **S-13** — O `browser_download_url` (exe e checksums) tem de começar por `https://github.com/braga1k/1nstall/releases/download/<tag escapada>/`. Fonte: src/update-helper.cs:52. Snippet: `if(!url.StartsWith(Repository+Uri.EscapeDataString(tag)+"/",StringComparison.Ordinal))`. Teste: sem teste. Confiança: alta.
- **S-14** — Fonte primária do hash: campo `digest` do asset na API, se casar com `^sha256:[a-fA-F0-9]{64}$`. Fonte: src/update-helper.cs:74. Snippet: `if(Regex.IsMatch(digest,@"^sha256:[a-fA-F0-9]{64}$")) result.Hash=digest.Substring(7)`. Teste: sem teste. Confiança: alta.
- **S-15** — Fallback sem `digest` válido: descarrega `SHA256SUMS.txt` (máx. 65 536 bytes) e usa a primeira linha `<64 hex><espaços/tabs>[*]1nstall.exe`; sem ficheiro ou sem linha é erro. Fonte: src/update-helper.cs:78. Snippet: `var match=Regex.Match(sums,@"(?m)^([a-fA-F0-9]{64})[ \t]+\*?1nstall\.exe\r?$");`. Teste: sem teste. Confiança: alta.
- **S-16** — O exe (máx. 104 857 600 bytes) vai para `Updates\<versão>\1nstall.exe.<guid32>.tmp`; só é promovido se o SHA-256 (hex minúsculo) for igual ao esperado; uma cópia em cache com hash certo evita novo download. Fonte: src/update-helper.cs:87. Snippet: `if(HashFile(temporary)!=result.Hash) throw new IOException("Checksum mismatch.");`. Teste: sem teste. Confiança: alta.
- **S-17** — Depois do hash, o ficheiro tem de ser um assembly .NET legível por `AssemblyName.GetAssemblyName`, com nome `1nstall` e Major.Minor.Build igual à tag; senão `Path=null` e erro. Fonte: src/update-helper.cs:90. Snippet: `var identity=AssemblyName.GetAssemblyName(path);`. (condição em :91: `if(identity.Name!="1nstall" || new Version(identity.Version.Major,identity.Version.Minor,`). Teste: sem teste. Confiança: alta (leitura); efeito num PE nativo não executado.
- **S-18** — Qualquer excepção no check/download é engolida para `result.Error`; a UI mostra só uma mensagem genérica. Fonte: src/update-helper.cs:93. Snippet: `catch(Exception error) { result.Path=null; result.Error=error.Message; }`. Teste: sem teste. Confiança: alta.

### Auto-update: quando e como se aplica
- **S-19** — A verificação automática corre no primeiro `ContentRendered` se `AutoUpdate` e fora de modo de teste; também em "Check now" e ao ligar a checkbox. Fonte: src/settings.ps1:312. Snippet: `if ($script:settings.AutoUpdate -and -not $script:settingsTest) { Start-AppUpdateCheck }`. Teste: sem teste. Confiança: alta.
- **S-20** — Não há verificação em modo de teste nem com uma já em curso. Fonte: src/settings.ps1:205. Snippet: `if ($script:settingsTest -or $script:updateTask) { return }`. Teste: sem teste. Confiança: alta.
- **S-21** — Sem a variável `AppExecutable` (execução como .ps1) a actualização fica desactivada. Fonte: src/settings.ps1:206. Snippet: `if (-not (Test-Path variable:AppExecutable)) {`. Teste: sem teste. Confiança: alta.
- **S-22** — A aplicação só é agendada no `Closed` da janela, se houver release pendente e (`AutoUpdate` ou "Restart and update"), fora de teste e com `AppExecutable`. Fonte: src/settings.ps1:315. Snippet: `if ($script:pendingRelease -and ($script:settings.AutoUpdate -or $script:restartAfterUpdate)`. Teste: sem teste. Confiança: alta.
- **S-23** — O fecho da janela é cancelado durante a fila de instalação (vexan_installers.ps1:998) e durante remoção/scan (:1395), logo o update nunca se aplica a meio. Fonte: vexan_installers.ps1:1395. Snippet: `$eventArgs.Cancel=$true; [OneInstallUninstall]::StopRequested=$true`. Teste: sem teste. Confiança: média (li só estes dois handlers de Closing).
- **S-24** — `Schedule` volta a verificar o hash do ficheiro em staging antes de lançar o worker. Fonte: src/update-helper.cs:110. Snippet: `HashFile(release.Path)!=release.Hash) throw new IOException("No verified update is ready.");`. Teste: sem teste. Confiança: alta.
- **S-25** — O worker é uma cópia do exe em execução (o antigo) para `Updates\<versão>\apply-<guid32>.exe`. Fonte: src/update-helper.cs:111. Snippet: `"apply-"+Guid.NewGuid().ToString("N")+".exe");`. Teste: sem teste. Confiança: alta.
- **S-26** — Linha de comando do worker: `--apply-update <pid> <b64 utf8 destino> <b64 utf8 origem> <sha256 novo> <sha256 antigo> <1|0>`, sem janela. Fonte: src/update-helper.cs:113. Snippet: `"--apply-update "+Process.GetCurrentProcess().Id+" "+Encode(target)+" "+Encode(release.Path)+" "`. Teste: sem teste. Confiança: alta.
- **S-27** — `Apply` exige exactamente 7 argumentos. Fonte: src/update-helper.cs:120. Snippet: `if(args.Length!=7) throw new ArgumentException("Invalid update arguments.");`. Teste: sem teste. Confiança: alta.
- **S-28** — `Apply` exige a origem dentro de `%LOCALAPPDATA%\1nstall\Updates\`, os dois hashes em `^[a-f0-9]{64}$`, e o SHA-256 do próprio worker igual ao hash "antigo". Fonte: src/update-helper.cs:124. Snippet: `HashFile(Process.GetCurrentProcess().MainModule.FileName)!=args[5]) throw new IOException(`. Teste: sem teste. Confiança: alta.
- **S-29** — O worker espera até 60 000 ms pela saída do processo pai; se não sair, devolve 1 sem escrever log; PID inexistente é aceite. Fonte: src/update-helper.cs:125. Snippet: `if(!parent.WaitForExit(60000)) return 1; } } catch(ArgumentException) { }`. Teste: sem teste. Confiança: alta.
- **S-30** — A substituição é tentada até 10 vezes com 1 000 ms de pausa em qualquer `IOException`. Fonte: src/update-helper.cs:128. Snippet: `catch(IOException) { if(attempt==9) throw; Thread.Sleep(1000); }`. Teste: sem teste. Confiança: alta.
- **S-31** — Antes de substituir, origem e destino são re-hashados contra os valores esperados; um update corrompido não toca no destino. Fonte: src/update-helper.cs:99. Snippet: `if(HashFile(source)!=expected || HashFile(target)!=original) throw new IOException(`. Teste: tests/manager-ui.ps1:411-412. Confiança: alta.
- **S-32** — A origem é copiada para `<destino>.<guid32>.update` na pasta do destino, re-verificada e só depois trocada. Fonte: src/update-helper.cs:100. Snippet: `string pending=target+"."+Guid.NewGuid().ToString("N")+".update";`. Teste: sem teste. Confiança: alta.
- **S-33** — A troca é `File.Replace` com backup `<destino>.previous` (ex.: `1nstall.exe.previous`); nenhum código o lê ou apaga. Fonte: src/update-helper.cs:104. Snippet: `File.Replace(pending,target,target+".previous",true);`. Teste: tests/manager-ui.ps1:413-414. Confiança: alta.
- **S-34** — Em sucesso apaga `update-error.log` e, se o último argumento for `"1"`, relança o destino sem argumentos via ShellExecute. Fonte: src/update-helper.cs:132. Snippet: `if(args[6]=="1") Process.Start(new ProcessStartInfo(target) { UseShellExecute=true });`. Teste: sem teste. Confiança: alta.
- **S-35** — Qualquer excepção em `Apply` escreve `error.ToString()` em `%LOCALAPPDATA%\1nstall\update-error.log` e devolve 1. Fonte: src/update-helper.cs:135. Snippet: `"1nstall","update-error.log"),error.ToString()); } catch { }`. Teste: sem teste. Confiança: alta.
- **S-36** — Se `Schedule` falhar no fecho, grava só `Exception.Message` no mesmo `update-error.log`. Fonte: src/settings.ps1:317. Snippet: `(Join-Path $env:LOCALAPPDATA '1nstall\update-error.log'),$_.Exception.Message)`. Teste: sem teste. Confiança: alta.
- **S-37** — Não há verificação prévia de "pasta gravável" ou "a correr de temp": a existência de `update-error.log` no arranque só muda o texto de estado. Fonte: src/settings.ps1:202. Snippet: `'The previous update could not be applied. Move 1nstall to a writable folder and try again.'`. Teste: sem teste. Confiança: alta.
- **S-38** — O resultado da tarefa é sondado por um DispatcherTimer de 1 s. Fonte: src/settings.ps1:299. Snippet: `$script:updateTimer.Interval=[TimeSpan]::FromSeconds(1)`. Teste: sem teste. Confiança: alta.

### Launcher / arranque
- **S-39** — O exe não pede elevação (`asInvoker`, `uiAccess=false`). Fonte: src/app.manifest:5. Snippet: `<requestedExecutionLevel level="asInvoker" uiAccess="false"/>`. Teste: sem teste. Confiança: alta.
- **S-40** — O manifesto declara apenas o GUID de compatibilidade Windows 10/11 e identidade `1nstall.Desktop` amd64 3.6.0.0. Fonte: src/app.manifest:6. Snippet: `<supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>`. Teste: sem teste. Confiança: alta.
- **S-41** — `--apply-update` como primeiro argumento é tratado antes de tudo: carrega `1nstall.Helpers.dll` da cache e invoca `OneInstallUpdate.Apply`; qualquer excepção dá código 1. Fonte: src/launcher.cs:72. Snippet: `return (int)assembly.GetType("OneInstallUpdate").GetMethod("Apply").Invoke(null,new object[]{args});`. Teste: sem teste. Confiança: alta.
- **S-42** — Fora disso só são aceites zero argumentos ou um de `--smoke-test`, `--self-test`, `--manager-test`, `--startup-test`; o resto é "Unknown argument." (código 1). Fonte: src/launcher.cs:94. Snippet: `if(args.Length>0 && !test) throw new ArgumentException("Unknown argument.");`. Teste: sem teste. Confiança: alta.
- **S-43** — Os scripts PowerShell nunca vão para disco: o recurso `1nstall.Payload` é lido para memória e partido no marcador `# UI starts here`; sem marcador, erro. Fonte: src/launcher.cs:99. Snippet: `int split=source.IndexOf("# UI starts here",StringComparison.Ordinal);`. Teste: sem teste. Confiança: alta.
- **S-44** — Só dois DLL embutidos (`1nstall.Helpers`, `1nstall.UI`) são extraídos, para `%LOCALAPPDATA%\1nstall\Runtime\<sha256>\<nome>.dll` (em teste: `<pasta do exe>\runtime-cache\...`). Fonte: src/launcher.cs:43. Snippet: `Environment.SpecialFolder.LocalApplicationData),"1nstall","Runtime");`. Teste: sem teste. Confiança: alta.
- **S-45** — Integridade da extracção: o ficheiro em cache só é reutilizado se o seu SHA-256 for igual ao do recurso; senão é reescrito via `.tmp` + Replace/Move. Fonte: src/launcher.cs:47. Snippet: `if(File.Exists(path) && Hash(File.ReadAllBytes(path))==hash) return path;`. Teste: sem teste. Confiança: alta.
- **S-46** — O PowerShell corre in-process (sem `powershell.exe`, logo sem `-NoProfile`/`-ExecutionPolicy`), com `InitialSessionState.CreateDefault2()`. Fonte: src/launcher.cs:103. Snippet: `var state=InitialSessionState.CreateDefault2();`. Teste: sem teste. Confiança: alta.
- **S-47** — O runspace é STA e `UseCurrentThread`; a 1.ª metade do payload corre numa Task e a 2.ª na thread principal `[STAThread]`. Fonte: src/launcher.cs:105. Snippet: `session.ApartmentState=ApartmentState.STA;`. Teste: sem teste. Confiança: alta.
- **S-48** — A 1.ª metade recebe `-ResourceRoot <%TEMP%\1nstall-<guid32>>` e, em teste, um de `-SmokeTest`/`-ManagerTest`/`-SelfTest`/`-StartupTest`. Fonte: src/launcher.cs:111. Snippet: `ps.AddScript(source.Substring(0,split),false).AddParameter("ResourceRoot",folder);`. Teste: sem teste. Confiança: alta.
- **S-49** — `%TEMP%\1nstall-<guid32>` é criada em cada arranque e apagada recursivamente no `finally`; no exe empacotado fica vazia (só `test-logs` em smoke/manager-test). Fonte: src/launcher.cs:89. Snippet: `string folder=Path.Combine(Path.GetTempPath(),"1nstall-"+Guid.NewGuid().ToString("N"));`. Teste: sem teste. Confiança: alta.
- **S-50** — O launcher injecta `NativeWindow`, `AppExecutable` (caminho do exe) e `StartupClock` antes da 2.ª metade. Fonte: src/launcher.cs:132. Snippet: `runspace.SessionStateProxy.SetVariable("AppExecutable",Assembly.GetExecutingAssembly().Location);`. Teste: sem teste. Confiança: alta.
- **S-51** — Erro de arranque: `error.ToString()` sobrescreve `%TEMP%\1nstall-startup-error.log` (em teste: `<pasta do exe>\...`), MessageBox fora de teste, código 1. Fonte: src/launcher.cs:149. Snippet: `test?AppDomain.CurrentDomain.BaseDirectory:Path.GetTempPath(),"1nstall-startup-error.log");`. Teste: tests/startup.ps1:10. Confiança: alta.
- **S-52** — Em teste, o output do script vai para `<pasta do exe>\<switch sem "--">.log`. Fonte: src/launcher.cs:144. Snippet: `Path.Combine(AppDomain.CurrentDomain.BaseDirectory,args[0].Substring(2)+".log"),output.ToString());`. Teste: .github/workflows/windows.yml:42-44. Confiança: alta.
- **S-53** — `--startup-test` exige `window.Tag` do tipo long e escreve `READY <ms>`, `FirstFrameMs`, `BeforeShowMs`, `LoadedMs`, `RenderMs`. Fonte: src/launcher.cs:138. Snippet: `if(!(window.Tag is long)) throw new Exception("Window did not reach the ready checkpoint.");`. Teste: tests/startup.ps1:11-14. Confiança: alta.
- **S-54** — A janela de abertura só existe sem argumentos ou com `--startup-test`. Fonte: src/launcher.cs:82. Snippet: `(args.Length==0 || args.Length==1 && args[0]=="--startup-test")?new StartupView():null`. Teste: tests/startup-opening.ps1:27-33. Confiança: alta.
- **S-55** — Fechar a abertura antes do handoff cancela o arranque e o processo sai com 0. Fonte: src/launcher.cs:129. Snippet: `if(opening!=null && opening.Cancelled) return 0;`. Teste: tests/startup-opening.ps1:57. Confiança: alta.
- **S-56** — A abertura corre numa thread STA de fundo com Dispatcher próprio (nome "1nstall opening"), sem segundo processo; falhas são engolidas. Fonte: src/startup.cs:34. Snippet: `thread=new Thread(Show) { IsBackground=true,Name="1nstall opening" };`. Teste: tests/startup-opening.ps1:31-32. Confiança: alta.
- **S-57** — A abertura não cria entrada na barra de tarefas. Fonte: src/startup.cs:52. Snippet: `WindowStyle=WindowStyle.None,ResizeMode=ResizeMode.NoResize,ShowInTaskbar=false`. Teste: tests/startup-opening.ps1:34. Confiança: alta.
- **S-58** — O launcher activa multicore-JIT com perfil `startup.profile` na raiz Runtime (ou `runtime-cache`); erros de IO são ignorados. Fonte: src/launcher.cs:80. Snippet: `System.Runtime.ProfileOptimization.StartProfile("startup.profile");`. Teste: sem teste. Confiança: alta.
- **S-59** — Em modo script exige-se Windows 64-bit (:130) e thread STA (:131); o atalho usa `powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File`. Fonte: script_allower.cmd:2. Snippet: `powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0vexan_installers.ps1"`. Teste: sem teste. Confiança: alta.
- **S-60** — Não existe instância única: nenhum Mutex, EventWaitHandle, pipe ou FindWindow em `vexan_installers.ps1`, `src/*`, `tests/*`, `interface.xaml`. Fonte: ausência (grep). Snippet: n/a. Teste: sem teste. Confiança: alta.

### Settings
- **S-61** — Valores por omissão: `Theme='System'`, `WindowsAccent=$true`, `Language='System'`, `AutoUpdate=$true`. Fonte: src/settings.ps1:7. Snippet: `$script:settings=@{Theme='System'; WindowsAccent=$true; Language='System'; AutoUpdate=$true}`. Teste: sem teste. Confiança: alta.
- **S-62** — Caminho: `%LOCALAPPDATA%\1nstall\settings.json` (via variável de ambiente). Fonte: src/settings.ps1:8. Snippet: `$script:settingsPath=Join-Path $env:LOCALAPPDATA '1nstall\settings.json'`. Teste: sem teste. Confiança: alta.
- **S-63** — Em modo de teste o ficheiro não é lido nem escrito, e força-se `Language='en'`, `Theme='Dark'`, `AutoUpdate=$false`. Fonte: src/settings.ps1:10. Snippet: `$script:settings.Language='en'; $script:settings.Theme='Dark'; $script:settings.AutoUpdate=$false`. Teste: sem teste. Confiança: alta.
- **S-64** — O ficheiro só é lido se tiver ≤ 8 192 bytes; ausente, maior ou JSON inválido dá defaults em silêncio (try em :12, `catch { }` em :24), sem o reescrever. Fonte: src/settings.ps1:13. Snippet: `if ((Get-Item -LiteralPath $script:settingsPath).Length -le 8192) {`. Teste: sem teste. Confiança: alta.
- **S-65** — Validação por chave: `Theme` ∈ {System, Light, Dark}; valor inválido mantém o default; chaves desconhecidas são ignoradas. Fonte: src/settings.ps1:17. Snippet: `if ($property.Value -in @('System','Light','Dark')) { $script:settings.Theme=$property.Value }`. Teste: sem teste. Confiança: alta.
- **S-66** — `Language` tem de ser `'System'` ou uma chave de `locales.json`. Fonte: src/settings.ps1:18. Snippet: `$script:locales.PSObject.Properties.Name -contains $property.Value) { $script:settings.Language=`. Teste: sem teste. Confiança: alta.
- **S-67** — `WindowsAccent` e `AutoUpdate` só são aceites se forem booleanos JSON. Fonte: src/settings.ps1:19. Snippet: `if ($property.Value -is [bool]) { $script:settings.WindowsAccent=$property.Value }`. Teste: sem teste. Confiança: alta.
- **S-68** — Gravação atómica: `settings.json.<guid32>.tmp` em UTF-8 sem BOM, depois `File.Replace` (sem backup) ou `Move`; o tmp é apagado no `finally`; só persistem as 4 chaves conhecidas. Fonte: src/settings.ps1:31. Snippet: `($script:settings | ConvertTo-Json),[Text.UTF8Encoding]::new($false))`. Teste: tests/manager-ui.ps1:399-403. Confiança: alta.
- **S-69** — Falha de gravação não lança: mostra texto de estado e devolve `$false`. Fonte: src/settings.ps1:36. Snippet: `'Could not save settings. Check folder permissions.'`. Teste: sem teste. Confiança: alta.
- **S-70** — `Language='System'`: `pt*`→`pt-PT`, `zh*`→`zh-Hans`, `no`→`nb`, `cnr`→`sr-Latn-ME`; depois corta sufixos até encontrar locale; fallback `en`. Fonte: src/settings.ps1:43. Snippet: `if ($code.StartsWith('pt')) { return 'pt-PT' }`. Teste: tests/reliability.ps1:22-26. Confiança: alta.
- **S-71** — `Theme='System'` lê `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme` (≠0 = claro; erro = escuro). Fonte: src/settings.ps1:127. Snippet: `'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme`. Teste: sem teste. Confiança: alta.
- **S-72** — A abertura lê o mesmo `settings.json` em C# (≤ 8 192 bytes; só `Theme` string e `WindowsAccent` bool), comparando `"Light"`/`"Dark"` com distinção de maiúsculas. Fonte: src/appearance.cs:39. Snippet: `theme=="Light" || theme!="Dark" && key!=null && object.Equals(key.GetValue("AppsUseLightTheme"),1);`. Teste: sem teste. Confiança: alta.
- **S-73** — `preferences.json` guarda só `View` ∈ {`All apps`, `Installed`}; lido se ≤ 4 096 bytes e fora de SmokeTest; inválido dá `All apps`. Fonte: src/manager-ui.ps1:137. Snippet: `if ($prefs.View -in @('All apps','Installed')) { $script:libraryView=$prefs.View }`. Teste: sem teste. Confiança: alta.

### Outros dados em disco
- **S-74** — `operations.json` é reescrito atomicamente (tmp + Replace/Move) com no máximo as últimas 500 entradas. Fonte: src/package-helper.cs:234. Snippet: `Json().Serialize(rows.Skip(Math.Max(0, rows.Count - 500)).ToList()), Encoding.UTF8);`. Teste: sem teste. Confiança: alta.
- **S-75** — Histórico corrompido, > 4 194 304 bytes, ou com linha nula ou sem `Timestamp`/`Action`/`Outcome` nunca é sobrescrito: `Record` recusa gravar. Fonte: src/package-helper.cs:231. Snippet: `if (HistoryError != null) throw new IOException(HistoryError + " Existing history was preserved.");`. Teste: tests/reliability.ps1:121-124. Confiança: alta.
- **S-76** — `uninstall-history.json` guarda no máximo 100 `InstalledApp`, deduplicados por `Id`, com escrita não atómica. Fonte: src/uninstall-helper.cs:206. Snippet: `Json().Serialize(history.Skip(Math.Max(0, history.Count - 100)).ToList()));`. Teste: sem teste (tests/uninstall-process.ps1:38,76-77 só salvaguarda o ficheiro real). Confiança: alta.
- **S-77** — `uninstall-history.json` > 1 048 576 bytes ou ilegível é tratado como vazio em silêncio e sobrescrito na remoção seguinte. Fonte: src/uninstall-helper.cs:198. Snippet: `if (new FileInfo(HistoryFile).Length > 1048576) return new List<InstalledApp>();`. Teste: sem teste. Confiança: alta.
- **S-78** — Cada limpeza cria `%LOCALAPPDATA%\1nstall\Backups\<yyyyMMdd-HHmmss>-<8 hex>\`. Fonte: src/uninstall-helper.cs:674. Snippet: `@"1nstall\Backups", DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N")`. Teste: tests/uninstall.ps1:113-114. Confiança: alta.
- **S-79** — Uma chave/valor de registo só é apagada depois de `reg.exe export` para `<guid32>.reg` com código 0 e ≥ 10 bytes. Fonte: src/uninstall-helper.cs:704. Snippet: `new FileInfo(backup).Length < 10) throw new IOException("Registry backup failed; key was kept.");`. Teste: tests/uninstall.ps1:84-92. Confiança: alta.
- **S-80** — Log de sessão: `%LOCALAPPDATA%\1nstall\Logs\session-<yyyyMMdd-HHmmss>-<PID>.log`. Fonte: vexan_installers.ps1:350. Snippet: `$logPath = Join-Path $logDir ('session-{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$PID)`. Teste: sem teste. Confiança: alta.
- **S-81** — Cada instalação winget grava stdout+stderr em `<Logs>\<guid32>.log`. Fonte: src/package-helper.cs:264. Snippet: `log = Path.Combine(logs, Guid.NewGuid().ToString("N") + ".log");`. Teste: tests/reliability.ps1:72-76 (indirecto). Confiança: alta.
- **S-82** — "Open detailed log" só aparece se `LogPath` existir e estiver dentro de `$logDir`. Fonte: src/manager-ui.ps1:191. Snippet: `[IO.Path]::GetFullPath($record.LogPath).StartsWith([IO.Path]::GetFullPath($logDir)+'\'`. Teste: sem teste. Confiança: alta.
- **S-83** — Ficheiros de setup: máx. 65 536 bytes; `Version` inteiro 1 ou 2; nenhuma chave extra (v2 exige `Kind="1nstall-selection"`); `Apps` com 1–500 itens. Fonte: src/package-helper.cs:306. Snippet: `if (version != 1 && version != 2) throw new IOException("Unsupported setup version.");`. Teste: tests/reliability.ps1:113-117. Confiança: alta.
- **S-84** — Em v2 cada app tem exactamente `Id`, `Source`, `Name`, `Version` (strings); `Source` ∈ {winget, msstore}; `Name` ≤ 200, `Version` ≤ 100; sem caracteres de controlo; `Source:Id` único. Fonte: src/package-helper.cs:323. Snippet: `fields.Keys.Any(k => k != "Id" && k != "Source" && k != "Name" && k != "Version")`. Teste: tests/reliability.ps1:115. Confiança: alta.

### Build / release (lado produtor)
- **S-85** — O exe é um assembly .NET x64 `winexe` com recursos `1nstall.Payload`, `1nstall.Symbol`, `1nstall.Catalog`, `1nstall.Helpers`, `1nstall.UI`. Fonte: build-windows.ps1:40. Snippet: `"/resource:$payload,1nstall.Payload" "/resource:$dist\symbol.xaml,1nstall.Symbol"`. Teste: .github/workflows/windows.yml:42-43. Confiança: alta.
- **S-86** — `SHA256SUMS.txt` tem linhas `<hex minúsculo><2 espaços><nome>`, UTF-8 sem BOM, ordenadas por nome na release. Fonte: scripts/package-release.ps1:47. Snippet: `(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$_.Name`. Teste: .github/workflows/windows.yml:76. Confiança: alta.
- **S-87** — A versão de release tem de casar com `^\d+\.\d+\.\d+$`. Fonte: scripts/package-release.ps1:8. Snippet: `if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid release version in build metadata.' }`. Teste: sem teste. Confiança: alta.
- **S-88** — O CI só publica a partir de push para `refs/heads/release/3.6.0`. Fonte: .github/workflows/windows.yml:54. Snippet: `if: github.event_name == 'push' && github.ref == 'refs/heads/release/3.6.0'`. Teste: n/a. Confiança: alta.
- **S-89** — Antes de publicar, o CI compara os `digest` devolvidos pela API com os SHA-256 locais e só então marca `--latest`. Fonte: .github/workflows/windows.yml:117. Snippet: `assert actual == expected, 'Uploaded release assets differ from verified build'`. Teste: n/a. Confiança: alta.
- **S-90** — A assinatura Authenticode é opcional e exige timestamp HTTPS; o updater não verifica assinatura nenhuma. Fonte: build-windows.ps1:44. Snippet: `throw 'An HTTPS timestamp server is required for signing.'`. Teste: sem teste. Confiança: alta.

Os asserts de update e settings em tests/manager-ui.ps1 só correm embutidos via `--manager-test` (build-windows.ps1:22; vexan_installers.ps1:1423-1428); o CI só executa `--self-test`.

## PARTE B — Contratos

### B1. Ficheiros em runtime
Raiz de estado: `%LOCALAPPDATA%\1nstall\`. O PowerShell usa `$env:LOCALAPPDATA`; o C# usa `Environment.GetFolderPath(LocalApplicationData)`.

| Caminho | Escreve | Lê | Formato e campos |
|---|---|---|---|
| `settings.json` | src/settings.ps1:26-39 | src/settings.ps1:13-22; src/appearance.cs:30-35 (só Theme, WindowsAccent) | JSON, UTF-8 sem BOM, ≤ 8 192 bytes. `Theme`: "System"/"Light"/"Dark"; `WindowsAccent`: bool; `Language`: "System" ou chave de locales.json; `AutoUpdate`: bool. Chaves extra ignoradas e perdidas na gravação seguinte. |
| `settings.json.<guid32>.tmp` | src/settings.ps1:28-33 | — | Transitório. |
| `preferences.json` | src/manager-ui.ps1:13 (não atómico, `Set-Content -Encoding UTF8`, BOM no PS 5.1) | src/manager-ui.ps1:135-137 | `{ "View": "All apps" ou "Installed" }`, ≤ 4 096 bytes. |
| `operations.json` (+ `.<guid32>.tmp`) | src/package-helper.cs:223-240 | src/package-helper.cs:241-256; src/manager-ui.ps1:177; src/package-helper.cs:293 | Array JSON (UTF-8 com BOM), máx. 500, leitura ≤ 4 194 304 bytes. Campos (:33-45): `Timestamp` (DateTimeOffset "o"), `Action` ("Install"/"Remove"/"Cleanup"), `Id`, `Source` ("winget"/"catalog"/"guided"/"Windows registration"), `Name`, `Outcome`, `Message`, `LogPath` (string ou null), `ExitCode` (int), `Detail` (só de leitura; presumo serializado). Obrigatórios não vazios: Timestamp, Action, Outcome. |
| `uninstall-history.json` (identidades de remoção) | src/uninstall-helper.cs:201-207 | src/uninstall-helper.cs:196-200; vexan_installers.ps1:1015, 1309 | Array JSON (UTF-8 sem BOM), máx. 100, leitura ≤ 1 048 576 bytes. `InstalledApp` (:21-45): strings `Id, Name, Publisher, Version, Kind, Location, Command, RegistryPath, PackageFamily`; bools `Machine, View32, Msi, RemovalVerified, OwnershipVerified, IdentityVerified, CanRemove`; longs `RestartRequestedAt` (ticks), `SizeKB`; `Detail` derivado; `Selected` excluído. |
| `Backups\<yyyyMMdd-HHmmss>-<8hex>\items.json` | src/uninstall-helper.cs:676 | ninguém (Explorer: vexan_installers.ps1:1389-1391) | Array de `LeftoverItem` (:46-62): `AppName, Kind` ("Folder"/"Registry"), `Path, ValueName, DisplayValueName, Reason, Confidence`; `Owner` (InstalledApp completo); bools `Machine, View32, Selected`; `Bytes` long; `Files` int; `Detail`. |
| `Backups\...\<guid32>.reg` | src/uninstall-helper.cs:701-704 (`reg.exe export <HKLM ou HKCU>\<path> <ficheiro> /y /reg:32 ou 64`) | ninguém; restauro manual | Formato do reg.exe. Um por item de registo. |
| `Backups\...\RESTORE.txt` | src/uninstall-helper.cs:705 (append) | ninguém | Blocos: `<chave> (32-bit ou 64-bit)`, `To restore from Command Prompt[ as administrator]:`, `reg.exe import "<.reg>" /reg:<32 ou 64>`, linha vazia. |
| `Backups\...\results.json` | src/uninstall-helper.cs:719 | ninguém | Array de `RemovalOutcome` (:78-87): `Id, Name, Outcome, Message, ExitCode` (int), `Kind, Path`. |
| `Logs\session-<yyyyMMdd-HHmmss>-<PID>.log` | vexan_installers.ps1:357, 1022 | ninguém (Explorer :768) | Texto UTF-8. Linhas `[yyyy-MM-dd HH:mm:ss] msg` (:354) e `[HH:mm:ss] msg` (:1020). Sem rotação. |
| `Logs\<guid32>.log` | src/package-helper.cs:264-266 | notepad via src/manager-ui.ps1:191-193 | stdout + CRLF + stderr do winget, UTF-8 com BOM. |
| `Runtime\<sha256>\1nstall.Helpers.dll`, `Runtime\<sha256>\1nstall.UI.dll` | src/launcher.cs:36-58 | `Assembly.LoadFrom` (:64, 71, 108, 120) | Assemblies .NET. Revisões antigas nunca removidas (:41-42). |
| `Runtime\startup.profile` | CLR (src/launcher.cs:79-80) | CLR | Perfil multicore-JIT, opaco. |
| `Updates\<versão>\1nstall.exe` (+ `.<guid32>.tmp`) | src/update-helper.cs:82-88 | src/update-helper.cs:84, 90, 110, 122 | Binário verificado; nunca apagado. |
| `Updates\<versão>\apply-<guid32>.exe` | src/update-helper.cs:111-112 | executado em :115 | Cópia do exe antigo; nunca apagada. |
| `<pasta do exe>\<exe>.<guid32>.update` | src/update-helper.cs:100-102 | :103-104 | Transitório. |
| `<exe>.previous` | src/update-helper.cs:104 | ninguém | Rollback manual. |
| `update-error.log` | src/update-helper.cs:135; src/settings.ps1:317 | existência: src/settings.ps1:202; apagado em src/update-helper.cs:130-131 | Texto livre. |
| `%TEMP%\1nstall-startup-error.log` (teste: `<pasta do exe>\`) | src/launcher.cs:149-150 | tests/startup.ps1:10 | `Exception.ToString()`, sobrescrito. |
| `%TEMP%\1nstall-<guid32>\` | src/launcher.cs:89, 95; apagada :157 | passada como `ResourceRoot` (:111) | Vazia no exe; `test-logs\` em smoke-test (vexan_installers.ps1:348). |
| `%TEMP%\1nstall-inventory-<guid32>.json` | winget export (src/package-helper.cs:159-162) | :164; apagado :169 | Export do WinGet, ≤ 4 194 304 bytes. |
| `%TEMP%\1nstall-check-<guid32>\Sample Editor\fixture.txt` | src/uninstall-helper.cs:787-791 (só SelfTest) | — | Apagado :796. |
| `<pasta do exe>\{self-test,smoke-test,manager-test,startup-test}.log` | src/launcher.cs:144 | windows.yml:44; tests/startup.ps1:11-13; scripts/package-release.ps1:18 | Output do script. |
| `<pasta do exe>\runtime-cache\` | src/launcher.cs:43, 77 | idem | Cache e perfil em modo de teste. |
| Diagnóstico (caminho do utilizador; nome proposto `1nstall-diagnostics.txt`) | src/manager-ui.ps1:201 | — | Texto UTF-8 com BOM: cabeçalho, versão do Windows, últimas 100 operações redigidas (src/package-helper.cs:279-294). |
| Perfil v1 (nome proposto `my-setup.json`) | vexan_installers.ps1:756-758, 771 | src/package-helper.cs:295-330 via src/manager-ui.ps1:223-224 | `{"Version":1,"Apps":["<chave de catálogo>",…]}`; chaves `^[A-Za-z0-9][A-Za-z0-9.+_-]*$`, ≤ 200, únicas. |
| Snapshot v2 (nome proposto `installed-setup.json`) | src/package-helper.cs:331-338; src/manager-ui.ps1:256-257 | idem | `{"Version":2,"Kind":"1nstall-selection","Apps":[{"Id","Source","Name","Version"}]}`, ≤ 65 536 bytes, UTF-8 com BOM. |
| `dist\BUILD-INFO.json` (build; não lido pela app) | build-windows.ps1:69-77 | scripts/package-release.ps1:6-8, 12, 21, 37-40 | `Product, Version, BuiltAtUtc, UpstreamBase, SourceCommit, SourceDirty, Windows, PowerShell, Compiler, CompilerSHA256, Signed, ExeSHA256, Inputs{caminho→sha256}`. |

Em modo script há ainda leituras de `catalog.json`, `interface.xaml`, `profiles.json`, `locales.json` e fontes `.cs` a partir de `ResourceRoot` (vexan_installers.ps1:15-16, 31; src/settings.ps1:5), e PNG de teste com `-PreviewPath`. Não se aplicam ao exe.

### B2. Contrato de rede do updater
| Item | Valor | Fonte |
|---|---|---|
| Endpoint | `GET https://api.github.com/repos/braga1k/1nstall/releases/latest` | src/update-helper.cs:62 |
| Cabeçalhos | `User-Agent: 1nstall-updater`; `Accept: application/vnd.github+json`; sem token | :29 |
| Transporte | HttpWebRequest (redireccionamentos, proxy e validação de certificados por omissão do .NET); TLS 1.2 acrescentado; URI final https | :28-32, :60 |
| JSON da release | `tag_name` (string), `draft` (bool), `prerelease` (bool), `assets` (array); ≤ 1 048 576 bytes (inclui as notas) | :61-66 |
| JSON de cada asset | `name`, `browser_download_url`, `digest` opcional (`sha256:<64 hex>`) | :51, :67-68, :73-74 |
| Assets | `1nstall.exe` (≤ 104 857 600 bytes) e `SHA256SUMS.txt` (≤ 65 536 bytes; só usado sem `digest` válido) | :67-68, :76-77, :86 |
| URL dos assets | prefixo `https://github.com/braga1k/1nstall/releases/download/<EscapeDataString(tag)>/` | :22, :52 |
| Linha de checksum | `(?m)^([a-fA-F0-9]{64})[ \t]+\*?1nstall\.exe\r?$`; primeira ocorrência | :78 |
| Verificação | SHA-256 do ficheiro contra o hash acima; depois identidade de assembly .NET | :87, :90-91 |

**O que uma release v4.0 tem de publicar para uma 3.6 a aceitar e aplicar:**
1. Release no repositório `braga1k/1nstall`, não draft, não prerelease, devolvida por `/releases/latest`, com tag `v4.0.0` (ou `4.0.0`), três componentes numéricos, sem sufixo.
2. JSON da release abaixo de 1 MiB.
3. Asset chamado exactamente `1nstall.exe`, ≤ 100 MiB, servido sob o prefixo acima.
4. `digest` SHA-256 na API, ou asset `SHA256SUMS.txt` com a linha de `1nstall.exe`. Sem BOM: um BOM na primeira linha impede o `^` de casar se essa for a linha do exe (inferência da regex).
5. **O `1nstall.exe` tem de ser um assembly .NET com nome simples `1nstall` e AssemblyVersion `4.0.0.x`** (src/update-helper.cs:90-91). Um PE nativo fica em cache em `Updates\4.0.0\`, falha esta verificação em cada arranque e a 3.6 mostra "Could not check or download the update. Try again later." (src/settings.ps1:305). Para manter a cadeia é preciso um stub .NET com esse nome e versão, ou aceitar a quebra.
6. A substituição é feita pelo exe 3.6 antigo (worker), não pelo novo. O novo binário é copiado para o caminho do antigo (mesmo nome de ficheiro) e pode ser relançado sem argumentos.
7. No primeiro arranque a v4.0 encontra `<exe>.previous`, `Updates\<versão>\{1nstall.exe, apply-*.exe}`, `Runtime\<sha>\*.dll`, `Runtime\startup.profile` e possivelmente `update-error.log`; nada disto é limpo pela 3.6.
8. A 3.6 não verifica Authenticode, o campo `size`, `BUILD-INFO.json` nem o nome da release.

### B3. Switches e códigos de saída
| Linha de comando | Efeito | Fonte |
|---|---|---|
| (sem argumentos) | GUI com janela de abertura | src/launcher.cs:82, 85-146 |
| `--self-test` | Sem janela; `-SelfTest`; escreve `self-test.log` | src/launcher.cs:88, 101, 119, 144; vexan_installers.ps1:71-104 |
| `--smoke-test` | `-SmokeTest`; `smoke-test.log` | src/launcher.cs:88, 101; vexan_installers.ps1:1433-1883 |
| `--manager-test` | `-ManagerTest` (implica SmokeTest, vexan_installers.ps1:4); `manager-test.log` | src/launcher.cs:88, 101; vexan_installers.ps1:1423-1432 |
| `--startup-test` | `-StartupTest` com abertura; `startup-test.log` | src/launcher.cs:82, 88, 137-142; vexan_installers.ps1:1409-1422 |
| `--apply-update <pid> <b64 destino> <b64 origem> <sha novo> <sha antigo> <1 ou 0>` | Interno: aplica o update | src/launcher.cs:69-74; src/update-helper.cs:113, 117-138 |
| outro argumento, ou mais de um | "Unknown argument."; MessageBox e log em %TEMP% | src/launcher.cs:94, 147-152 |
| Só em modo script: `-CatalogOnly`, `-SelfTest`, `-SmokeTest`, `-ManagerTest`, `-PreviewPath`, `-StartupTest`, `-ResourceRoot` | — | vexan_installers.ps1:3 |

| Código | Significado | Fonte |
|---|---|---|
| 0 | Fecho normal ou teste com sucesso | src/launcher.cs:145 |
| 0 | Abertura fechada pelo utilizador | src/launcher.cs:129 |
| 0 | `--apply-update` com sucesso | src/update-helper.cs:133 |
| 1 | Qualquer excepção de arranque ou execução | src/launcher.cs:152 |
| 1 | `--apply-update`: pai não saiu em 60 s (sem log) | src/update-helper.cs:125 |
| 1 | `--apply-update`: validação ou substituição falhou (com log) | src/update-helper.cs:136 |
| 1 | `--apply-update`: falha ao carregar Helpers ou invocar | src/launcher.cs:73 |

### B4. Objectos nomeados do SO e registo
| Tipo | Valor | Fonte |
|---|---|---|
| Mutex, evento, pipe, semáforo | Nenhum | grep sem resultados |
| AppUserModelID, classe de janela própria | Nenhum | grep sem resultados |
| Título das janelas | `1nstall` | src/startup.cs:51 |
| Nome de thread | `1nstall opening` | src/startup.cs:34 |
| Identidades | assembly `1nstall` 3.6.0.0 (src/launcher.cs:16); manifesto `1nstall.Desktop` amd64 (src/app.manifest:3); DLL `1nstall.Helpers`, `1nstall.UI` | build-windows.ps1:27, 40; src/ui.csproj:2 |
| Recursos embutidos | `1nstall.Payload`, `1nstall.Symbol`, `1nstall.Catalog`, `1nstall.Helpers`, `1nstall.UI` | build-windows.ps1:40 |
| Registo, estado próprio | Nenhum valor escrito | grep sem CreateSubKey/SetValue de estado |
| Registo, leituras | `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme` | src/settings.ps1:127; src/appearance.cs:38-39 |
| Variáveis de ambiente | `LOCALAPPDATA` (src/settings.ps1:8, 202, 203, 317; vexan_installers.ps1:348, 1390); `OS` (vexan_installers.ps1:130); `PATH` (src/package-helper.cs:82); TEMP/TMP via `GetTempPath` | — |
| Processos filhos com flags de host | `powershell.exe -NoProfile -NonInteractive -EncodedCommand` (src/uninstall-helper.cs:122); `pwsh.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand` (src/package-helper.cs:141) | — |

## PARTE C

### C1. Comportamentos que parecem acidentais ou bugs
1. A porta de identidade .NET (src/update-helper.cs:90-91) torna o canal de update incompatível com qualquer binário não-.NET.
2. Falhas de integridade são `IOException` e por isso são repetidas 10 vezes com 1 s de pausa, como se fossem bloqueios de ficheiro (src/update-helper.cs:99, 128).
3. O timeout de 60 s à espera do pai devolve 1 sem escrever `update-error.log`: falha silenciosa (src/update-helper.cs:125).
4. Nada limpa `Updates\<versão>\1nstall.exe`, `apply-<guid>.exe` (um por tentativa), `<exe>.previous` nem `Runtime\<sha>\` antigos (src/update-helper.cs:111-112, 104; src/launcher.cs:41-42).
5. "Check now" com AutoUpdate desligado descarrega e anuncia "Update ready. It will be applied when you close 1nstall." (src/settings.ps1:306), mas o fecho só aplica com AutoUpdate ou "Restart and update" (:315).
6. O aviso de update falhado (src/settings.ps1:202) é logo substituído por "Checking for updates…" quando AutoUpdate está ligado (:211, :312).
7. `update-error.log` tem dois formatos (`Message` em src/settings.ps1:317, `ToString()` em src/update-helper.cs:135) e só é apagado por um apply bem-sucedido (:130-131).
8. O updateRoot vem de `$env:LOCALAPPDATA` (src/settings.ps1:203) mas `Apply` valida contra `GetFolderPath` (src/update-helper.cs:123); se divergirem, o apply falha com "Unexpected update source.".
9. A versão actual está em literais separados: src/settings.ps1:213 e :281, src/launcher.cs:16-17, src/app.manifest:3. O updater usa o literal do script.
10. `Theme` é validado sem distinção de maiúsculas em PowerShell (src/settings.ps1:17) e comparado com distinção em C# (src/appearance.cs:39): um "light" editado à mão dá abertura em modo sistema e app em modo claro.
11. Guardar settings descarta chaves desconhecidas (src/settings.ps1:15-21, 31), e um ficheiro > 8 192 bytes é ignorado e depois sobrescrito (:13). Risco se a v4.0 partilhar o ficheiro e o utilizador voltar à 3.6.
12. `uninstall-history.json` corrompido é sobrescrito em silêncio, tem escrita não atómica e ignora `DataRoot` (src/uninstall-helper.cs:97, 198-199, 206), ao contrário de `operations.json` (src/package-helper.cs:231).
13. `preferences.json` tem escrita não atómica e com BOM (src/manager-ui.ps1:13).
14. Há duas definições de "teste" no launcher: :76 (qualquer argumento único `--*`) e :88 (quatro switches). `1nstall.exe --foo` cria `runtime-cache\` junto ao exe e depois falha com log em %TEMP%.
15. A pasta `%TEMP%\1nstall-<guid>` é vestigial no exe (src/launcher.cs:89, 95, 157) e fica órfã se o processo for morto.
16. `$out`/`$err` em vexan_installers.ps1:872-873 são calculados e nunca usados.
17. O build embute o texto de `update-helper.cs` no payload (build-windows.ps1:20) apesar de já estar compilado no Helpers.dll (:27); os outros helpers são substituídos por `''`.
18. Sem instância única: duas instâncias podem agendar o mesmo update e escrever `operations.json` em simultâneo; o `HistoryGate` é só in-process (src/package-helper.cs:75).
19. `SecurityProtocol|=Tls12` só acrescenta; não desactiva protocolos antigos (src/update-helper.cs:60).
20. O cabeçalho `Accept` da API também segue no download do binário (src/update-helper.cs:29).
21. `Load-UserProfile` é definido duas vezes (vexan_installers.ps1:760 e src/manager-ui.ps1:223); vale a segunda.
22. A abertura engole todas as excepções (src/startup.cs:124).

### C2. Dependências de .NET / PowerShell / WPF que o Rust não dá de graça
- `AssemblyName.GetAssemblyName` como porta do update (src/update-helper.cs:90).
- `File.Replace` (troca com backup) em src/update-helper.cs:88, 104; src/settings.ps1:32; src/package-helper.cs:235; src/launcher.cs:51.
- PowerShell in-process: runspace STA, `AddScript`, variáveis injectadas, `Add-Type` (src/launcher.cs:102-136; vexan_installers.ps1:58-63).
- `JavaScriptSerializer`: parsing permissivo, `MaxJsonLength`, `RecursionLimit=20`, e `root["Version"] is int` (um `1.0` é rejeitado) (src/package-helper.cs:76, 304; src/update-helper.cs:61; src/appearance.cs:32).
- `ConvertFrom-Json`/`ConvertTo-Json` e operadores sem distinção de maiúsculas (`-in`, `-contains`), mais `-is [bool]` (src/settings.ps1:14-20, 31).
- Codificações: `Set-Content -Encoding UTF8` e `Encoding.UTF8` escrevem BOM; `File.ReadAllText` detecta-o. A v4.0 tem de tolerar BOM em `preferences.json`, `operations.json`, perfis v1/v2 e `BUILD-INFO.json` (src/manager-ui.ps1:13; src/package-helper.cs:234, 337; vexan_installers.ps1:758; build-windows.ps1:77).
- `HttpWebRequest`: redireccionamentos, proxy do sistema, SChannel e store de certificados (src/update-helper.cs:28-31).
- Semântica de `System.Version` (3 componentes, Revision −1) (src/update-helper.cs:47-48).
- `Process.GetProcessById`, `WaitForExit`, `MainModule.FileName` e ShellExecute para relançar (src/update-helper.cs:124-125, 132).
- `ProfileOptimization` (src/launcher.cs:79-80).
- `CultureInfo.CurrentUICulture` (src/settings.ps1:42).
- WPF: segundo Dispatcher para a abertura (src/startup.cs:37-39, 122), `WindowChrome` (:54-55), `XamlReader` do recurso `1nstall.Symbol` (:75-76), `SystemParameters` (:43, 95), handoff de owner/foreground (:126-143), `MessageBox` de erro (src/launcher.cs:151), diálogos de ficheiro (vexan_installers.ps1:770, 782).
- WinRT `UISettings` por reflexão e atributos DWM 2/20/33/34/38 (src/appearance.cs:43-49; src/window-helper.cs:30, 53-59).
- `reg.exe` para os backups `.reg` (src/uninstall-helper.cs:702).

### C3. Não determinável a partir do código
- O comportamento real de `GetAssemblyName` com um PE nativo (não executado; a conclusão vem da leitura).
- Se a API do GitHub devolve sempre `digest` e que release considera "latest"; limites de taxa não autenticados (o código só os veria como erro genérico).
- Forma exacta do JSON do `JavaScriptSerializer` (ordem dos campos; inclusão de `Detail`): confiança média.
- Ordem das chaves de `settings.json` (enumeração de hashtable).
- Codificação dos `.reg` e conteúdo de `startup.profile`.
- Se o `AddScript` in-process fica sujeito a ExecutionPolicy ou AppLocker/CLM numa máquina restrita.
- Resultado com o exe numa pasta só de leitura ou dentro de um ZIP: não há verificação explícita, só as falhas implícitas descritas.
- `src/ui-helper.cs` e `src/motion.cs` não foram lidos na íntegra; o grep não mostra IO de ficheiros nem registo.
- Se `--smoke-test` e `--manager-test` do exe são corridos nalgum pipeline.
- O conjunto exacto de assets da release v3.6.0 real (só o que `package-release.ps1:42-48` produz).
- A documentação não foi usada como fonte.
