const app = document.getElementById('app');
const truckList = document.getElementById('truckList');
const templateList = document.getElementById('templateList');
const truckForm = document.getElementById('truckForm');
const editorEmpty = document.getElementById('editorEmpty');
const editorTitle = document.getElementById('editorTitle');
const bridgeMeta = document.getElementById('bridgeMeta');
const menuRows = document.getElementById('menuRows');
const stockRows = document.getElementById('stockRows');
const categorySelect = document.getElementById('fCategory');
const vehicleList = document.getElementById('vehicleList');

let state = {
  trucks: [],
  templates: [],
  categories: [],
  vehicles: [],
  defaults: {},
  activeId: null,
  editingIdLocked: false,
};

function resourceName() {
  try {
    return GetParentResourceName();
  } catch (_) {
    return 'viking_foodtruck';
  }
}

async function nui(event, data = {}) {
  const res = await fetch(`https://${resourceName()}/${event}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  });
  try {
    return await res.json();
  } catch (_) {
    return {};
  }
}

function showEditor(show) {
  truckForm.classList.toggle('hidden', !show);
  editorEmpty.classList.toggle('hidden', show);
}

function setTabs() {
  document.querySelectorAll('.tab').forEach((tab) => {
    tab.addEventListener('click', () => {
      document.querySelectorAll('.tab').forEach((t) => t.classList.remove('active'));
      document.querySelectorAll('.tab-panel').forEach((p) => p.classList.remove('active'));
      tab.classList.add('active');
      document.querySelector(`[data-panel="${tab.dataset.tab}"]`).classList.add('active');
    });
  });
}

function fillCategories() {
  categorySelect.innerHTML = '';
  (state.categories || []).forEach((c) => {
    const opt = document.createElement('option');
    opt.value = c.id;
    opt.textContent = c.label;
    categorySelect.appendChild(opt);
  });
}

function fillVehicles() {
  vehicleList.innerHTML = '';
  (state.vehicles || []).forEach((v) => {
    const opt = document.createElement('option');
    opt.value = v;
    vehicleList.appendChild(opt);
  });
}

function renderLists() {
  truckList.innerHTML = '';
  state.trucks.forEach((t) => {
    const li = document.createElement('li');
    li.className = state.activeId === t.id ? 'active' : '';
    li.innerHTML = `<strong>${t.label}</strong><span class="meta">${t.id} · $${t.price || 0}${t.owner_id ? ' · owned' : ''}</span>`;
    li.addEventListener('click', () => loadTruck(t));
    truckList.appendChild(li);
  });

  templateList.innerHTML = '';
  state.templates.forEach((t) => {
    const li = document.createElement('li');
    li.innerHTML = `<strong>${t.label}</strong><span class="meta">Template · $${t.price || 0}</span>`;
    li.addEventListener('click', async () => {
      const res = await nui('importTemplate', { id: t.id });
      if (res.truck) {
        loadTruck(res.truck, true);
      }
    });
    templateList.appendChild(li);
  });
}

function blankMenuItem() {
  return {
    item: '',
    label: '',
    price: 10,
    cookMs: state.defaults.cookMs || 8000,
    category: 'food',
    hunger: 0,
    thirst: 0,
    stress: 0,
    ingredients: [{ item: '', count: 1 }],
  };
}

function addMenuCard(item = blankMenuItem()) {
  const card = document.createElement('div');
  card.className = 'card menu-card';

  card.innerHTML = `
    <div class="card-head">
      <span>Menu Item</span>
      <button type="button" class="btn danger btn-remove-menu">Remove</button>
    </div>
    <div class="menu-grid">
      <input class="m-item" placeholder="item spawn name" value="${item.item || ''}">
      <input class="m-label" placeholder="Label" value="${item.label || ''}">
      <input class="m-price" type="number" min="0" placeholder="Price" value="${item.price ?? 0}">
      <input class="m-cook" type="number" min="500" placeholder="Cook ms" value="${item.cookMs ?? 8000}">
    </div>
    <div class="menu-grid needs-grid">
      <input class="m-cat" placeholder="category" value="${item.category || 'food'}">
      <input class="m-hunger" type="number" min="0" max="100" placeholder="Hunger" value="${item.hunger ?? 0}">
      <input class="m-thirst" type="number" min="0" max="100" placeholder="Thirst" value="${item.thirst ?? 0}">
      <input class="m-stress" type="number" min="0" max="100" placeholder="Stress relief" value="${item.stress ?? 0}">
    </div>
    <div class="panel-toolbar"><span>Ingredients</span><button type="button" class="btn btn-add-ing">+ Ingredient</button></div>
    <div class="ingredients"></div>
  `;

  const ingBox = card.querySelector('.ingredients');
  const addIng = (ing = { item: '', count: 1 }) => {
    const row = document.createElement('div');
    row.className = 'ing-row';
    row.innerHTML = `
      <input class="i-item" placeholder="ingredient item" value="${ing.item || ''}">
      <input class="i-count" type="number" min="1" value="${ing.count ?? 1}">
      <button type="button" class="btn danger btn-del-ing">×</button>
    `;
    row.querySelector('.btn-del-ing').addEventListener('click', () => row.remove());
    ingBox.appendChild(row);
  };

  (item.ingredients && item.ingredients.length ? item.ingredients : [{ item: '', count: 1 }]).forEach(addIng);
  card.querySelector('.btn-add-ing').addEventListener('click', () => addIng());
  card.querySelector('.btn-remove-menu').addEventListener('click', () => card.remove());
  menuRows.appendChild(card);
}

function addStockRow(item = '', count = 1) {
  const row = document.createElement('div');
  row.className = 'stock-row';
  row.innerHTML = `
    <input class="s-item" placeholder="item" value="${item}">
    <input class="s-count" type="number" min="0" value="${count}">
    <button type="button" class="btn danger btn-del-stock">×</button>
  `;
  row.querySelector('.btn-del-stock').addEventListener('click', () => row.remove());
  stockRows.appendChild(row);
}

function clearDynamic() {
  menuRows.innerHTML = '';
  stockRows.innerHTML = '';
}

function loadTruck(truck, fromTemplate = false) {
  state.activeId = truck.id;
  state.editingIdLocked = !fromTemplate && !!truck.id && state.trucks.some((t) => t.id === truck.id);
  showEditor(true);
  editorTitle.textContent = fromTemplate ? `Template: ${truck.label}` : truck.label || 'Edit Truck';
  renderLists();

  const data = truck.data || {};
  document.getElementById('fId').value = truck.id || '';
  document.getElementById('fId').readOnly = state.editingIdLocked;
  document.getElementById('fLabel').value = truck.label || '';
  document.getElementById('fCategory').value = truck.category || 'custom';
  document.getElementById('fEnabled').value = truck.enabled === false ? 'false' : 'true';
  document.getElementById('fPrice').value = truck.price ?? 50000;
  document.getElementById('fDescription').value = truck.description || data.description || '';

  document.getElementById('fVehicle').value = data.vehicle || state.defaults.vehicle || 'taco';
  document.getElementById('fPlate').value = data.platePrefix || 'FOOD';
  document.getElementById('fLivery').value = data.livery ?? '';

  const ret = data.retrieve || {};
  document.getElementById('fRetX').value = ret.x ?? '';
  document.getElementById('fRetY').value = ret.y ?? '';
  document.getElementById('fRetZ').value = ret.z ?? '';
  document.getElementById('fRetW').value = ret.w ?? '';

  document.getElementById('fShopRadius').value = data.shopRadius ?? 3;
  const win = data.windowOffset || {};
  document.getElementById('fWinX').value = win.x ?? 0;
  document.getElementById('fWinY').value = win.y ?? -2;
  document.getElementById('fWinZ').value = win.z ?? 0;

  const blip = data.blip || state.defaults.blip || {};
  document.getElementById('fBlipEnabled').value = blip.enabled === false ? 'false' : 'true';
  document.getElementById('fBlipSprite').value = blip.sprite ?? 106;
  document.getElementById('fBlipColor').value = blip.color ?? 5;
  document.getElementById('fBlipScale').value = blip.scale ?? 0.75;
  document.getElementById('fMaxStock').value = data.maxStock ?? 250;

  clearDynamic();
  (data.menu && data.menu.length ? data.menu : [blankMenuItem()]).forEach(addMenuCard);
  const stock = data.startingStock || {};
  const keys = Object.keys(stock);
  if (keys.length) keys.forEach((k) => addStockRow(k, stock[k]));
  else addStockRow('', 0);
}

function newTruck() {
  loadTruck({
    id: '',
    label: '',
    category: 'custom',
    enabled: true,
    price: 50000,
    description: '',
    data: {
      vehicle: state.defaults.vehicle || 'taco',
      platePrefix: 'FOOD',
      shopRadius: 3,
      windowOffset: { x: 0, y: -2, z: 0 },
      blip: state.defaults.blip || { enabled: true, sprite: 106, color: 5, scale: 0.75 },
      menu: [blankMenuItem()],
      maxStock: 250,
      startingStock: {},
    },
  }, true);
  state.editingIdLocked = false;
  document.getElementById('fId').readOnly = false;
  editorTitle.textContent = 'New Food Truck';
}

function collectMenu() {
  return [...menuRows.querySelectorAll('.menu-card')].map((card) => ({
    item: card.querySelector('.m-item').value.trim(),
    label: card.querySelector('.m-label').value.trim(),
    price: Number(card.querySelector('.m-price').value || 0),
    cookMs: Number(card.querySelector('.m-cook').value || 8000),
    category: card.querySelector('.m-cat').value.trim() || 'food',
    hunger: Number(card.querySelector('.m-hunger').value || 0),
    thirst: Number(card.querySelector('.m-thirst').value || 0),
    stress: Number(card.querySelector('.m-stress').value || 0),
    ingredients: [...card.querySelectorAll('.ing-row')].map((row) => ({
      item: row.querySelector('.i-item').value.trim(),
      count: Number(row.querySelector('.i-count').value || 1),
    })).filter((i) => i.item),
  })).filter((m) => m.item);
}

function collectStock() {
  const stock = {};
  [...stockRows.querySelectorAll('.stock-row')].forEach((row) => {
    const item = row.querySelector('.s-item').value.trim();
    const count = Number(row.querySelector('.s-count').value || 0);
    if (item) stock[item] = count;
  });
  return stock;
}

function collectPayload() {
  const rx = document.getElementById('fRetX').value;
  const ry = document.getElementById('fRetY').value;
  const rz = document.getElementById('fRetZ').value;
  const rw = document.getElementById('fRetW').value;
  let retrieve;
  if (rx !== '' && ry !== '' && rz !== '') {
    retrieve = {
      x: Number(rx),
      y: Number(ry),
      z: Number(rz),
      w: Number(rw || 0),
    };
  }

  const liveryVal = document.getElementById('fLivery').value;
  return {
    id: document.getElementById('fId').value.trim(),
    label: document.getElementById('fLabel').value.trim(),
    category: document.getElementById('fCategory').value,
    enabled: document.getElementById('fEnabled').value === 'true',
    price: Number(document.getElementById('fPrice').value || 0),
    description: document.getElementById('fDescription').value.trim(),
    data: {
      description: document.getElementById('fDescription').value.trim(),
      vehicle: document.getElementById('fVehicle').value.trim(),
      platePrefix: document.getElementById('fPlate').value.trim(),
      livery: liveryVal === '' ? null : Number(liveryVal),
      retrieve,
      shopRadius: Number(document.getElementById('fShopRadius').value || 3),
      windowOffset: {
        x: Number(document.getElementById('fWinX').value || 0),
        y: Number(document.getElementById('fWinY').value || -2),
        z: Number(document.getElementById('fWinZ').value || 0),
      },
      blip: {
        enabled: document.getElementById('fBlipEnabled').value === 'true',
        sprite: Number(document.getElementById('fBlipSprite').value || 106),
        color: Number(document.getElementById('fBlipColor').value || 5),
        scale: Number(document.getElementById('fBlipScale').value || 0.75),
      },
      menu: collectMenu(),
      maxStock: Number(document.getElementById('fMaxStock').value || 250),
      startingStock: collectStock(),
    },
  };
}

function applyCreatorData(data) {
  state.trucks = data.trucks || [];
  state.templates = data.templates || [];
  state.categories = data.categories || [];
  state.vehicles = data.vehicles || [];
  state.defaults = data.defaults || {};
  fillCategories();
  fillVehicles();
  renderLists();
  if (data.bridge) {
    const b = data.bridge;
    bridgeMeta.textContent = `FW: ${b.framework} · Inv: ${b.inventory} · Bank: ${b.banking || 'framework'} · Bill: ${b.billing || 'builtin'} · Food: ${b.food || 'inventory'} · Rest: ${b.restaurant || 'none'} · Cons: ${b.consumables || 'none'}`;
  }
}

const ftTextUi = document.getElementById('ftTextUi');
const ftProgress = document.getElementById('ftProgress');
const ftOverlay = document.getElementById('ftOverlay');
const ftModalTitle = document.getElementById('ftModalTitle');
const ftModalBody = document.getElementById('ftModalBody');
const ftModalActions = document.getElementById('ftModalActions');
let ftProgressTimer = null;
let ftLibOpen = false;

function ftPost(event, data = {}) {
  return fetch(`https://${resourceName()}/${event}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  });
}

function closeFtOverlay(result) {
  ftLibOpen = false;
  ftOverlay.classList.add('hidden');
  ftModalBody.innerHTML = '';
  ftModalActions.innerHTML = '';
  if (result === null || result === undefined) {
    ftPost('ftlibCancel', {});
  } else {
    ftPost('ftlibResult', result);
  }
}

function openContext(data) {
  ftLibOpen = true;
  ftOverlay.classList.remove('hidden');
  ftModalTitle.textContent = data.title || 'Menu';
  ftModalBody.innerHTML = '';
  ftModalActions.innerHTML = '';
  (data.options || []).forEach((opt, i) => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'ft-option';
    btn.disabled = !!opt.disabled;
    btn.innerHTML = `<strong>${opt.title || ''}</strong>${opt.description ? `<small>${opt.description}</small>` : ''}`;
    btn.addEventListener('click', () => closeFtOverlay({ index: i + 1 }));
    ftModalBody.appendChild(btn);
  });
  const cancel = document.createElement('button');
  cancel.type = 'button';
  cancel.className = 'btn';
  cancel.textContent = 'Close';
  cancel.addEventListener('click', () => closeFtOverlay(null));
  ftModalActions.appendChild(cancel);
}

function openAlert(data) {
  ftLibOpen = true;
  ftOverlay.classList.remove('hidden');
  ftModalTitle.textContent = data.header || 'Confirm';
  ftModalBody.innerHTML = `<p style="color:var(--muted);margin:0;line-height:1.45">${data.content || ''}</p>`;
  ftModalActions.innerHTML = '';
  if (data.cancel !== false) {
    const cancel = document.createElement('button');
    cancel.type = 'button';
    cancel.className = 'btn';
    cancel.textContent = 'Cancel';
    cancel.addEventListener('click', () => closeFtOverlay({ confirm: false }));
    ftModalActions.appendChild(cancel);
  }
  const ok = document.createElement('button');
  ok.type = 'button';
  ok.className = 'btn primary';
  ok.textContent = 'Confirm';
  ok.addEventListener('click', () => closeFtOverlay({ confirm: true }));
  ftModalActions.appendChild(ok);
}

function openInput(data) {
  ftLibOpen = true;
  ftOverlay.classList.remove('hidden');
  ftModalTitle.textContent = data.title || 'Input';
  ftModalBody.innerHTML = '';
  ftModalActions.innerHTML = '';
  const fields = [];
  (data.rows || []).forEach((row, i) => {
    const wrap = document.createElement('label');
    wrap.className = 'ft-field';
    const label = row.label || row.title || `Field ${i + 1}`;
    wrap.innerHTML = `${label}`;
    let input;
    if (row.type === 'select' && row.options) {
      input = document.createElement('select');
      row.options.forEach((o) => {
        const opt = document.createElement('option');
        opt.value = o.value;
        opt.textContent = o.label || o.value;
        input.appendChild(opt);
      });
    } else {
      input = document.createElement('input');
      input.type = row.type === 'number' ? 'number' : 'text';
      if (row.min != null) input.min = row.min;
      if (row.max != null) input.max = row.max;
      if (row.default != null) input.value = row.default;
      input.placeholder = row.placeholder || '';
      input.required = !!row.required;
    }
    input.dataset.idx = String(i);
    wrap.appendChild(input);
    fields.push(input);
    ftModalBody.appendChild(wrap);
  });
  const cancel = document.createElement('button');
  cancel.type = 'button';
  cancel.className = 'btn';
  cancel.textContent = 'Cancel';
  cancel.addEventListener('click', () => closeFtOverlay(null));
  const ok = document.createElement('button');
  ok.type = 'button';
  ok.className = 'btn primary';
  ok.textContent = 'Submit';
  ok.addEventListener('click', () => {
    const values = fields.map((f) => {
      if (f.type === 'number') return f.value === '' ? null : Number(f.value);
      return f.value;
    });
    closeFtOverlay({ values });
  });
  ftModalActions.appendChild(cancel);
  ftModalActions.appendChild(ok);
}

const ftStockInv = document.getElementById('ftStockInv');
const ftStockTitle = document.getElementById('ftStockTitle');
const ftStockPrepared = document.getElementById('ftStockPrepared');
const ftStockIngredients = document.getElementById('ftStockIngredients');
let ftStockTruckId = null;

function stockAction(action, item) {
  ftPost('stockInvAction', {
    action,
    item: item || '',
    truckId: ftStockTruckId,
  });
}

function renderStockSlots(container, items, kind) {
  container.innerHTML = '';
  if (!items || !items.length) {
    const empty = document.createElement('div');
    empty.className = 'ft-stock-empty';
    empty.textContent = kind === 'prepared' ? 'No prepared food yet — craft to truck stock.' : 'No ingredient stock.';
    container.appendChild(empty);
    return;
  }
  items.forEach((it) => {
    const slot = document.createElement('button');
    slot.type = 'button';
    slot.className = `ft-stock-slot${kind === 'prepared' ? ' prepared' : ''}`;
    slot.innerHTML = `
      <span class="slot-label">${it.label || it.item}</span>
      <span class="slot-item">${it.item || ''}</span>
      <span class="slot-count">${it.count ?? 0}</span>
    `;
    slot.title = 'Click to take from truck';
    slot.addEventListener('click', () => stockAction('take', it.item));
    slot.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      stockAction('deposit', it.item);
    });
    container.appendChild(slot);
  });
}

function openStockInv(data) {
  if (!data || data.show === false) {
    ftStockInv.classList.add('hidden');
    ftStockTruckId = null;
    return;
  }
  ftStockTruckId = data.truckId || null;
  ftStockTitle.textContent = data.title || 'Truck Stock';
  renderStockSlots(ftStockPrepared, data.prepared || [], 'prepared');
  renderStockSlots(ftStockIngredients, data.ingredients || [], 'ingredient');
  ftStockInv.classList.remove('hidden');
}

document.getElementById('ftStockClose').addEventListener('click', () => {
  ftStockInv.classList.add('hidden');
  ftPost('stockInvClose', {});
});
document.getElementById('ftStockRefresh').addEventListener('click', () => stockAction('refresh'));
document.getElementById('ftStockDepositNew').addEventListener('click', () => stockAction('deposit', ''));

window.addEventListener('message', (event) => {
  const msg = event.data;
  if (!msg || !msg.action) return;
  if (msg.action === 'openCreator') {
    app.classList.remove('hidden');
    applyCreatorData(msg.data || {});
    showEditor(false);
    editorTitle.textContent = 'Select or Create a Truck';
  }
  if (msg.action === 'closeCreator') {
    app.classList.add('hidden');
  }
  if (msg.action === 'textui') {
    const d = msg.data || {};
    if (d.show) {
      ftTextUi.textContent = d.text || '';
      ftTextUi.classList.remove('hidden');
    } else {
      ftTextUi.classList.add('hidden');
    }
  }
  if (msg.action === 'progress') {
    const d = msg.data || {};
    if (d.show) {
      ftProgress.classList.remove('hidden');
      ftProgress.querySelector('.ft-progress-label').textContent = d.label || '';
      const fill = ftProgress.querySelector('.ft-progress-fill');
      fill.style.transition = 'none';
      fill.style.width = '0%';
      requestAnimationFrame(() => {
        fill.style.transition = `width ${Number(d.duration || 1000)}ms linear`;
        fill.style.width = '100%';
      });
      if (ftProgressTimer) clearTimeout(ftProgressTimer);
      ftProgressTimer = setTimeout(() => {
        ftProgress.classList.add('hidden');
      }, Number(d.duration || 1000) + 50);
    } else {
      if (ftProgressTimer) clearTimeout(ftProgressTimer);
      ftProgress.classList.add('hidden');
    }
  }
  if (msg.action === 'context') openContext(msg.data || {});
  if (msg.action === 'alert') openAlert(msg.data || {});
  if (msg.action === 'input') openInput(msg.data || {});
  if (msg.action === 'stockInv') openStockInv(msg.data || {});
});

document.getElementById('btnClose').addEventListener('click', () => nui('close'));
document.getElementById('btnNew').addEventListener('click', newTruck);
document.getElementById('btnRefresh').addEventListener('click', async () => {
  const data = await nui('refresh');
  if (data && data.trucks) applyCreatorData(data);
});
document.getElementById('btnAddMenu').addEventListener('click', () => addMenuCard());
document.getElementById('btnAddStock').addEventListener('click', () => addStockRow());
document.getElementById('btnUseCoords').addEventListener('click', async () => {
  const coords = await nui('getCoords');
  if (!coords) return;
  document.getElementById('fRetX').value = coords.x.toFixed(2);
  document.getElementById('fRetY').value = coords.y.toFixed(2);
  document.getElementById('fRetZ').value = coords.z.toFixed(2);
  document.getElementById('fRetW').value = coords.w.toFixed(2);
});

document.getElementById('btnDelete').addEventListener('click', async () => {
  const id = document.getElementById('fId').value.trim();
  if (!id) return;
  const res = await nui('deleteTruck', { id });
  if (res.ok) {
    state.activeId = null;
    showEditor(false);
    const data = await nui('refresh');
    if (data && data.trucks) applyCreatorData(data);
  }
});

truckForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const payload = collectPayload();
  if (!payload.id || !payload.label) return;
  const res = await nui('saveTruck', payload);
  if (res.ok) {
    const data = await nui('refresh');
    if (data && data.trucks) applyCreatorData(data);
    if (res.result) loadTruck(res.result);
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  if (!ftStockInv.classList.contains('hidden')) {
    ftStockInv.classList.add('hidden');
    ftPost('stockInvClose', {});
    return;
  }
  if (ftLibOpen) {
    closeFtOverlay(null);
    return;
  }
  if (!app.classList.contains('hidden')) {
    nui('close');
  }
});

setTabs();
