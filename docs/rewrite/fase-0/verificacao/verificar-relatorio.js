// node verify-md.js <repoRoot> <report.md> <mapJson>
// Parses "**X-NN**" blocks with "Source:/Fonte:" and "Snippet(s):" lines; checks each backticked snippet
// is a literal substring of one of the cited lines (ranges honoured). Reports anything else.
const fs = require('fs'), path = require('path');
const [root, report, mapJson] = process.argv.slice(2);
const map = JSON.parse(mapJson);
const cache = {};
const lines = k => cache[k] ??= fs.readFileSync(path.join(root, map[k] || k), 'utf8').replace(/^﻿/, '').split(/\r?\n/);
const text = fs.readFileSync(report, 'utf8');
const blocks = text.split(/\n(?=\*\*[A-Z]-\d+\*\*)/).filter(b => /^\*\*[A-Z]-\d+\*\*/.test(b));
let n = 0, exact = 0, moved = 0, missing = 0, nosnip = 0;
const keyAlt = Object.keys(map).map(k => k.replace(/[.*+?^${}()|[\]\\\/]/g, '\\$&')).join('|');
const citeRe = new RegExp(`(${keyAlt}):(\\d+)(?:-(\\d+))?`, 'g');
for (const b of blocks) {
  const id = b.match(/^\*\*([A-Z]-\d+)\*\*/)[1];
  const src = (b.match(/(?:Source|Fonte):\s*(.*)/) || [])[1] || '';
  // snippet text sits between "Snippet(s):" and the next field ("Test"/"Teste") — may hold several backticked parts
  const snipField = (b.match(/Snippets?:\s*([\s\S]*?)(?:\n\s*-\s*(?:Test|Teste)\b|$)/) || [])[1] || '';
  const snips = [...snipField.matchAll(/`([^`]+)`/g)].map(m => m[1]);
  const cites = [...src.matchAll(citeRe)].map(m => ({ key: m[1], a: +m[2], b: +(m[3] || m[2]) }));
  if (!snips.length || !cites.length) { nosnip++; console.log(`NOPARSE ${id} src="${src.slice(0, 60)}" snips=${snips.length}`); continue; }
  for (const s of snips) {
    n++;
    let ok = false;
    for (const c of cites) { const L = lines(c.key); for (let i = c.a; i <= c.b; i++) if ((L[i - 1] || '').includes(s)) ok = true; }
    if (ok) { exact++; continue; }
    // look anywhere in the cited files
    let where = null;
    for (const k of new Set(cites.map(c => c.key))) { const i = lines(k).findIndex(x => x.includes(s)); if (i >= 0) { where = `${k}:${i + 1}`; break; } }
    if (where) { moved++; console.log(`MOVED ${id} cited ${cites.map(c => c.key + ':' + c.a + (c.b > c.a ? '-' + c.b : '')).join(',')} actual ${where} :: ${s.slice(0, 60)}`); }
    else { missing++; console.log(`MISSING ${id} :: ${s.slice(0, 90)}`); }
  }
}
console.log(`blocks=${blocks.length} snippets=${n} exact=${exact} wrong_line=${moved} not_found=${missing} unparsed_blocks=${nosnip}`);
