// Small, original documents with distinct page content and explicit breaks.
// They exercise actual Office parsing and PDF.js rendering, not mock surfaces.
function storedZip(files) {
  const locals = [], directory = [];
  let offset = 0;
  for (const [name, text] of Object.entries(files)) {
    const filename = Buffer.from(name), data = Buffer.from(text);
    let crc = 0xffffffff;
    for (const byte of data) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
    }
    crc = (crc ^ 0xffffffff) >>> 0;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50); local.writeUInt16LE(20, 4);
    local.writeUInt32LE(crc, 14); local.writeUInt32LE(data.length, 18);
    local.writeUInt32LE(data.length, 22); local.writeUInt16LE(filename.length, 26);
    locals.push(local, filename, data);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6);
    central.writeUInt32LE(crc, 16); central.writeUInt32LE(data.length, 20);
    central.writeUInt32LE(data.length, 24); central.writeUInt16LE(filename.length, 28);
    central.writeUInt32LE(offset, 42);
    directory.push(central, filename);
    offset += local.length + filename.length + data.length;
  }
  const index = Buffer.concat(directory), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50); end.writeUInt16LE(directory.length / 2, 8);
  end.writeUInt16LE(directory.length / 2, 10); end.writeUInt32LE(index.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, index, end]);
}

export function pagedWord(count = 6) {
  const body = Array.from({ length: count }, (_, i) => `
    <w:p><w:pPr>${i ? '<w:pageBreakBefore/>' : ''}<w:spacing w:after="300"/></w:pPr>
      <w:r><w:rPr><w:color w:val="235D86"/><w:b/><w:sz w:val="40"/></w:rPr><w:t>Document page ${i + 1}</w:t></w:r></w:p>
    <w:p><w:r><w:t>Original demonstration content for page ${i + 1}.</w:t></w:r></w:p>
    <w:p><w:r><w:t>Use the page thumbnails to navigate, or scroll the document to follow the active page.</w:t></w:r></w:p>`).join('');
  const data = storedZip({
    '[Content_Types].xml': '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
    '_rels/.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/document.xml': `<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>${body}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr></w:body></w:document>`,
  });
  return { data_base64: data.toString('base64'), media_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', sig: `pages:word:${count}` };
}

export function pagedPdf(count = 6, landscape = false) {
  const width = landscape ? 792 : 612, height = landscape ? 446 : 792;
  const kids = Array.from({ length: count }, (_, i) => `${4 + i * 2} 0 R`).join(' ');
  const objects = ['<< /Type /Catalog /Pages 2 0 R >>', `<< /Type /Pages /Kids [${kids}] /Count ${count} >>`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'];
  for (let i = 0; i < count; i++) {
    const stream = `q 0.12 0.36 0.48 rg 0 ${height - 132} ${width} 132 re f 1 1 1 rg BT /F1 32 Tf 50 ${height - 77} Td (Document page ${i + 1}) Tj ET 0 0 0 rg BT /F1 16 Tf 50 ${height - 182} Td (Original demonstration content for page ${i + 1}.) Tj ET Q`;
    objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${width} ${height}] /Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + i * 2} 0 R >>`,
      `<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`);
  }
  let pdf = '%PDF-1.7\n';
  const offsets = [0];
  objects.forEach((object, i) => { offsets.push(Buffer.byteLength(pdf)); pdf += `${i + 1} 0 obj\n${object}\nendobj\n`; });
  const xref = Buffer.byteLength(pdf);
  pdf += `xref\n0 ${offsets.length}\n0000000000 65535 f \n` + offsets.slice(1).map(offset => `${String(offset).padStart(10, '0')} 00000 n \n`).join('');
  pdf += `trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return { data_base64: Buffer.from(pdf).toString('base64'), media_type: 'application/pdf', sig: `pages:pdf:${count}` };
}
