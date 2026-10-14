// Original PDF fixture: split heading, two-line paragraph and adjacent column.
// Tagged and untagged versions have exactly the same painted content.
export function annotationPdf(tagged, rotation = 0) {
  const line = (id, x, y, text) => `/P <</MCID ${id}>> BDC BT /F1 20 Tf ${x} ${y} Td (${text}) Tj ET EMC`;
  const stream = [line(0, 72, 710, 'Hello'), line(1, 137, 710, 'world'),
    line(2, 72, 670, 'First paragraph line'), line(3, 72, 640, 'Second paragraph line'),
    line(4, 400, 710, 'Other column')].join('\n');
  const objects = [
    `<< /Type /Catalog /Pages 2 0 R ${tagged ? '/MarkInfo << /Marked true >> /StructTreeRoot 8 0 R' : ''} >>`,
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R /Rotate ${rotation} ${tagged ? '/StructParents 0' : ''} >>`,
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 7 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    `<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`,
    '<< /Length 0 >>\nstream\n\nendstream',
    '<< /Type /StructTreeRoot /K [9 0 R 10 0 R 11 0 R] /ParentTree 12 0 R >>',
    '<< /Type /StructElem /S /H1 /P 8 0 R /Pg 3 0 R /K [0 1] >>',
    '<< /Type /StructElem /S /P /P 8 0 R /Pg 3 0 R /K [2 3] >>',
    '<< /Type /StructElem /S /P /P 8 0 R /Pg 3 0 R /K 4 >>',
    '<< /Nums [0 [9 0 R 9 0 R 10 0 R 10 0 R 11 0 R]] >>',
  ];
  return pdfFixture(objects, `annotation:${tagged}:${rotation}`);
}

// A read-only field is painted on a separate annotation canvas by PDF.js.
export function formPdf({ readOnly = true, appearance = true, noRotate = false, note = false, kind = 'text' } = {}) {
  const stream = 'q 1 0 0 rg 0 0 240 40 re f 0 0 0 rg BT /F1 20 Tf 10 10 Td (Stored field value) Tj ET Q';
  const fields = {
    text: `/FT /Tx /V (Stored field value) /Ff ${readOnly ? 1 : 0}`,
    pushButton: '/FT /Btn /Ff 65536 /MK << /BC [1 0 0] >> /BS << /W 3 /S /S >> /A << /S /URI /URI (https://example.com) >>',
    checkbox: '/FT /Btn /Ff 1 /V /Yes /AS /Yes',
    radio: '/FT /Btn /Ff 32769 /V /Yes /AS /Yes',
    choice: '/FT /Ch /Ff 1 /V (Stored field value) /Opt [(Stored field value)]',
  };
  const field = fields[kind];
  if (!field) throw new Error(`Unknown form fixture: ${kind}`);
  const normal = kind === 'checkbox' || kind === 'radio' ? '<< /Yes 7 0 R >>' : '7 0 R';
  return pdfFixture([
    '<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [6 0 R] /DR << /Font << /F1 5 0 R >> >> /DA (/F1 20 Tf 0 g) >> >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Annots [6 0 R ${note ? '8 0 R' : ''}] >>`,
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    `<< /Type /Annot /Subtype /Widget ${field} /T (name) /F ${noRotate ? 20 : 4} /Rect [72 650 312 690] /P 3 0 R /DA (/F1 20 Tf 0 g) ${appearance ? `/AP << /N ${normal} >>` : ''} >>`,
    `<< /Type /XObject /Subtype /Form /BBox [0 0 240 40] /Resources << /Font << /F1 5 0 R >> >> /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`,
    note === 'attachment'
      ? '<< /Type /Annot /Subtype /FileAttachment /Rect [350 650 380 680] /P 3 0 R /Name /Paperclip /FS 9 0 R /ca 0.5 /F 4 >>'
      : '<< /Type /Annot /Subtype /Text /Rect [350 650 380 680] /P 3 0 R /Name /Note /Contents (Review this note) /F 4 >>',
    '<< /Type /Filespec /F (demo.txt) /EF << /F 10 0 R >> >>',
    '<< /Type /EmbeddedFile /Length 4 >>\nstream\ndemo\nendstream',
  ], `form:${readOnly}:${appearance}:${noRotate}:${note}:${kind}`);
}

// No /AP: PDF.js must synthesize the visible bitmap appearance. The SVG in
// the annotation layer is a separate transparent hit area for these markups.
export function markupPdf(kind) {
  const shapes = {
    Line: '/L [80 655 300 720]',
    Square: '',
    Circle: '',
    PolyLine: '/Vertices [80 655 190 720 300 655]',
    Polygon: '/Vertices [80 655 190 720 300 655 80 655]',
    Ink: '/InkList [[80 655 190 720 300 655]]',
  };
  if (!Object.hasOwn(shapes, kind)) throw new Error(`Unknown markup fixture: ${kind}`);
  return pdfFixture([
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [5 0 R] >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>',
    `<< /Type /Annot /Subtype /${kind} /Rect [72 645 312 730] /P 3 0 R /F 4 /C [1 0 0] /BS << /W 4 /S /S >> ${shapes[kind]} >>`,
  ], `markup:${kind}`);
}

function pdfFixture(objects, sig) {
  let pdf = '%PDF-1.7\n';
  const offsets = [0];
  objects.forEach((object, i) => {
    offsets.push(Buffer.byteLength(pdf));
    pdf += `${i+1} 0 obj\n${object}\nendobj\n`;
  });
  const xref = Buffer.byteLength(pdf);
  pdf += `xref\n0 ${offsets.length}\n0000000000 65535 f \n`;
  pdf += offsets.slice(1).map(offset => `${String(offset).padStart(10, '0')} 00000 n \n`).join('');
  pdf += `trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return { data_base64: Buffer.from(pdf).toString('base64'), media_type: 'application/pdf', sig };
}
