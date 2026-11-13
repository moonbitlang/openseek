///|
#derive(Eq)
pub(all) enum Failure {
  ReadAttachmentsFailed(String)
  InvalidDocumentSize(String)
  ImagesUnsupported
  ImageTooLarge(String)
  EmptyImage(String)
  UnsupportedFormat(String)
  Bridge(@interop.BridgeProblem)
}

///|
pub extend Failure with Eq::{equal, not_equal}

///|
pub fn Failure::text(self : Failure, locale : @i18n.Locale) -> String {
  let max_image_mib = @protocol.MaxImageBytes / 1024 / 1024
  match (locale, self) {
    (_, Bridge(problem)) => problem.text(locale)
    (English, ReadAttachmentsFailed(detail)) =>
      "Could not read attachments: \{detail}"
    (SimplifiedChinese, ReadAttachmentsFailed(detail)) =>
      "无法读取附件：\{detail}"
    (TraditionalChinese, ReadAttachmentsFailed(detail)) =>
      "無法讀取附件：\{detail}"
    (Japanese, ReadAttachmentsFailed(detail)) =>
      "添付ファイルを読み取れません：\{detail}"
    (Spanish, ReadAttachmentsFailed(detail)) =>
      "No se pudieron leer los archivos adjuntos: \{detail}"
    (English, InvalidDocumentSize(name)) =>
      "Documents must be nonempty and 20 MiB or smaller: \{name}"
    (SimplifiedChinese, InvalidDocumentSize(name)) =>
      "文档不能为空且不得超过 20 MiB：\{name}"
    (TraditionalChinese, InvalidDocumentSize(name)) =>
      "文件不能為空且不得超過 20 MiB：\{name}"
    (Japanese, InvalidDocumentSize(name)) =>
      "文書は空でなく、20 MiB 以下にしてください：\{name}"
    (Spanish, InvalidDocumentSize(name)) =>
      "Los documentos deben tener contenido y ocupar 20 MiB o menos: \{name}"
    (English, ImagesUnsupported) =>
      "This model does not support images. Choose PDF, DOCX, XLSX or PPTX documents."
    (SimplifiedChinese, ImagesUnsupported) =>
      "当前模型不支持图片，请选择 PDF、DOCX、XLSX 或 PPTX 文档。"
    (TraditionalChinese, ImagesUnsupported) =>
      "目前模型不支援圖片，請選擇 PDF、DOCX、XLSX 或 PPTX 文件。"
    (Japanese, ImagesUnsupported) =>
      "このモデルは画像をサポートしていません。PDF、DOCX、XLSX、PPTX の文書を選択してください。"
    (Spanish, ImagesUnsupported) =>
      "Este modelo no admite imágenes. Elige documentos PDF, DOCX, XLSX o PPTX."
    (English, ImageTooLarge(name)) =>
      "Each image must be \{max_image_mib} MiB or smaller: \{name}"
    (SimplifiedChinese, ImageTooLarge(name)) =>
      "每张图片不得超过 \{max_image_mib} MiB：\{name}"
    (TraditionalChinese, ImageTooLarge(name)) =>
      "每張圖片不得超過 \{max_image_mib} MiB：\{name}"
    (Japanese, ImageTooLarge(name)) =>
      "画像は 1 枚あたり \{max_image_mib} MiB 以下にしてください：\{name}"
    (Spanish, ImageTooLarge(name)) =>
      "Cada imagen debe ocupar \{max_image_mib} MiB o menos: \{name}"
    (English, EmptyImage(name)) => "Image is empty: \{name}"
    (SimplifiedChinese, EmptyImage(name)) => "图片为空：\{name}"
    (TraditionalChinese, EmptyImage(name)) => "圖片為空：\{name}"
    (Japanese, EmptyImage(name)) => "画像が空です：\{name}"
    (Spanish, EmptyImage(name)) => "La imagen está vacía: \{name}"
    (English, UnsupportedFormat(name)) =>
      "Choose PNG, JPEG, WebP or GIF images, or PDF, DOCX, XLSX or PPTX documents: \{name}"
    (SimplifiedChinese, UnsupportedFormat(name)) =>
      "请选择 PNG、JPEG、WebP、GIF 图片或 PDF、DOCX、XLSX、PPTX 文档：\{name}"
    (TraditionalChinese, UnsupportedFormat(name)) =>
      "請選擇 PNG、JPEG、WebP、GIF 圖片或 PDF、DOCX、XLSX、PPTX 文件：\{name}"
    (Japanese, UnsupportedFormat(name)) =>
      "PNG、JPEG、WebP、GIF の画像、または PDF、DOCX、XLSX、PPTX の文書を選択してください：\{name}"
    (Spanish, UnsupportedFormat(name)) =>
      "Elige imágenes PNG, JPEG, WebP o GIF, o documentos PDF, DOCX, XLSX o PPTX: \{name}"
  }
}
