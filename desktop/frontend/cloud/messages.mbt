///|
#derive(Eq)
pub(all) enum Notice {
  Failure(@cloud_client.Failure)
  EngineDetail(String)
  OperationRejected(String)
  ControlRejected(String)
  AnswerRejected(String)
  QuestionAnswerFailed(@cloud_client.Failure)
  QuestionAnswerDetail(String)
  SettingsSaveRaced
  DeleteWhileGenerating
  AdditionalInputNotApplied
}

///|
pub extend Notice with Eq::{equal, not_equal}

///|
pub fn Notice::text(self : Notice, locale : @i18n.Locale) -> String {
  match (locale, self) {
    (_, Failure(failure)) => failure.text(locale)
    (_, EngineDetail(detail)) => detail
    (English, OperationRejected(reason)) =>
      "Cloud rejected the operation: \{reason}"
    (SimplifiedChinese, OperationRejected(reason)) =>
      "云端拒绝了此操作：\{reason}"
    (TraditionalChinese, OperationRejected(reason)) =>
      "雲端拒絕了此操作：\{reason}"
    (Japanese, OperationRejected(reason)) =>
      "クラウドが操作を拒否しました：\{reason}"
    (Spanish, OperationRejected(reason)) =>
      "Cloud rechazó la operación: \{reason}"
    (English, ControlRejected(reason)) =>
      "Cloud rejected the operation: \{reason}."
    (SimplifiedChinese, ControlRejected(reason)) =>
      "云端拒绝了此操作：\{reason}。"
    (TraditionalChinese, ControlRejected(reason)) =>
      "雲端拒絕了此操作：\{reason}。"
    (Japanese, ControlRejected(reason)) =>
      "クラウドが操作を拒否しました：\{reason}。"
    (Spanish, ControlRejected(reason)) =>
      "Cloud rechazó la operación: \{reason}."
    (English, AnswerRejected(reason)) =>
      "Cloud did not accept the answer: \{reason}."
    (SimplifiedChinese, AnswerRejected(reason)) =>
      "云端未接受此答复：\{reason}。"
    (TraditionalChinese, AnswerRejected(reason)) =>
      "雲端未接受此答覆：\{reason}。"
    (Japanese, AnswerRejected(reason)) =>
      "クラウドが回答を受け付けませんでした：\{reason}。"
    (Spanish, AnswerRejected(reason)) =>
      "Cloud no aceptó la respuesta: \{reason}."
    (English, QuestionAnswerFailed(failure)) =>
      "Could not deliver question answer: \{failure.text(locale)}"
    (SimplifiedChinese, QuestionAnswerFailed(failure)) =>
      "无法发送问题答复：\{failure.text(locale)}"
    (TraditionalChinese, QuestionAnswerFailed(failure)) =>
      "無法傳送問題答覆：\{failure.text(locale)}"
    (Japanese, QuestionAnswerFailed(failure)) =>
      "質問への回答を送信できませんでした：\{failure.text(locale)}"
    (Spanish, QuestionAnswerFailed(failure)) =>
      "No se pudo enviar la respuesta a la pregunta: \{failure.text(locale)}"
    (English, QuestionAnswerDetail(detail)) =>
      "Could not deliver question answer: \{detail}"
    (SimplifiedChinese, QuestionAnswerDetail(detail)) =>
      "无法发送问题答复：\{detail}"
    (TraditionalChinese, QuestionAnswerDetail(detail)) =>
      "無法傳送問題答覆：\{detail}"
    (Japanese, QuestionAnswerDetail(detail)) =>
      "質問への回答を送信できませんでした：\{detail}"
    (Spanish, QuestionAnswerDetail(detail)) =>
      "No se pudo enviar la respuesta a la pregunta: \{detail}"
    (English, SettingsSaveRaced) =>
      "The session became busy before the settings were saved. Choose them again when it is idle."
    (SimplifiedChinese, SettingsSaveRaced) =>
      "会话设置保存前已有任务开始。请在会话空闲后重新选择。"
    (TraditionalChinese, SettingsSaveRaced) =>
      "對話設定儲存前已有工作開始。請在對話閒置後重新選擇。"
    (Japanese, SettingsSaveRaced) =>
      "設定を保存する前にセッションで処理が開始されました。処理が終わってからもう一度選択してください。"
    (Spanish, SettingsSaveRaced) =>
      "La sesión pasó a estar ocupada antes de guardar la configuración. Vuelve a elegirla cuando esté inactiva."
    (English, DeleteWhileGenerating) =>
      "This conversation is generating. Try deleting it after it finishes."
    (SimplifiedChinese, DeleteWhileGenerating) =>
      "此对话正在生成回复。请在生成结束后重试删除。"
    (TraditionalChinese, DeleteWhileGenerating) =>
      "此對話正在產生回覆。請在產生作業結束後重試刪除。"
    (Japanese, DeleteWhileGenerating) =>
      "この会話は生成中です。生成終了後に削除を再試行してください。"
    (Spanish, DeleteWhileGenerating) =>
      "Esta conversación está generando una respuesta. Intenta eliminarla cuando termine."
    (English, AdditionalInputNotApplied) =>
      "The additional input was not applied."
    (SimplifiedChinese, AdditionalInputNotApplied) =>
      "补充输入未被应用。"
    (TraditionalChinese, AdditionalInputNotApplied) =>
      "補充輸入未套用。"
    (Japanese, AdditionalInputNotApplied) =>
      "追加入力は適用されませんでした。"
    (Spanish, AdditionalInputNotApplied) =>
      "No se aplicó la entrada adicional."
  }
}
