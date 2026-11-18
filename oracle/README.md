# Oracle: recorded behaviour of the 3.6 engine

This folder records what the 3.6 engine actually does, so that a rewrite can be compared against it instead of against anyone's memory of it. Nothing here changes the app.

## What is recorded

| Layer | What | Where it runs | Output |
| --- | --- | --- | --- |
| Pure functions | 1,552 inputs through 23 engine functions: package ID validation, WinGet command line, exit-code mapping, export and setup parsing, redaction, uninstall-command parsing, name normalisation, registry-leftover rules | Any Windows machine; nothing is written outside the output file | `golden/v3.6.0/pure.jsonl` (committed) |
| Removal scenarios | Remove, scan and clean on eight fixture apps, with registry and file state before and after each step, the backup folder and the removal history file | Disposable machines only (CI runners, VMs) | `golden/v3.6.0/removal.jsonl` (committed) |
| Machine observations | The existing native removal tests, how 3.6 reads the machine's real uninstall registrations, and real WinGet installs | Disposable machines only | Workflow artifact `oracle-observations-<os>` |

The first two layers are golden files: CI regenerates them on clean runners and fails if a single byte differs. The third is an observation: runner images change, so it is compared between implementations within the same run, not against a stored file.

`reference/winget-errors.json` holds the official names of the WinGet error codes, taken from `AppInstallerErrors.h`.

## Removal scenarios

Each scenario registers a fixture app under `HKCU` with a stand-in uninstaller, then runs the real 3.6 calls: `Inventory`, `RemoveAsync`, `ScanAsync`, `CleanAsync`.

| Scenario | Stand-in uninstaller | Recorded 3.6 outcome |
| --- | --- | --- |
| Alpha | Succeeds, leaves a program file, user data, a product key and a trace value | Success; 4 leftovers offered and cleaned |
| Bravo | Exits 1602 | Cancelled |
| Charlie | Exits 0 but the registration stays | Manual action required |
| Delta | Exits 3010 | Restart required; scan withheld |
| Echo | Launcher exits at once, a child finishes 1.5 s later | Success after waiting for the child |
| Foxtrot | Exits 1603 | Failed |
| Golf | Succeeds; the registration has no `InstallLocation` | Success; the uninstaller's own folder is offered as the installation folder |
| Hotel | The uninstall command is `cmd.exe` | Refused; Failed |

Paths are recorded as `{LOCALAPPDATA}`, `{APPDATA}` and `{USERPROFILE}`; backup folder stamps and GUID file names as `{STAMP}` and `{GUID}`.

## Files

- `corpus/pure.json` - the inputs. Implementation-neutral; a second driver can read the same file.
- `drivers/v36-pure.ps1` - evaluates the corpus with the C# helpers in `src/`.
- `golden/v3.6.0/pure.jsonl` - one JSON object per case: `{"fn", "args", "out"}` or `{"fn", "args", "err": {"type", "message"}}`.
- `observe-machine.ps1` - the machine layer. Refuses to run without `-DisposableEnvironment`.
- `lib/json.ps1` - canonical JSON writer (ASCII-only, fixed key order).

## Run

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File oracle\drivers\v36-pure.ps1 -Out oracle\golden\v3.6.0\pure.jsonl
git diff --exit-code -- oracle/golden
```

A clean diff means this machine reproduces the recorded behaviour.

## Corpus format

Each entry names a function and lists `cases`; each case is the argument list. `ranges` adds one case per integer between two hexadecimal bounds, used to enumerate the whole WinGet HRESULT range `0x8A150000`-`0x8A1501FF`.

Long inputs use generators, and the golden file records the generator rather than its expansion:

| Generator | Result |
| --- | --- |
| `{"$gen": "repeat", "unit": "A", "count": 200, "suffix": ""}` | `unit` repeated `count` times, then `suffix` |
| `{"$gen": "join", "prefix": "\"k", "suffix": "\"", "count": 3, "sep": ","}` | `"k0","k1","k2"` |
| `{"$gen": "concat", "parts": [...]}` | the parts, expanded and concatenated |

## Conventions that make the golden file portable

- Culture is fixed to `en-US`. `Uninstall.FormatBytes@pt-PT` exists to pin the one function that formats numbers with the current culture.
- The System32 directory is written as `{SYSTEM32}` in `Uninstall.GetCommand` results.
- Strings are escaped to ASCII, so the file does not depend on editor or Git encoding settings.
- Private helpers are reached through reflection, and arguments are passed as real nulls.

## Adding cases

Add the case to `corpus/pure.json`, run the driver, review the new lines in the diff and commit both files together. A changed existing line means the engine's behaviour changed.
