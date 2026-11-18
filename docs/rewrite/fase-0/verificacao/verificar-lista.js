// Independent citation check: node verify.js <repoRoot> <dataFile> <mapJson>
// dataFile rows: KEY@@@line@@@verbatim snippet. Reports rows whose snippet is not a literal substring of that line.
const fs = require('fs'), path = require('path');
const [root, dataFile, mapJson] = process.argv.slice(2);
const map = JSON.parse(mapJson);
const cache = {};
const lines = k => cache[k] ??= fs.readFileSync(path.join(root, map[k] || k), 'utf8').replace(/^﻿/, '').split(/\r?\n/);
let n = 0, bad = 0, near = 0;
for (const row of fs.readFileSync(dataFile, 'utf8').replace(/^﻿/, '').split(/\r?\n/)) {
  if (!row.trim()) continue;
  const i = row.indexOf('@@@'), j = row.indexOf('@@@', i + 3);
  if (i < 0 || j < 0) { console.log('UNPARSED ' + row.slice(0, 80)); bad++; continue; }
  const key = row.slice(0, i), ln = Number(row.slice(i + 3, j)), snip = row.slice(j + 3);
  n++;
  let L;
  try { L = lines(key); } catch (e) { console.log(`NOFILE ${key}`); bad++; continue; }
  if ((L[ln - 1] || '').includes(snip)) continue;
  const hit = L.findIndex(x => x.includes(snip));
  if (hit >= 0) { near++; console.log(`MOVED ${key}:${ln} -> actually line ${hit + 1} :: ${snip.slice(0, 70)}`); }
  else { bad++; console.log(`FAIL ${key}:${ln} not found anywhere :: ${snip.slice(0, 90)}`); }
}
console.log(`checked=${n} exact=${n - bad - near} wrong_line=${near} not_found=${bad}`);
