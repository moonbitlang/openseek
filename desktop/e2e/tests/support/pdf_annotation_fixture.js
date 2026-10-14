// Original PDF fixture: split heading, two-line paragraph and adjacent column.
// Tagged and untagged versions have exactly the same painted content.
export function annotationPdf(tagged) {
  const line = (id, x, y, text) => `/P <</MCID ${id}>> BDC BT /F1 20 Tf ${x} ${y} Td (${text}) Tj ET EMC`;
  const stream = [line(0, 72, 710, 'Hello'), line(1, 137, 710, 'world'),
    line(2, 72, 670, 'First paragraph line'), line(3, 72, 640, 'Second paragraph line'),
    line(4, 400, 710, 'Other column')].join('\n');
  const objects = [
    `<< /Type /Catalog /Pages 2 0 R ${tagged ? '/MarkInfo << /Marked true >> /StructTreeRoot 8 0 R' : ''} >>`,
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R ${tagged ? '/StructParents 0' : ''} >>`,
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
  return { data_base64: Buffer.from(pdf).toString('base64'), media_type: 'application/pdf', sig: `annotation:${tagged}` };
}
