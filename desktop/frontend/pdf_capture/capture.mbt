// Browser resources are scoped to one mounted PDF session. Only commands and
// serializable capture data cross this package boundary.

///|
extern "js" fn start_region(
  surface_id : String,
  hint : String,
  failure : String,
  too_large : String,
  done : (
    String,
    FixedArray[Int32],
    FixedArray[Double],
    FixedArray[Double],
    FixedArray[Double],
    FixedArray[Double],
    Int32,
    @js.Nullable[String],
    String,
  ) -> Unit,
  failed : (String) -> Unit,
  make_targets : (String, () -> Unit) -> @js.Value,
) -> Unit =
  #| (surfaceId, hint, failure, tooLarge, done, failed, makeTargets) => {
  #|   const host = document.getElementById(surfaceId);
  #|   const session = host?.__officeViewerPdf;
  #|   const container = host?.querySelector('.pdf-container');
  #|   if (!host || !container || !session?.alive) { failed(failure); return; }
  #|   if (host.__pdfRegionCapture) { host.__pdfRegionCapture(); return; }
  #|   const bounds = container.getBoundingClientRect();
  #|   const left = Math.max(0, bounds.left), top = Math.max(0, bounds.top);
  #|   const right = Math.min(innerWidth, bounds.right), bottom = Math.min(innerHeight, bounds.bottom);
  #|   if (right <= left || bottom <= top) { failed(failure); return; }
  #|   const abort = new AbortController();
  #|   const overlay = document.createElement('div');
  #|   overlay.className = 'pdf-region-capture';
  #|   overlay.setAttribute('role', 'region');
  #|   overlay.setAttribute('aria-label', hint);
  #|   Object.assign(overlay.style, { left: `${left}px`, top: `${top}px`, width: `${right-left}px`, height: `${bottom-top}px` });
  #|   const box = document.createElement('div');
  #|   box.className = 'pdf-region-capture-box';
  #|   box.hidden = true;
  #|   overlay.append(box);
  #|   let drag = null;
  #|   let lastPointer = null;
  #|   const targets = makeTargets(surfaceId, () => { if (!abort.signal.aborted) hover(); });
  #|   const observer = new MutationObserver(() => {
  #|     if (!host.isConnected || host.__officeViewerPdf !== session || !container.getClientRects().length) cleanup();
  #|   });
  #|   const resize = new ResizeObserver(() => {
  #|     const current = container.getBoundingClientRect();
  #|     if (current.left !== bounds.left || current.top !== bounds.top || current.width !== bounds.width || current.height !== bounds.height) cleanup();
  #|   });
  #|   const cleanup = () => {
  #|     abort.abort();
  #|     observer.disconnect();
  #|     resize.disconnect();
  #|     targets.dispose();
  #|     overlay.remove();
  #|     container.classList.remove('pdf-region-capturing');
  #|     session.abort.signal.removeEventListener('abort', cleanup);
  #|     for (const name of ['scalechanging', 'rotationchanging']) session.bus.off(name, cleanup);
  #|     if (host.__pdfRegionCapture === cleanup) delete host.__pdfRegionCapture;
  #|   };
  #|   host.__pdfRegionCapture = cleanup;
  #|   const listen = (target, event, listener, options = {}) => target.addEventListener(event, listener, { ...options, signal: abort.signal });
  #|   listen(document, 'keydown', event => {
  #|     if (event.key === 'Escape') { event.preventDefault(); event.stopImmediatePropagation(); cleanup(); }
  #|   }, { capture: true });
  #|   listen(container, 'contextmenu', event => { event.preventDefault(); cleanup(); });
  #|   // A change of geometry retires the selection rather than cropping old coordinates.
  #|   listen(container, 'scroll', () => {
  #|     if (drag && lastPointer) move(lastPointer); else hover();
  #|   });
  #|   listen(window, 'resize', cleanup);
  #|   listen(window, 'blur', cleanup);
  #|   session.abort.signal.addEventListener('abort', cleanup, { once: true });
  #|   for (const name of ['scalechanging', 'rotationchanging']) session.bus.on(name, cleanup);
  #|   const point = event => ({ x: Math.max(left, Math.min(right, event.clientX)) - bounds.left + container.scrollLeft, y: Math.max(top, Math.min(bottom, event.clientY)) - bounds.top + container.scrollTop });
  #|   const selection = end => ({ x: Math.min(drag.x, end.x), y: Math.min(drag.y, end.y), width: Math.abs(end.x-drag.x), height: Math.abs(end.y-drag.y) });
  #|   const paint = rect => Object.assign(box.style, {
  #|     left: `${rect.x - container.scrollLeft + bounds.left - left}px`,
  #|     top: `${rect.y - container.scrollTop + bounds.top - top}px`,
  #|     width: `${rect.width}px`, height: `${rect.height}px`
  #|   });
  #|   const inViewport = event => event.clientX >= left && event.clientX < Math.min(right, bounds.left+container.clientWidth) &&
  #|     event.clientY >= top && event.clientY < Math.min(bottom, bounds.top+container.clientHeight);
  #|   const contentRect = rect => ({ ...rect, x: rect.x-bounds.left+container.scrollLeft, y: rect.y-bounds.top+container.scrollTop });
  #|   const hover = () => {
  #|     if (drag) return;
  #|     const target = lastPointer && inViewport(lastPointer) ? targets.at(lastPointer.clientX, lastPointer.clientY) : null;
  #|     box.hidden = !target;
  #|     box.dataset.selectionKind = 'element';
  #|     if (target) paint(contentRect(target));
  #|   };
  #|   const move = event => {
  #|     lastPointer = event;
  #|     if (!drag) { hover(); return; }
  #|     if (drag.pointerId !== event.pointerId) return;
  #|     const end = point(event);
  #|     if (Math.hypot(end.x-drag.x, end.y-drag.y) >= 4) drag.selecting = true;
  #|     if (drag.selecting) {
  #|       box.hidden = false;
  #|       box.dataset.selectionKind = 'region';
  #|       paint(selection(end));
  #|     }
  #|   };
  #|   listen(container, 'pointerdown', event => {
  #|     if (event.button !== 0 || !event.isPrimary) return;
  #|     if (!inViewport(event)) return;
  #|     event.preventDefault(); event.stopPropagation();
  #|     lastPointer = event;
  #|     hover();
  #|     drag = { ...point(event), pointerId: event.pointerId, selecting: false,
  #|       target: targets.at(event.clientX, event.clientY) };
  #|     container.setPointerCapture(event.pointerId);
  #|   }, { capture: true });
  #|   listen(container, 'pointermove', move);
  #|   listen(container, 'pointerleave', () => {
  #|     if (!drag) { lastPointer = null; box.hidden = true; }
  #|   });
  #|   listen(container, 'pointercancel', cleanup);
  #|   listen(container, 'lostpointercapture', () => { if (drag) cleanup(); });
  #|   // Capture-mode clicks must not activate PDF links beneath the selection.
  #|   listen(container, 'click', event => { event.preventDefault(); event.stopPropagation(); }, { capture: true });
  #|   listen(container, 'pointerup', event => {
  #|     if (!drag || drag.pointerId !== event.pointerId) return;
  #|     event.preventDefault(); event.stopPropagation();
  #|     move(event);
  #|     const selected = drag.selecting ? selection(point(event)) : null;
  #|     const target = drag.target;
  #|     const rect = selected ? { ...selected, x: selected.x - container.scrollLeft + bounds.left, y: selected.y - container.scrollTop + bounds.top } : target;
  #|     const text = selected ? null : target?.text ?? null;
  #|     drag = null;
  #|     if (!rect) { hover(); return; }
  #|     // Prevent the synthetic click even after successful capture disposes listeners.
  #|     container.addEventListener('click', event => { event.preventDefault(); event.stopPropagation(); }, { capture: true, once: true, signal: session.abort.signal });
  #|     cleanup();
  #|     if (rect.width < 4 || rect.height < 4) return;
  #|     if (!session.alive || host.__officeViewerPdf !== session) return;
  #|     try {
  #|       const pieces = [];
  #|       for (const page of host.querySelectorAll('.pdfViewer .page')) {
  #|         const pageRect = page.getBoundingClientRect();
  #|         if (pageRect.right <= rect.x || pageRect.left >= rect.x+rect.width || pageRect.bottom <= rect.y || pageRect.top >= rect.y+rect.height) continue;
  #|         const view = session.viewer.getPageView(Number(page.dataset.pageNumber)-1);
  #|         const canvas = page.querySelector('.canvasWrapper canvas');
  #|         if (!canvas || view?.renderingState !== 3) throw new Error('Page is still rendering');
  #|         const b = canvas.getBoundingClientRect();
  #|         const x = Math.max(rect.x, b.left), y = Math.max(rect.y, b.top);
  #|         const width = Math.min(rect.x+rect.width, b.right)-x;
  #|         const height = Math.min(rect.y+rect.height, b.bottom)-y;
  #|         if (width > 0 && height > 0 && b.width > 0 && b.height > 0 && canvas.width > 0 && canvas.height > 0) {
  #|           pieces.push({ canvas, b, x, y, width, height, page: Number(page.dataset.pageNumber), pageRect, viewport: view.viewport });
  #|         }
  #|       }
  #|       if (!pieces.length) { failed(failure); return; }
  #|       // Canvas resolution includes PDF zoom and the display's pixel density.
  #|       const scale = Math.max(...pieces.map(p => Math.max(p.canvas.width/p.b.width, p.canvas.height/p.b.height)));
  #|       const width = Math.ceil(rect.width*scale), height = Math.ceil(rect.height*scale);
  #|       if (width*height > 16777216 || width > 16384 || height > 16384) { failed(tooLarge); return; }
  #|       const output = document.createElement('canvas');
  #|       output.width = width; output.height = height;
  #|       const ctx = output.getContext('2d');
  #|       if (!ctx) throw new Error('Canvas unavailable');
  #|       ctx.fillStyle = 'white'; ctx.fillRect(0, 0, width, height);
  #|       for (const p of pieces) {
  #|         const sx = p.canvas.width/p.b.width, sy = p.canvas.height/p.b.height;
  #|         ctx.drawImage(p.canvas, (p.x-p.b.left)*sx, (p.y-p.b.top)*sy, p.width*sx, p.height*sy,
  #|           (p.x-rect.x)*scale, (p.y-rect.y)*scale, p.width*scale, p.height*scale);
  #|       }
  #|       const url = output.toDataURL('image/png');
  #|       if (!url.startsWith('data:image/png;base64,')) throw new Error('PNG export failed');
  #|       if ((url.length-22)*3/4 > 5*1024*1024) { failed(tooLarge); return; }
  #|       const source = JSON.stringify({
  #|         document: session.identity,
  #|         regions: pieces.map(p => {
  #|           const v = p.viewport;
  #|           const a = v.convertToPdfPoint((p.x-p.b.left)*v.width/p.b.width, (p.y-p.b.top)*v.height/p.b.height);
  #|           const b = v.convertToPdfPoint((p.x+p.width-p.b.left)*v.width/p.b.width, (p.y+p.height-p.b.top)*v.height/p.b.height);
  #|           return { page: p.page, geometry: { space: 'pdf-page-user-space', unit: 'user-unit',
  #|             bbox: [Math.min(a[0],b[0]), Math.min(a[1],b[1]), Math.max(a[0],b[0]), Math.max(a[1],b[1])] } };
  #|         })
  #|       });
  #|       done(url, pieces.map(p => p.page),
  #|         pieces.map(p => (p.x-p.pageRect.left)/p.pageRect.width),
  #|         pieces.map(p => (p.y-p.pageRect.top)/p.pageRect.height),
  #|         pieces.map(p => p.width/p.pageRect.width),
  #|         pieces.map(p => p.height/p.pageRect.height), session.viewer.pagesRotation, text, source);
  #|     } catch (_) { failed(failure); }
  #|   }, { capture: true });
  #|   window.getSelection()?.removeAllRanges();
  #|   container.classList.add('pdf-region-capturing');
  #|   document.body.append(overlay);
  #|   observer.observe(document.body, { childList: true, subtree: true });
  #|   resize.observe(container);
  #| }

///|
extern "js" fn cancel_region(surface_id : String) -> Unit =
  #| id => document.getElementById(id)?.__pdfRegionCapture?.()

///|
pub fn start(
  surface_id : String,
  hint~ : String,
  failure~ : String,
  too_large~ : String,
  emit : @cmd.Emit[Result[Capture, String]],
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=@cmd.after_render, scheduler => {
    start_region(
      surface_id,
      hint,
      failure,
      too_large,
      (url, pages, xs, ys, widths, heights, rotation, text, source) => {
        let source = @json.parse(source) catch {
          _ => {
            scheduler.add(emit(Err(failure)))
            return
          }
        }
        let regions = Array::makei(pages.length(), index => {
          page: pages[index],
          x: xs[index],
          y: ys[index],
          width: widths[index],
          height: heights[index],
        })
        scheduler.add(
          emit(Ok({ url, source, regions, rotation, text: text.to_option(), })),
        )
      },
      message => scheduler.add(emit(Err(message))),
      create_targets,
    )
  })
}

///|
pub fn cancel(surface_id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => cancel_region(surface_id))
}
