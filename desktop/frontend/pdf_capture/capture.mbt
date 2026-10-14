// Browser resources are scoped to one mounted PDF session. Only commands and
// serializable capture data cross this package boundary.

///|
extern "js" fn start_region(
  surface_id : String,
  hint : String,
  failure : String,
  too_large : String,
  unsupported_annotation : String,
  done : (String, String, FixedArray[@js.Value], Int32, @js.Nullable[String]) -> Unit,
  failed : (String) -> Unit,
  make_targets : (String, () -> Unit) -> @js.Value,
  geometry : @js.Value,
) -> Unit =
  #| (surfaceId, hint, failure, tooLarge, unsupportedAnnotation, done, failed, makeTargets, geometry) => {
  #|   const host = document.getElementById(surfaceId);
  #|   const session = host?.__officeViewerPdf;
  #|   const container = host?.querySelector('.pdf-container');
  #|   if (!host || !container || !session?.alive) { failed(failure); return; }
  #|   if (host.__pdfRegionCapture) return;
  #|   const bounds = container.getBoundingClientRect();
  #|   const viewport = geometry.viewport(bounds, innerWidth, innerHeight);
  #|   if (!viewport) { failed(failure); return; }
  #|   const abort = new AbortController();
  #|   const overlay = document.createElement('div');
  #|   overlay.className = 'pdf-region-capture';
  #|   overlay.setAttribute('role', 'region');
  #|   overlay.setAttribute('aria-label', hint);
  #|   Object.assign(overlay.style, { left: `${viewport.x}px`, top: `${viewport.y}px`, width: `${viewport.width}px`, height: `${viewport.height}px` });
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
  #|   const point = event => geometry.point(event, bounds, viewport, container);
  #|   const paint = rect => {
  #|     const p = geometry.paintRect(rect, bounds, viewport, container);
  #|     Object.assign(box.style, { left: `${p.x}px`, top: `${p.y}px`, width: `${p.width}px`, height: `${p.height}px` });
  #|   };
  #|   const inViewport = event => geometry.inViewport(event, bounds, viewport, container);
  #|   const contentRect = rect => geometry.contentRect(rect, bounds, container, false);
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
  #|     const selected = geometry.selection(drag, end, drag.selecting);
  #|     if (selected) {
  #|       drag.selecting = true;
  #|       box.hidden = false;
  #|       box.dataset.selectionKind = 'region';
  #|       paint(selected);
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
  #|     const selected = drag.selecting ? geometry.selection(drag, point(event), true) : null;
  #|     const target = drag.target;
  #|     const rect = selected ? geometry.contentRect(selected, bounds, container, true) : target;
  #|     const text = selected ? null : target?.text ?? null;
  #|     drag = null;
  #|     if (!rect) { hover(); return; }
  #|     // Prevent the synthetic click even after successful capture disposes listeners.
  #|     container.addEventListener('click', event => { event.preventDefault(); event.stopPropagation(); }, { capture: true, once: true, signal: session.abort.signal });
  #|     cleanup();
  #|     if (!geometry.validCapture(rect)) return;
  #|     if (!session.alive || host.__officeViewerPdf !== session) return;
  #|     try {
  #|       const pieces = [];
  #|       for (const page of host.querySelectorAll('.pdfViewer .page')) {
  #|         const pageRect = page.getBoundingClientRect();
  #|         if (!geometry.intersect(pageRect, rect)) continue;
  #|         const view = session.viewer.getPageView(Number(page.dataset.pageNumber)-1);
  #|         const canvas = page.querySelector('.canvasWrapper canvas');
  #|         if (!canvas || view?.renderingState !== 3) throw new Error('Page is still rendering');
  #|         const b = canvas.getBoundingClientRect();
  #|         const crop = geometry.intersect(rect, b);
  #|         if (crop && canvas.width > 0 && canvas.height > 0) {
  #|           // The viewer disables editable forms and XFA. Some documents still
  #|           // use HTML-only field fallbacks or popups: never silently omit them.
  #|           for (const element of page.querySelectorAll('.textWidgetAnnotation > div:not([hidden]), .annotationLayer .popup, .annotationLayer .mediaAnnotation, .xfaLayer')) {
  #|             const r = element.getBoundingClientRect();
  #|             if (getComputedStyle(element).visibility === 'visible' && geometry.intersect(r, crop)) { failed(unsupportedAnnotation); return; }
  #|           }
  #|           pieces.push({ canvas, annotations: page.querySelectorAll('.annotationLayer canvas, .annotationLayer img'), b, ...crop, page: Number(page.dataset.pageNumber), pageRect, viewport: view.viewport });
  #|         }
  #|       }
  #|       if (!pieces.length) { failed(failure); return; }
  #|       // Canvas resolution includes PDF zoom and the display's pixel density.
  #|       const size = geometry.output(rect, pieces);
  #|       if (!size) { failed(tooLarge); return; }
  #|       const { scale, width, height } = size;
  #|       const output = document.createElement('canvas');
  #|       output.width = width; output.height = height;
  #|       const ctx = output.getContext('2d');
  #|       if (!ctx) throw new Error('Canvas unavailable');
  #|       ctx.fillStyle = 'white'; ctx.fillRect(0, 0, width, height);
  #|       for (const p of pieces) {
  #|         const drawing = geometry.drawing(p, rect, scale);
  #|         const src = drawing.source, dst = drawing.destination, v = drawing.viewport;
  #|         ctx.drawImage(p.canvas, src.x, src.y, src.width, src.height, dst.x, dst.y, dst.width, dst.height);
  #|         p.pdfStart = p.viewport.convertToPdfPoint(v.x, v.y);
  #|         p.pdfEnd = p.viewport.convertToPdfPoint(v.x + v.width, v.y + v.height);
  #|         // PDF.js paints read-only widgets and some rotated annotations on
  #|         // separate canvases. Composite their displayed pixels, including
  #|         // the layer rotation and any annotation-specific counter-rotation.
  #|         for (const bitmap of p.annotations) {
  #|           const b = bitmap.getBoundingClientRect(), style = getComputedStyle(bitmap);
  #|           if (!b.width || !b.height || style.visibility !== 'visible') continue;
  #|           if (!geometry.intersect(b, p)) continue;
  #|           const pixelWidth = bitmap instanceof HTMLImageElement ? bitmap.naturalWidth : bitmap.width;
  #|           const pixelHeight = bitmap instanceof HTMLImageElement ? bitmap.naturalHeight : bitmap.height;
  #|           if (!pixelWidth || !pixelHeight) throw new Error('Annotation is still rendering');
  #|           const layers = [];
  #|           for (let node = bitmap; node; node = node.parentElement) {
  #|             const css = getComputedStyle(node);
  #|             layers.push({ matrix: css.transform === 'none' ? new DOMMatrix() : new DOMMatrix(css.transform), opacity: Number(css.opacity) });
  #|           }
  #|           const placement = geometry.bitmap(layers, b,
  #|             { x: parseFloat(style.width), y: parseFloat(style.height) },
  #|             { x: pixelWidth, y: pixelHeight }, rect, scale);
  #|           ctx.save();
  #|           ctx.beginPath();
  #|           ctx.rect(dst.x, dst.y, dst.width, dst.height);
  #|           ctx.clip();
  #|           ctx.globalAlpha = placement.opacity;
  #|           ctx.filter = style.filter;
  #|           ctx.setTransform(placement.a, placement.b, placement.c, placement.d, placement.x, placement.y);
  #|           ctx.drawImage(bitmap, 0, 0);
  #|           ctx.restore();
  #|         }
  #|       }
  #|       const url = output.toDataURL('image/png');
  #|       done(url, JSON.stringify(session.identity), pieces, session.viewer.pagesRotation, text);
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
  unsupported_annotation~ : String,
  emit : @cmd.Emit[Result[Capture, String]],
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=@cmd.after_render, scheduler => {
    start_region(
      surface_id,
      hint,
      failure,
      too_large,
      unsupported_annotation,
      (url, identity, pieces, rotation, text) => {
        let result = finish_capture(
          url,
          identity,
          pieces,
          rotation,
          text.to_option(),
          failure~,
          too_large~,
        )
        scheduler.add(emit(result))
      },
      message => scheduler.add(emit(Err(message))),
      (id, changed) => create_targets(id, changed, index_page),
      geometry_bridge(),
    )
  })
}

///|
pub fn cancel(surface_id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => cancel_region(surface_id))
}
