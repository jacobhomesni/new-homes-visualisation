(() => {
  'use strict';

  const state = {
    data: null,
    markers: new Map(),
    activeId: null,
    layer: null,
  };

  const els = {
    statsTotal: document.getElementById('stat-total'),
    statsHomes: document.getElementById('stat-homes'),
    statsRedundant: document.getElementById('stat-redundant'),
    statsAgents: document.getElementById('stat-agents'),
    q: document.getElementById('q'),
    status: document.getElementById('status'),
    hideRedundant: document.getElementById('hide-redundant'),
    paneList: document.getElementById('pane-list'),
    paneAgents: document.getElementById('pane-agents'),
    paneDevelopers: document.getElementById('pane-developers'),
    meta: document.getElementById('meta'),
  };

  const map = L.map('map', {
    zoomControl: true,
    minZoom: 7,
    maxZoom: 14,
    attributionControl: true,
  }).setView([54.6, -6.5], 8);

  // Ocean backdrop — no basemap tiles / API keys
  map.getContainer().style.background =
    'radial-gradient(120% 90% at 50% 35%, #8ec8ea 0%, #6eb5e0 42%, #4f9dcb 100%)';
  map.attributionControl.setPrefix(false);
  map.attributionControl.addAttribution('County boundaries OSNI (OGL)');

  function markerIcon(redundant) {
    const color = redundant ? '#a13d2d' : '#1f7a4c';
    return L.divIcon({
      className: '',
      html: `<span style="display:block;width:14px;height:14px;border-radius:50%;background:${color};border:2px solid #fff;box-shadow:0 2px 6px rgba(10,30,18,.45), 0 1px 0 rgba(255,255,255,.35) inset"></span>`,
      iconSize: [14, 14],
      iconAnchor: [7, 7],
      popupAnchor: [0, -8],
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

  function logoImg(src, name, className = 'org-logo') {
    const href = resolveAsset(src);
    if (!href) return `<span class="${className} placeholder" aria-hidden="true"></span>`;
    return `<img class="${className}" src="${escapeAttr(href)}" alt="${escapeAttr(name || 'Logo')}" decoding="async" />`;
  }

  function orgCards(list, fallbackName) {
    const items = Array.isArray(list) ? list.filter((x) => x && (x.name || x.image || x.url)) : [];
    if (!items.length) {
      if (!fallbackName) return '';
      return `<div class="org-row"><div class="org-card"><span class="org-name">${escapeHtml(fallbackName)}</span></div></div>`;
    }
    return `<div class="org-row">${items.map((o) => {
      const name = o.name || '';
      const src = o.image || o.url || '';
      return `<div class="org-card">${logoImg(src, name)}<span class="org-name">${escapeHtml(name || '—')}</span></div>`;
    }).join('')}</div>`;
  }

  function logoByName() {
    const map = new Map();
    for (const d of state.data?.developments || []) {
      for (const o of [...(d.agentOrgs || []), ...(d.developerOrgs || [])]) {
        if (!o?.name || !o.image) continue;
        const key = String(o.name).trim().toLowerCase();
        if (key && !map.has(key)) map.set(key, o.image);
      }
    }
    return map;
  }

  function popupHtml(d) {
    const homes = d.homesAvailable == null ? '—' : d.homesAvailable;
    const status = d.status || (d.redundant ? 'Sale agreed / redundant' : 'Available');
    const developers = Array.isArray(d.developerOrgs) && d.developerOrgs.length
      ? d.developerOrgs
      : String(d.developers || '').split(';').map((n) => n.trim()).filter(Boolean).map((name) => ({ name }));
    const agents = Array.isArray(d.agentOrgs) && d.agentOrgs.length
      ? d.agentOrgs
      : String(d.agents || '').split(';').map((n) => n.trim()).filter(Boolean).map((name) => ({ name }));
    return `<div class="popup">
      <h3>${escapeHtml(d.name)}</h3>
      <p>${escapeHtml(d.address || '')}</p>
      <p><strong>${escapeHtml(String(homes))}</strong> homes available · ${escapeHtml(d.price || 'Price n/a')}</p>
      <p>${escapeHtml(status)}</p>
      <p class="org-label">Developer</p>
      ${orgCards(developers, d.developers || 'Developer n/a')}
      <p class="org-label">Agent</p>
      ${orgCards(agents, d.agents || 'Agent n/a')}
      ${d.url ? `<p><a href="${escapeAttr(d.url)}" target="_blank" rel="noopener">Open listing</a></p>` : ''}
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
    return (state.data.developments || []).filter((d) => {
      if (hideRedundant && d.redundant) return false;
      if (status && String(d.status || '') !== status) return false;
      if (!q) return true;
      const hay = [d.name, d.address, d.town, d.agents, d.developers, d.status, d.pathId]
        .map((x) => String(x || '').toLowerCase())
        .join(' ');
      return hay.includes(q);
    });
  }

  function renderStats(list) {
    const homes = list.reduce((n, d) => n + (Number(d.homesAvailable) || 0), 0);
    const redundant = list.filter((d) => d.redundant).length;
    els.statsTotal.textContent = String(list.length);
    els.statsHomes.textContent = String(homes);
    els.statsRedundant.textContent = String(redundant);
    els.statsAgents.textContent = String((state.data.agentTallies || []).length);
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
        <p class="meta">${escapeHtml(d.developers || '—')} · ${escapeHtml(d.agents || '—')}</p>
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
      const img = logos.get(String(r.name || '').trim().toLowerCase()) || '';
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
        marker = L.marker([d.lat, d.lng], { icon: markerIcon(!!d.redundant) });
        marker.bindPopup(() => popupHtml(d), { maxWidth: 320, minWidth: 220, autoPanPadding: [24, 24] });
        marker.on('click', () => selectDev(d.pathId, false));
        state.layer.addLayer(marker);
        state.markers.set(d.pathId, marker);
      }
    }
  }

  function selectDev(pathId, pan = true) {
    state.activeId = pathId;
    const d = (state.data.developments || []).find((x) => x.pathId === pathId);
    renderList(filtered());
    const marker = state.markers.get(pathId);
    if (marker) {
      marker.openPopup();
      if (pan && d && d.lat != null) map.panTo([d.lat, d.lng], { animate: true });
    }
  }

  function refresh() {
    const list = filtered();
    renderStats(list);
    renderList(list);
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

  async function loadCounties() {
    try {
      const res = await fetch('data/ni-counties.geojson');
      const geo = await res.json();

      // Soft land-mass shadow over the ocean
      L.geoJSON(geo, {
        interactive: false,
        style: {
          color: '#1a3f24',
          weight: 2,
          opacity: 1,
          fillColor: '#245530',
          fillOpacity: 1,
          className: 'county-poly-shadow',
        },
      }).addTo(map);

      // Light green fill + dark stroke drawn on top (inner rim inside each county)
      L.geoJSON(geo, {
        style: {
          color: '#1f4a2c',
          weight: 8,
          opacity: 1,
          fillColor: '#4f8f58',
          fillOpacity: 1,
          className: 'county-poly',
          lineJoin: 'round',
        },
        onEachFeature(feature, layer) {
          // paint-order must be set on the SVG path after Leaflet creates it
          const el = layer.getElement?.() || layer._path;
          if (el) el.setAttribute('paint-order', 'fill stroke');

          let name = feature.properties?.name;
          if (!name) return;
          if (/^londonderry$/i.test(name)) name = 'Derry/Londonderry';
          const latlng = countyLabelLatLng(feature, layer);
          if (!latlng) return;
          L.tooltip({
            permanent: true,
            direction: 'center',
            className: 'county-label',
            opacity: 0.95,
          })
            .setContent(name)
            .setLatLng(latlng)
            .addTo(map);
        },
      }).addTo(map);

      // White county border hairline on top
      L.geoJSON(geo, {
        interactive: false,
        style: {
          color: '#ffffff',
          weight: 1.4,
          opacity: 1,
          fill: false,
          fillOpacity: 0,
          className: 'county-poly-line',
          lineJoin: 'round',
        },
      }).addTo(map);
    } catch (err) {
      console.warn('County layer failed', err);
    }
  }

  async function boot() {
    state.layer = L.layerGroup().addTo(map);
    await loadCounties();

    const res = await fetch('data/developments.json');
    state.data = await res.json();
    fillStatusOptions(state.data.developments || []);
    renderTallies(els.paneAgents, state.data.agentTallies, 'agent');
    renderTallies(els.paneDevelopers, state.data.developerTallies, 'developer');
    els.meta.textContent = `${state.data.mappedCount || 0} mapped · ${String(state.data.generated || '').slice(0, 10)}`;
    refresh();

    const mapped = (state.data.developments || []).filter((d) => d.lat != null);
    if (mapped.length) {
      const bounds = L.latLngBounds(mapped.map((d) => [d.lat, d.lng]));
      map.fitBounds(bounds.pad(0.08));
    }
  }

  els.q.addEventListener('input', refresh);
  els.status.addEventListener('change', refresh);
  els.hideRedundant.addEventListener('change', refresh);

  els.paneList.addEventListener('click', (e) => {
    const card = e.target.closest('.card[data-id]');
    if (!card) return;
    selectDev(card.dataset.id, true);
  });

  boot().catch((err) => {
    console.error(err);
    els.paneList.innerHTML = `<p class="meta" style="padding:8px;color:#a13d2d">Failed to load data: ${escapeHtml(err.message || err)}</p>`;
  });
})();
