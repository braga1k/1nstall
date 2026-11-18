# Fase 0 — Contratos de dados (1nstall 3.6.0)

Origem: tag `v3.6.0`, commit `80e584f`. Os valores abaixo foram medidos nos próprios ficheiros, não copiados dos docs.

Este documento cobre os dados que a app **traz consigo**. Os ficheiros que a app **escreve em runtime** (definições, histórico, backups, logs) e o contrato de rede do updater estão em [invariantes/updater-e-arranque.md](invariantes/updater-e-arranque.md), Parte B. Os formatos de seleção guardada (v1 e v2) estão em [invariantes/instalacao.md](invariantes/instalacao.md), I-68 a I-84.

## Regras comuns aos três JSON

| Propriedade | Valor medido | Implicação para a 4.0 |
| --- | --- | --- |
| Codificação | UTF-8 sem BOM | Vários ficheiros de runtime escritos pela 3.6 **têm** BOM (`operations.json`, logs, seleções guardadas) e outros não (`uninstall-history.json`); o leitor tem de aceitar ambos. |
| Fins de linha | CRLF | O ZIP de código-fonte preserva os bytes exatos; não normalizar. |
| Embutidos no exe | Sim, por substituição de marcadores `@@...@@` no build | A validação de esquema só corre com `-SelfTest` (I-04); em arranque normal os dados são aceites tal como estão. |

## `catalog.json` — 270 667 bytes

Raiz: array de 325 objetos. 277 automáticos (WinGet) e 48 guiados (URL).

### Campos sempre presentes (325/325)

| Campo | Tipo | Regra observada |
| --- | --- | --- |
| `Key` | string | Único. Caracteres `[a-z0-9_-]`, máximo 34. Quatro chaves têm hífen (`winutil_claude-code`, `winutil_es-de`, `winutil_mpc-qt`, `winutil_pdf-xchange`). |
| `Name` | string | Único. |
| `Category` | string | Um de 24 valores (lista em `docs/catalog/CATEGORY-TAXONOMY.json`). |
| `CategoryGroup` | string | `Everyday`, `Create`, `Files & Storage`, `PC & Tools`. |
| `AlsoIn` | string[] | 0 a 2 categorias, sem repetir `Category`. |
| `Description` | string | Não vazio. |
| `Ids` | string[] | 0 a 12 IDs WinGet. Cada um casa com `[A-Za-z0-9][A-Za-z0-9.+_-]*`. Únicos em todo o catálogo, sem distinguir maiúsculas. |
| `Url` | string | `""` ou `https://…`. |
| `Requires` | string[] | 0 ou 1 chaves de catálogo. Só existe um caso: `peace` requer `apo`. |
| `Icon` | string | `""` ou 2 letras. |
| `OpenSource` | bool ou null | null em 47 entradas. |
| `LicenseLabel` | string | `Open source`, `Proprietary`, `Open core`, `Check license` ou `""`. |
| `GitHubStars` | number ou null | Preenchido em 20 entradas. |
| `StarsCheckedOn` | string ou null | Data ISO, nas mesmas 20. |

**Invariante central:** exatamente um de `Ids` e `Url` está preenchido (`tests/catalog.py:24`).

### Campos opcionais (proveniência)

| Campo | Presente em | Tipo |
| --- | --- | --- |
| `Website`, `CatalogSource`, `VerifiedOn` | 284 | string |
| `ManifestUrl`, `License`, `VerifiedVersion` | 283 | string |
| `Verification` | 225 | string (texto livre, 10 valores distintos) |
| `WinUtilKey`, `WinUtilId` | 152 | string |
| `WinUtilKeys` | 80 | string[] (1 a 2) |
| `Repository` | 59 | string `dono/repo` |
| `Publisher`, `PublisherEvidence`, `PublisherVerifiedOn` | 5 | string |

Os objetos têm entre 14 e 25 chaves. Um leitor em Rust tem de tratar todos os campos opcionais como ausentes **ou** presentes, e `OpenSource`/`GitHubStars`/`StarsCheckedOn` como anuláveis.

### Casos que só existem uma vez

- **Multi-ID:** só o VCRedist (12 IDs). A fila pára no primeiro ID sem `Success` (I-35) e este caminho não tem teste.
- **Dependência:** só `peace → apo`. A ordenação de dependências está testada com dados fictícios, não com este par.
- **Origem `msstore`:** nenhum ID do catálogo é da Store. A fila instala sempre com origem literal `winget` (I-18).

## `profiles.json` — 9 655 bytes

Raiz: array de 20 objetos, todos com exatamente 5 campos.

| Campo | Tipo | Regra observada |
| --- | --- | --- |
| `Key` | string | Único, 2 a 16 caracteres. |
| `Name` | string | Não vazio. |
| `Group` | string | `Everyday & Work`, `Create`, `Files & Privacy`, `PC & Tools`. |
| `Description` | string | Não vazio. |
| `Apps` | string[] | 8 a 11 chaves de catálogo, sem repetição, todas existentes. |

**Atenção:** os grupos dos perfis (`Everyday & Work`, `Files & Privacy`) não são os grupos de categorias do catálogo (`Everyday`, `Files & Storage`). São duas enumerações diferentes com dois valores em comum.

Os docs prometem que as chaves de perfil existentes e os ficheiros guardados se mantêm compatíveis; a 4.0 herda essa promessa.

## `locales.json` — 1 099 432 bytes

Raiz: objeto com 51 idiomas. Cada idioma tem exatamente `Name` (string), `Rtl` (bool) e `Strings` (objeto com 239 entradas).

- **A chave de cada string é o texto inglês.** `Strings["Check now"]` devolve a tradução. Não há identificadores estáveis: mudar uma frase inglesa muda a chave em 51 idiomas.
- O idioma `en` existe como pacote próprio, com as mesmas 239 chaves.
- **RTL:** `ar` e `ur`.
- **Marcadores:** só `{0}` a `{3}`, em 13 chaves. O conjunto de marcadores de cada tradução tem de ser igual ao da chave (`tests/locales.py`).
- Português existe apenas como `pt-PT`.
- Lista de idiomas, pela ordem do ficheiro: `en zh-Hans hi es ar fr bn pt-PT id ur de it nl da sv nb nn fi is ga mt el pl cs sk hu ro bg hr sl et lv lt sq bs sr sr-Latn sr-Latn-ME rm lb ca be uk ru tr ka hy az kk mk ja`.

**Risco para a reescrita:** os estados internos (`Success`, `Failed`, `Installed ·`, `Queued`) são comparados como literais ingleses no código (I-45, I-46, I-57). Não ficou confirmado que a tradução nunca toca nesses valores antes da comparação. Na 4.0 os estados devem ser um `enum`, e o texto só deve existir na camada de apresentação.

## Dados de apoio que os testes exigem

`tests/catalog.py` cruza o catálogo com cinco ficheiros em `docs/catalog/` (taxonomia, auditoria de categorias, cobertura, auditoria de uso diário, resumo). Se a 4.0 mantiver `catalog.json` no mesmo formato, este teste corre sem alterações e continua a servir de juiz.

## Artefactos publicados na release 3.6.0

Tamanhos lidos da API do GitHub, sem descarregar nada.

| Ficheiro | Bytes |
| --- | --- |
| `1nstall.exe` | 2 699 264 |
| `1nstall-3.6.0-Windows-x64.zip` | 795 623 |
| `1nstall-3.6.0-source.zip` | 1 919 441 |
| `BUILD-INFO.json` | 3 088 |
| `SHA256SUMS.txt` | 862 |
| `THIRD-PARTY-NOTICES.txt` | 12 553 |
| `CI-catalog.txt`, `CI-locales.txt`, `CI-reliability.txt`, `CI-elastic-motion.txt`, `self-test.log` | 138 a 296 cada |

SHA-256 do `1nstall.exe` publicado: `90428e1ea21db5f5b939aab920db3309a457fc4bd4ac116641fb1754feb8508c`.
