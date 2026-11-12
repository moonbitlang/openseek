///|
#derive(Eq)
pub(all) enum AttachmentFailure {
  Cloud(@cloud_client.Failure)
  Bridge(@interop.BridgeProblem)
  Image(@image_input.Failure)
  WorkspaceRequired
  ImagesUnsupported
}

///|
pub extend AttachmentFailure with Eq::{equal, not_equal}

///|
fn AttachmentFailure::text(
  self : AttachmentFailure,
  locale : @i18n.Locale,
) -> String {
  match self {
    Cloud(failure) => failure.text(locale)
    Bridge(problem) => problem.text(locale)
    Image(failure) => failure.text(locale)
    ImagesUnsupported => @image_input.Failure::ImagesUnsupported.text(locale)
    WorkspaceRequired =>
      match locale {
        English => "Choose a workspace before attaching documents"
        SimplifiedChinese => "请先选择工作区，再添加文档附件"
        TraditionalChinese => "請先選擇工作區，再新增文件附件"
        Japanese =>
          "ドキュメントを添付する前にワークスペースを選択してください"
        Spanish => "Elige un espacio de trabajo antes de adjuntar documentos"
      }
  }
}
