(() => {
  'use strict';

  const state = {
    data: null,
    markers: new Map(),
    activeId: null,
    layer: null,
  };

  const els = {
    app: document.querySelector('.app'),
    statsTotal: document.getElementById('stat-total'),
    statsHomes: document.getElementById('stat-homes'),
    statsRedundant: document.getElementById('stat-redundant'),
    statsAgents: document.getElementById('stat-agents'),
    q: document.getElementById('q'),
    filterMicrosite: document.getElementById('filter-microsite'),
    filterHomesNi: document.getElementById('filter-homesni'),
    status: document.getElementById('status'),
    hideRedundant: document.getElementById('hide-redundant'),
    paneList: document.getElementById('pane-list'),
    paneAgents: document.getElementById('pane-agents'),
    paneDevelopers: document.getElementById('pane-developers'),
    meta: document.getElementById('meta'),
    browseFab: document.getElementById('browse-fab'),
    sheetClose: document.getElementById('sheet-close'),
    sheetBackdrop: document.getElementById('sheet-backdrop'),
    sheetGrab: document.getElementById('sheet-grab'),
  };

  const mqMobile = window.matchMedia('(max-width: 860px)');

  function isMobile() {
    return mqMobile.matches;
  }

  function setSheetOpen(open) {
    if (!els.app) return;
    els.app.classList.toggle('sheet-open', !!open);
    if (els.browseFab) els.browseFab.setAttribute('aria-expanded', open ? 'true' : 'false');
    if (els.sheetBackdrop) els.sheetBackdrop.hidden = !open;
    if (open) {
      document.documentElement.style.overflow = isMobile() ? 'hidden' : '';
    } else {
      document.documentElement.style.overflow = '';
    }
    requestAnimationFrame(() => {
      map.invalidateSize({ animate: false });
    });
  }

  function popupOptions() {
    if (isMobile()) {
      const w = Math.min(300, Math.max(220, window.innerWidth - 48));
      return {
        maxWidth: w,
        minWidth: Math.min(200, w - 20),
        autoPanPadding: [16, 72],
        keepInView: true,
      };
    }
    return { maxWidth: 320, minWidth: 220, autoPanPadding: [24, 24] };
  }

  const map = L.map('map', {
    zoomControl: true,
    minZoom: 7,
    maxZoom: 14,
    attributionControl: true,
    tapTolerance: 22,
  }).setView([54.6, -6.5], 8);

  // Ocean backdrop — no basemap tiles / API keys
  map.getContainer().style.background =
    'radial-gradient(120% 90% at 50% 35%, #8ec8ea 0%, #6eb5e0 42%, #4f9dcb 100%)';
  map.attributionControl.setPrefix(false);
  map.attributionControl.addAttribution('County boundaries OSNI (OGL)');

  function markerIcon(dev) {
    const redundant = !!(dev && dev.redundant);
    const microsite = !!(dev && dev.hasMicrosite);
    const notOnHomesNiFilter = !!(els.filterHomesNi && els.filterHomesNi.checked);
    const notOnHomesNi = !(dev && dev.onHomesNi);
    // Default: redundant red → microsite gold → live green.
    // Development not on HomesNI filter on: those pins get blue.
    let color = '#1f7a4c';
    let extraClass = '';
    let glow = '0 2px 6px rgba(10,30,18,.45), 0 1px 0 rgba(255,255,255,.35) inset';
    if (redundant) {
      color = '#a13d2d';
    } else if (notOnHomesNiFilter && notOnHomesNi) {
      color = '#1f50b3';
      extraClass = ' dev-marker-homesni';
      glow = '0 0 10px rgba(31,80,179,.75), 0 0 18px rgba(31,80,179,.45), 0 2px 6px rgba(10,30,18,.35), 0 1px 0 rgba(255,255,255,.35) inset';
    } else if (microsite) {
      color = '#c9a227';
      extraClass = ' dev-marker-microsite';
    }
    const size = isMobile() ? 10 : 14;
    const half = size / 2;
    return L.divIcon({
      className: 'dev-marker' + extraClass,
      html: `<span style="display:block;width:${size}px;height:${size}px;border-radius:50%;background:${color};border:2px solid #fff;box-shadow:${glow}"></span>`,
      iconSize: [size, size],
      iconAnchor: [half, half],
      popupAnchor: [0, -half - 2],
    });
  }

  function resolveAsset(src) {
    const raw = String(src || '').trim();
    if (!raw) return '';
    try {
      return new URL(raw, document.baseURI).href;
    } catch (_) {
      return raw;
    }
  }

  function isPhoneNumberJunk(name) {
    return /^phone\s*number$/i.test(String(name || '').trim());
  }

  function isAnonymousDeveloper(name) {
    return /^(multiple\s+developers|private\s+developer|undisclosed\s+developers?)$/i.test(String(name || '').trim());
  }

  function displayOrgName(name) {
    const raw = String(name || '').trim();
    if (!raw) return '';
    if (isPhoneNumberJunk(raw)) return '';
    if (/^multiple\s+developers$/i.test(raw) || /^undisclosed\s+developers?$/i.test(raw) || /^private\s+developer$/i.test(raw)) {
      return 'Undisclosed Developers';
    }
    return raw;
  }

  function cleanOrgList(list, fallbackName) {
    const seen = new Set();
    const out = [];
    const push = (name, image, url) => {
      const display = displayOrgName(name);
      if (!display) return;
      const key = display.toLowerCase();
      if (seen.has(key)) return;
      seen.add(key);
      out.push({
        name: display,
        image: isAnonymousDeveloper(display) ? '' : (image || ''),
        url: isAnonymousDeveloper(display) ? '' : (url || ''),
      });
    };
    for (const o of Array.isArray(list) ? list : []) {
      if (!o) continue;
      push(o.name, o.image, o.url);
    }
    if (!out.length && fallbackName) {
      String(fallbackName)
        .split(';')
        .map((n) => n.trim())
        .filter(Boolean)
        .forEach((n) => push(n, '', ''));
    }
    return out;
  }

  function logoImg(src, name, className = 'org-logo') {
    if (isAnonymousDeveloper(name)) {
      return `<span class="${className} placeholder" aria-hidden="true"></span>`;
    }
    const href = resolveAsset(src);
    if (!href) return `<span class="${className} placeholder" aria-hidden="true"></span>`;
    return `<img class="${className}" src="${escapeAttr(href)}" alt="${escapeAttr(name || 'Logo')}" decoding="async" />`;
  }

  function orgCards(list, fallbackName) {
    const items = cleanOrgList(list, fallbackName);
    if (!items.length) return '';
    return `<div class="org-row">${items.map((o) => {
      const name = o.name || '';
      const src = isAnonymousDeveloper(name) ? '' : (o.image || o.url || '');
      return `<div class="org-card">${logoImg(src, name)}<span class="org-name">${escapeHtml(name || '—')}</span></div>`;
    }).join('')}</div>`;
  }

  function logoByName() {
    const map = new Map();
    for (const d of state.data?.developments || []) {
      for (const o of [...(d.agentOrgs || []), ...(d.developerOrgs || [])]) {
        if (!o?.name || !o.image || isAnonymousDeveloper(o.name) || isPhoneNumberJunk(o.name)) continue;
        const key = String(o.name).trim().toLowerCase();
        if (key && !map.has(key)) map.set(key, o.image);
      }
    }
    return map;
  }

  function popupHtml(d) {
    const homes = d.homesAvailable == null ? '—' : d.homesAvailable;
    const status = d.status || (d.redundant ? 'Sale agreed / redundant' : 'Available');
    const developerCards = orgCards(d.developerOrgs, d.developers || 'Developer n/a');
    const agentCards = orgCards(d.agentOrgs, d.agents || 'Agent n/a');
    return `<div class="popup">
      <h3>${escapeHtml(d.name)}</h3>
      <p>${escapeHtml(d.address || '')}</p>
      <p><strong>${escapeHtml(String(homes))}</strong> homes available · ${escapeHtml(d.price || 'Price n/a')}</p>
      <p>${escapeHtml(status)}</p>
      <p class="org-label">Developer</p>
      ${developerCards || '<div class="org-row"><div class="org-card"><span class="org-name">Developer n/a</span></div></div>'}
      <p class="org-label">Agent</p>
      ${agentCards || '<div class="org-row"><div class="org-card"><span class="org-name">Agent n/a</span></div></div>'}
    </div>`;
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }
  function escapeAttr(s) {
    return escapeHtml(s).replace(/'/g, '&#39;');
  }

  function filtered() {
    const q = (els.q.value || '').trim().toLowerCase();
    const status = els.status.value;
    const hideRedundant = els.hideRedundant.checked;
    const micrositeOnly = !!(els.filterMicrosite && els.filterMicrosite.checked);
    const notOnHomesNi = !!(els.filterHomesNi && els.filterHomesNi.checked);
    return (state.data.developments || []).filter((d) => {
      if (hideRedundant && d.redundant) return false;
      if (micrositeOnly && !d.hasMicrosite) return false;
      if (notOnHomesNi && d.onHomesNi) return false;
      if (status && String(d.status || '') !== status) return false;
      if (!q) return true;
      const hay = [d.name, d.address, d.town, d.agents, d.developers, d.status, d.pathId]
        .map((x) => String(x || '').toLowerCase())
        .join(' ');
      return hay.includes(q);
    });
  }

  function listOrgNames(d, kind) {
    const orgs = kind === 'agent' ? d.agentOrgs : d.developerOrgs;
    const fallback = kind === 'agent' ? d.agents : d.developers;
    return cleanOrgList(orgs, fallback).map((o) => o.name);
  }

  function buildTallies(list, kind) {
    const map = new Map();
    for (const d of list || []) {
      const names = listOrgNames(d, kind);
      const unique = [...new Set(names.map((n) => n.trim()).filter(Boolean))];
      for (const name of unique) {
        const key = name.toLowerCase();
        let row = map.get(key);
        if (!row) {
          row = { name, count: 0, redundant: 0 };
          map.set(key, row);
        }
        row.count += 1;
        if (d.redundant) row.redundant += 1;
      }
    }
    return [...map.values()].sort((a, b) => b.count - a.count || a.name.localeCompare(b.name, 'en'));
  }

  function formatOrgLine(d) {
    const developers = listOrgNames(d, 'developer');
    const agents = listOrgNames(d, 'agent');
    const left = developers.length ? developers.join('; ') : '—';
    const right = agents.length ? agents.join('; ') : '—';
    return `${left} · ${right}`;
  }

  function renderStats(list) {
    const homes = list.reduce((n, d) => n + (Number(d.homesAvailable) || 0), 0);
    const redundant = list.filter((d) => d.redundant).length;
    const agentTallies = buildTallies(list, 'agent');
    els.statsTotal.textContent = String(list.length);
    els.statsHomes.textContent = String(homes);
    els.statsRedundant.textContent = String(redundant);
    els.statsAgents.textContent = String(agentTallies.length);
  }

  function renderList(list) {
    if (!list.length) {
      els.paneList.innerHTML = '<p class="meta" style="padding:8px">No developments match these filters.</p>';
      return;
    }
    const sorted = [...list].sort((a, b) => String(a.name).localeCompare(String(b.name), 'en'));
    els.paneList.innerHTML = sorted.map((d) => {
      const active = d.pathId === state.activeId ? ' active' : '';
      const tags = [];
      if (d.town) tags.push(`<span class="tag">${escapeHtml(d.town)}</span>`);
      if (d.redundant) tags.push('<span class="tag warn">Redundant</span>');
      else tags.push(`<span class="tag ok">${escapeHtml(String(d.homesAvailable ?? '—'))} avail</span>`);
      return `<button type="button" class="card${active}" data-id="${escapeAttr(d.pathId)}">
        <h3>${escapeHtml(d.name)}</h3>
        <p class="meta">${escapeHtml(d.address || '')}</p>
        <p class="meta">${escapeHtml(formatOrgLine(d))}</p>
        <div class="tags">${tags.join('')}</div>
      </button>`;
    }).join('');
  }

  function renderTallies(pane, rows, label) {
    if (!rows || !rows.length) {
      pane.innerHTML = `<p class="meta" style="padding:8px">No ${label} data.</p>`;
      return;
    }
    const logos = logoByName();
    pane.innerHTML = rows.map((r) => {
      const img = isAnonymousDeveloper(r.name)
        ? ''
        : (logos.get(String(r.name || '').trim().toLowerCase()) || '');
      return `<div class="tally">
        ${logoImg(img, r.name, 'tally-logo')}
        <div class="tally-text">
          <div class="tally-name">${escapeHtml(r.name)}</div>
          ${r.redundant ? `<div class="sub">${r.redundant} redundant</div>` : ''}
        </div>
        <strong>${r.count}</strong>
      </div>`;
    }).join('');
  }

  function syncMarkers(list) {
    const keep = new Set(list.map((d) => d.pathId));
    for (const [id, marker] of state.markers) {
      if (!keep.has(id)) {
        state.layer.removeLayer(marker);
        state.markers.delete(id);
      }
    }
    for (const d of list) {
      if (d.lat == null || d.lng == null) continue;
      let marker = state.markers.get(d.pathId);
      if (!marker) {
        marker = L.marker([d.lat, d.lng], { icon: markerIcon(d) });
        marker.bindPopup(() => popupHtml(d), popupOptions());
        marker.on('click', () => selectDev(d.pathId, false));
        state.layer.addLayer(marker);
        state.markers.set(d.pathId, marker);
      } else {
        marker.setIcon(markerIcon(d));
        marker.setPopupContent(() => popupHtml(d));
      }
    }
  }

  function selectDev(pathId, pan = true) {
    state.activeId = pathId;
    const d = (state.data.developments || []).find((x) => x.pathId === pathId);
    renderList(filtered());
    const marker = state.markers.get(pathId);
    if (marker) {
      if (isMobile()) setSheetOpen(false);
      marker.openPopup();
      if (pan && d && d.lat != null) {
        map.setView([d.lat, d.lng], Math.max(map.getZoom(), isMobile() ? 10 : 9), { animate: true });
      }
      requestAnimationFrame(() => map.invalidateSize({ animate: false }));
    }
  }

  function refresh() {
    const list = filtered();
    renderStats(list);
    renderList(list);
    renderTallies(els.paneAgents, buildTallies(list, 'agent'), 'agent');
    renderTallies(els.paneDevelopers, buildTallies(list, 'developer'), 'developer');
    syncMarkers(list);
  }

  function fillStatusOptions(devs) {
    const set = new Set();
    for (const d of devs) {
      String(d.status || '')
        .split(';')
        .map((s) => s.trim())
        .filter(Boolean)
        .forEach((s) => set.add(s));
      if (d.status) set.add(d.status);
    }
    const opts = [...set].sort((a, b) => a.localeCompare(b, 'en'));
    els.status.innerHTML = '<option value="">All statuses</option>' +
      opts.map((s) => `<option value="${escapeAttr(s)}">${escapeHtml(s)}</option>`).join('');
  }

  function ringBoundsCenter(ring) {
    let minLat = 90;
    let maxLat = -90;
    let minLng = 180;
    let maxLng = -180;
    for (const pt of ring || []) {
      const lng = Number(pt[0]);
      const lat = Number(pt[1]);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    if (minLat > maxLat || minLng > maxLng) return null;
    return {
      latlng: L.latLng((minLat + maxLat) / 2, (minLng + maxLng) / 2),
      score: (maxLat - minLat) * (maxLng - minLng),
    };
  }

  /** Prefer the largest polygon so tiny islands don't yank labels (e.g. Down). */
  function countyLabelLatLng(feature, fallbackLayer) {
    const geom = feature?.geometry;
    let best = null;
    if (geom?.type === 'Polygon') {
      best = ringBoundsCenter(geom.coordinates?.[0]);
    } else if (geom?.type === 'MultiPolygon') {
      for (const poly of geom.coordinates || []) {
        const candidate = ringBoundsCenter(poly?.[0]);
        if (!candidate) continue;
        if (!best || candidate.score > best.score) best = candidate;
      }
    }
    if (best?.latlng) return best.latlng;
    try {
      return fallbackLayer.getBounds().getCenter();
    } catch (_) {
      return null;
    }
  }

  function countyDisplayName(raw) {
    const name = String(raw || '').trim();
    if (/^londonderry$/i.test(name)) return 'Derry/Londonderry';
    return name;
  }

  function pointInRing(lng, lat, ring) {
    let inside = false;
    for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      const xi = Number(ring[i][0]);
      const yi = Number(ring[i][1]);
      const xj = Number(ring[j][0]);
      const yj = Number(ring[j][1]);
      const intersect = ((yi > lat) !== (yj > lat))
        && (lng < ((xj - xi) * (lat - yi)) / ((yj - yi) || Number.EPSILON) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  function pointInFeature(lng, lat, feature) {
    const geom = feature?.geometry;
    if (!geom) return false;
    if (geom.type === 'Polygon') {
      const rings = geom.coordinates || [];
      if (!rings.length || !pointInRing(lng, lat, rings[0])) return false;
      for (let i = 1; i < rings.length; i++) {
        if (pointInRing(lng, lat, rings[i])) return false;
      }
      return true;
    }
    if (geom.type === 'MultiPolygon') {
      for (const poly of geom.coordinates || []) {
        if (!poly?.length || !pointInRing(lng, lat, poly[0])) continue;
        let inHole = false;
        for (let i = 1; i < poly.length; i++) {
          if (pointInRing(lng, lat, poly[i])) {
            inHole = true;
            break;
          }
        }
        if (!inHole) return true;
      }
    }
    return false;
  }

  function tallyCountyStats(geo, developments) {
    const rows = (geo.features || []).map((feature) => ({
      feature,
      name: countyDisplayName(feature.properties?.name),
      count: 0,
      available: 0,
    }));
    for (const d of developments || []) {
      const lat = Number(d.lat);
      const lng = Number(d.lng);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
      const hit = rows.find((row) => pointInFeature(lng, lat, row.feature));
      if (!hit) continue;
      hit.count += 1;
      hit.available += Number(d.homesAvailable) || 0;
    }
    return rows;
  }

  function countyLabelHtml(name, count, available) {
    return `<div class="county-label-text">
      <div class="county-label-name">${escapeHtml(name)}</div>
      <div class="county-label-meta">(${count} developments,<br>${available} available)</div>
    </div>`;
  }

  async function loadCounties(developments) {
    try {
      const res = await fetch('data/ni-counties.geojson');
      const geo = await res.json();
      const stats = tallyCountyStats(geo, developments);

      // Green counties + dark green drop-shadow only (no hard underlay / thick rim)
      L.geoJSON(geo, {
        style: {
          color: '#ffffff',
          weight: 1.2,
          opacity: 0.85,
          fillColor: '#4f8f58',
          fillOpacity: 1,
          className: 'county-poly',
          lineJoin: 'round',
        },
        onEachFeature(feature, layer) {
          const name = countyDisplayName(feature.properties?.name);
          if (!name) return;
          const row = stats.find((s) => s.name === name) || { count: 0, available: 0 };
          const latlng = countyLabelLatLng(feature, layer);
          if (!latlng) return;
          L.tooltip({
            permanent: true,
            direction: 'center',
            className: 'county-label',
            opacity: 0.95,
          })
            .setContent(countyLabelHtml(name, row.count, row.available))
            .setLatLng(latlng)
            .addTo(map);
        },
      }).addTo(map);
    } catch (err) {
      console.warn('County layer failed', err);
    }
  }

  async function boot() {
    state.layer = L.layerGroup().addTo(map);

    const res = await fetch(`data/developments.json?v=${Date.now()}`);
    state.data = await res.json();
    await loadCounties(state.data.developments || []);

    fillStatusOptions(state.data.developments || []);
    els.meta.textContent = `${state.data.mappedCount || 0} mapped · ${String(state.data.generated || '').slice(0, 10)}`;
    refresh();

    const mapped = (state.data.developments || []).filter((d) => d.lat != null);
    if (mapped.length) {
      const bounds = L.latLngBounds(mapped.map((d) => [d.lat, d.lng]));
      map.fitBounds(bounds.pad(isMobile() ? 0.04 : 0.08));
    }
    map.invalidateSize({ animate: false });
  }

  function setMobilePanel(panel) {
    const panels = document.querySelector('.panels');
    if (!panels) return;
    const next = panel || 'list';
    panels.dataset.activePanel = next;
    document.querySelectorAll('.mobile-tab').forEach((btn) => {
      const on = btn.dataset.panel === next;
      btn.classList.toggle('active', on);
      btn.setAttribute('aria-selected', on ? 'true' : 'false');
    });
  }

  function bindSheetUi() {
    els.browseFab?.addEventListener('click', () => {
      setMobilePanel('list');
      setSheetOpen(true);
    });
    els.sheetClose?.addEventListener('click', () => setSheetOpen(false));
    els.sheetBackdrop?.addEventListener('click', () => setSheetOpen(false));

    document.querySelectorAll('.mobile-tab').forEach((btn) => {
      btn.addEventListener('click', () => setMobilePanel(btn.dataset.panel));
    });

    let startY = 0;
    let dragging = false;
    els.sheetGrab?.addEventListener('touchstart', (e) => {
      if (!isMobile()) return;
      dragging = true;
      startY = e.touches[0].clientY;
    }, { passive: true });
    els.sheetGrab?.addEventListener('touchend', (e) => {
      if (!dragging) return;
      dragging = false;
      const endY = e.changedTouches[0]?.clientY ?? startY;
      if (endY - startY > 60) setSheetOpen(false);
    }, { passive: true });

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') setSheetOpen(false);
    });
  }

  function onViewportChange() {
    if (!isMobile()) setSheetOpen(false);
    for (const d of state.data?.developments || []) {
      const marker = state.markers.get(d.pathId);
      if (!marker) continue;
      marker.setIcon(markerIcon(d));
      marker.setPopupContent(() => popupHtml(d));
    }
    map.invalidateSize({ animate: false });
  }

  els.q.addEventListener('input', refresh);
  els.filterMicrosite?.addEventListener('change', refresh);
  els.filterHomesNi?.addEventListener('change', refresh);
  els.status.addEventListener('change', refresh);
  els.hideRedundant.addEventListener('change', refresh);

  els.paneList.addEventListener('click', (e) => {
    const card = e.target.closest('.card[data-id]');
    if (!card) return;
    selectDev(card.dataset.id, true);
  });

  bindSheetUi();
  mqMobile.addEventListener?.('change', onViewportChange);
  window.addEventListener('resize', () => {
    clearTimeout(onViewportChange._t);
    onViewportChange._t = setTimeout(onViewportChange, 120);
  });
  window.addEventListener('orientationchange', () => {
    setTimeout(() => map.invalidateSize({ animate: false }), 250);
  });

  boot().catch((err) => {
    console.error(err);
    els.paneList.innerHTML = `<p class="meta" style="padding:8px;color:#a13d2d">Failed to load data: ${escapeHtml(err.message || err)}</p>`;
  });
})();
