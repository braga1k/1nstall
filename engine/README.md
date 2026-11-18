# Engine (4.0, work in progress)

The 1nstall engine rewritten in Rust. It has no user interface. The 3.6 application at the repository root is untouched and remains the shipped product.

## Layout

| Crate | Purpose |
| --- | --- |
| `core` (`oneinstall-core`) | The rules: package identity, the WinGet command line, exit-code mapping, export and setup parsing, redaction, uninstall-command parsing, name normalisation and leftover ownership. No I/O; everything machine-dependent goes through the `Host` trait. |
| `platform` (`oneinstall-platform`) | The Windows implementation of `Host` and of the engine's machine operations. |

## How correctness is checked

`platform/tests/oracle_pure.rs` runs every case of `oracle/corpus/pure.json` through the Rust rules and compares the result with what 3.6 produced (`oracle/golden/v3.6.0/pure.jsonl`).

A case may differ from 3.6 only in a declared way:

- **null input** - 3.6 was given a null that the Rust signature cannot express;
- **json syntax** - both reject text that is not JSON, with different wording;
- **listed divergence** - an entry in `oracle-divergences.json`, with its reason. The test fails if a listed case stops differing or differs in another way.

```bash
cargo test -- --nocapture
```

The summary line reads, for example: `oracle pure: 1552 cases; identical 1532; null input 9; json syntax 5; listed divergences 6; unexplained 0`.

## Toolchain

Rust 1.86. CI pins that version; `cargo fmt --check` and `cargo clippy -- -D warnings` must pass.
