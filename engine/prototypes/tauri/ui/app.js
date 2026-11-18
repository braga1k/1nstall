// The install library screen. Every piece of data comes from the Rust engine through `invoke`.
const { invoke } = window.__TAURI__.core;
const appWindow = window.__TAURI__.window.getCurrentWindow();
const $ = (id) => document.getElementById(id);

let view = null;
const selected = [];
const installed = new Set();
const cards = new Map();

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function buildCard(card) {
  const node = element('div', 'card');
  node.setAttribute('role', 'checkbox');
  node.setAttribute('aria-checked', 'false');
  node.setAttribute('aria-label', card.Name);
  node.tabIndex = 0;
  node.dataset.key = card.Key;
  const top = element('div', 'top');
  top.append(element('span', 'name', card.Name), element('span', 'switch'));
  const method = element('span', 'meta method', card.Method);
  node.append(top, element('span', 'meta', card.Category), method, element('span', 'details', view.Strings['Details']));
  cards.set(card.Key, { node, method, card, search: (card.Name + ' ' + card.Category).toLowerCase() });
  return node;
}

async function refreshQueue() {
  const result = await invoke('plan', { keys: selected });
  $('selected-label').textContent = result.Count;
  const queue = $('queue');
  queue.replaceChildren(...result.Rows.map((row) => {
    const item = element('li');
    const name = element('div', 'name');
    const remove = element('button', 'caption', '×');
    remove.setAttribute('aria-label', 'Remove ' + row.Name);
    remove.addEventListener('click', () => toggle(row.Key));
    name.append(element('span', '', row.Name), remove);
    item.append(name, element('div', 'method', row.Method));
    return item;
  }));
  $('status').textContent = result.Error || view.Strings[selected.length ? 'Selection updated. Review before installing.' : 'Your next setup starts here. Select apps from the library.'];
}

function toggle(key) {
  const index = selected.indexOf(key);
  if (index >= 0) selected.splice(index, 1); else selected.push(key);
  const entry = cards.get(key);
  if (entry) entry.node.setAttribute('aria-checked', String(index < 0));
  return refreshQueue();
}

function applySearch(query) {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  let shown = 0;
  for (const entry of cards.values()) {
    const match = words.every((word) => entry.search.includes(word));
    entry.node.hidden = !match;
    if (match) shown++;
  }
  $('empty').hidden = shown > 0;
  $('cards').hidden = shown === 0;
}

async function start() {
  view = await invoke('view');
  document.documentElement.lang = view.Lang;
  document.documentElement.dir = view.Rtl ? 'rtl' : 'ltr';
  for (const node of document.querySelectorAll('[data-t]')) node.textContent = view.Strings[node.dataset.t] ?? node.dataset.t;
  $('search').placeholder = view.Strings['Search apps · Ctrl+F'];
  $('search').setAttribute('aria-label', view.Strings['Search apps · Ctrl+F']);
  $('review').textContent = (view.Strings['Review & install'] ?? 'Review & install') + '  →';
  $('empty').textContent = view.Strings['No apps found. Try another search or All apps.'];
  $('library-label').textContent = view.LibraryLabel;
  $('groups').replaceChildren(...view.Groups.map((group) => {
    const button = element('button');
    button.append(element('span', '', group.Name), element('span', '', '›'));
    return button;
  }));
  $('cards').replaceChildren(...view.Cards.map(buildCard));
  for (const key of view.Select) {
    if (!cards.has(key)) continue;
    selected.push(key);
    cards.get(key).node.setAttribute('aria-checked', 'true');
  }
  await refreshQueue();

  $('cards').addEventListener('click', (event) => { const card = event.target.closest('.card'); if (card) toggle(card.dataset.key); });
  $('cards').addEventListener('keydown', (event) => { if (event.key === ' ' && event.target.classList.contains('card')) { event.preventDefault(); toggle(event.target.dataset.key); } });
  $('search').addEventListener('input', (event) => applySearch(event.target.value));
  $('clear').addEventListener('click', () => { for (const key of selected.splice(0)) cards.get(key)?.node.setAttribute('aria-checked', 'false'); refreshQueue(); });
  $('minimize').addEventListener('click', () => appWindow.minimize());
  $('maximize').addEventListener('click', () => appWindow.toggleMaximize());
  $('close').addEventListener('click', () => appWindow.close());
  document.addEventListener('keydown', (event) => { if (event.ctrlKey && event.key.toLowerCase() === 'f') { event.preventDefault(); $('search').focus(); } });

  // First frame with the cards, then the frame after it: drawn, and idle.
  requestAnimationFrame(async () => {
    await invoke('rendered');
    requestAnimationFrame(async () => {
      const testing = await invoke('ready');
      if (testing) return;
      for (const key of await invoke('installed')) {
        installed.add(key);
        const entry = cards.get(key);
        if (entry) { entry.method.textContent = view.Strings['Installed'] + ' · ' + entry.card.Method; entry.method.classList.add('installed'); }
      }
    });
  });
}

start();
