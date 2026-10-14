///|
/// Index rendered text once per page. Rectangles stay page-relative during scroll.
/// This private browser object never escapes the capture command's lifetime.
extern "js" fn create_targets(
  surface_id : String,
  changed : () -> Unit,
) -> @js.Value =
  #| (surfaceId, changed) => {
  #|   const host = document.getElementById(surfaceId), session = host.__officeViewerPdf;
  #|   const pages = new Map();
  #|   let alive = true;
  #|   const union = entries => {
  #|     const x = Math.min(...entries.map(e => e.x)), y = Math.min(...entries.map(e => e.y));
  #|     return { x, y, width: Math.max(...entries.map(e => e.x+e.width))-x,
  #|       height: Math.max(...entries.map(e => e.y+e.height))-y };
  #|   };
  #|   const prepare = page => {
  #|     if (pages.has(page)) return pages.get(page);
  #|     const slot = { targets: [] };
  #|     pages.set(page, slot);
  #|     const number = Number(page.dataset.pageNumber);
  #|     (async () => {
  #|       const mapping = await session.mapping(number);
  #|       if (!mapping) { if (pages.get(page) === slot) pages.delete(page); return; }
  #|       const tree = await mapping.data.page.getStructTree().catch(() => null);
  #|       if (!alive || !page.isConnected || pages.get(page) !== slot) return;
  #|       const p = page.getBoundingClientRect();
  #|       const entries = mapping.entries.filter(e => e.item.str.trim() && e.div.isConnected).map(e => {
  #|         const b = e.div.getBoundingClientRect();
  #|         const angle = Math.atan2(e.item.transform[1], e.item.transform[0]) + session.viewer.pagesRotation*Math.PI/180;
  #|         return { ...e, x: b.left-p.left, y: b.top-p.top, width: b.width, height: b.height,
  #|           vertical: Math.abs(Math.sin(angle)) > Math.SQRT1_2 };
  #|       }).filter(e => e.width > 0 && e.height > 0);
  #|       const groups = [], assigned = new Set();
  #|       // Use the smallest meaningful tagged block. A shared role name alone
  #|       // cannot identify a paragraph: different paragraphs may have that role.
  #|       const walk = node => {
  #|         const ids = new Set(node.type === 'content' ? [node.id] : []);
  #|         for (const child of node.children || []) for (const id of walk(child)) ids.add(id);
  #|         if (/^(H[1-6]?|P|LI|Caption|TD|TH|BlockQuote)$/.test(node.role)) {
  #|           const members = entries.filter(e => ids.has(e.markedId) && !assigned.has(e));
  #|           if (members.length) { groups.push(members); members.forEach(e => assigned.add(e)); }
  #|         }
  #|         return ids;
  #|       };
  #|       if (tree) walk(tree);
  #|       // Untagged PDFs expose text runs, not logical elements. Join only
  #|       // nearby runs on the same visual line with matching font and size.
  #|       const lines = [];
  #|       for (const e of entries.filter(e => !assigned.has(e)).sort((a,b) =>
  #|         a.vertical === b.vertical ? (a.vertical ? a.x-b.x || a.y-b.y : a.y-b.y || a.x-b.x) : Number(a.vertical)-Number(b.vertical))) {
  #|         const size = e.vertical ? e.width : e.height;
  #|         const cross = e.vertical ? e.x+e.width/2 : e.y+e.height/2;
  #|         const along = e.vertical ? e.y : e.x;
  #|         const line = lines.find(line => {
  #|           const last = line.at(-1), lastSize = last.vertical ? last.width : last.height;
  #|           const lastCross = last.vertical ? last.x+last.width/2 : last.y+last.height/2;
  #|           const end = last.vertical ? last.y+last.height : last.x+last.width;
  #|           return e.vertical === last.vertical && e.item.fontName === last.item.fontName &&
  #|             size/lastSize >= 0.8 && size/lastSize <= 1.25 && Math.abs(cross-lastCross) <= size*0.25 &&
  #|             along-end >= -size*0.25 && along-end <= size*1.5;
  #|         });
  #|         if (line) line.push(e); else lines.push([e]);
  #|       }
  #|       groups.push(...lines);
  #|       slot.targets = groups.map(members => {
  #|         const b = union(members), ordered = [...members].sort((a,b) => a.index-b.index);
  #|         let text = '';
  #|         ordered.forEach((e,i) => {
  #|           if (i && text && !/\s$/.test(text) && !/^\s/.test(e.item.str)) {
  #|             const prev = ordered[i-1], size = e.vertical ? e.width : e.height;
  #|             const cross = e.vertical ? Math.abs(e.x-prev.x) : Math.abs(e.y-prev.y);
  #|             const gap = e.vertical ? e.y-prev.y-prev.height : e.x-prev.x-prev.width;
  #|             if (cross > size/2) text += '\n';
  #|             else if (gap > size*0.15) text += ' ';
  #|           }
  #|           text += e.item.str + (e.item.hasEOL ? '\n' : '');
  #|         });
  #|         const x = Math.max(0, b.x-2), y = Math.max(0, b.y-2);
  #|         return { x, y, width: Math.min(p.width,b.x+b.width+2)-x,
  #|           height: Math.min(p.height,b.y+b.height+2)-y, text: text.trim() };
  #|       });
  #|       changed();
  #|     })().catch(() => { if (pages.get(page) === slot) pages.delete(page); });
  #|     return slot;
  #|   };
  #|   const rendered = event => {
  #|     const page = host.querySelector(`.page[data-page-number='${event.pageNumber}']`);
  #|     if (page) { pages.delete(page); prepare(page); }
  #|   };
  #|   session.bus.on('textlayerrendered', rendered);
  #|   for (const layer of host.querySelectorAll('.textLayer')) {
  #|     const page = layer.closest('.page');
  #|     if (page && layer.querySelector('span')) prepare(page);
  #|   }
  #|   return {
  #|     at(x,y) {
  #|       // Let browser hit testing find the page, without measuring every page
  #|       // of a long document on each pointer movement.
  #|       const page = document.elementFromPoint(x,y)?.closest('.page');
  #|       if (!page || !host.contains(page)) return null;
  #|       const p = page.getBoundingClientRect();
  #|       const candidates = prepare(page).targets.filter(b =>
  #|         x >= p.left+b.x && x <= p.left+b.x+b.width && y >= p.top+b.y && y <= p.top+b.y+b.height);
  #|       const target = candidates.sort((a,b) => a.width*a.height-b.width*b.height)[0];
  #|       return target ? { ...target, x: p.left+target.x, y: p.top+target.y } : null;
  #|     },
  #|     dispose() { alive = false; pages.clear(); session.bus.off('textlayerrendered', rendered); }
  #|   };
  #| }
