///|
priv enum Message {
  ReviewSelected
  RemoveSelected
  OldLines
  NewLines
  OpenReview
  OpenReviewLink
  RemoveChange
  SelectedChanges
  CloseSelected
  NextMessage
  ThisMessage
  SelectedOnly
  RemoveGroup
}

///|
fn Message::text(self : Message, locale : @i18n.Locale) -> String {
  match (locale, self) {
    (English, ReviewSelected) => "Review selected changes"
    (Spanish, ReviewSelected) => "Revisar cambios seleccionados"
    (SimplifiedChinese, ReviewSelected) => "查看所选更改"
    (TraditionalChinese, ReviewSelected) => "檢視所選更改"
    (Japanese, ReviewSelected) => "選択した変更をレビュー"
    (English, RemoveSelected) => "Remove selected changes"
    (Spanish, RemoveSelected) => "Quitar cambios seleccionados"
    (SimplifiedChinese, RemoveSelected) => "移除所选更改"
    (TraditionalChinese, RemoveSelected) => "移除所選更改"
    (Japanese, RemoveSelected) => "選択した変更を削除"
    (English, OldLines) => "Old "
    (Spanish, OldLines) => "Anterior "
    (SimplifiedChinese, OldLines) => "原始 "
    (TraditionalChinese, OldLines) => "原始 "
    (Japanese, OldLines) => "変更前 "
    (English, NewLines) => "New "
    (Spanish, NewLines) => "Nuevo "
    (SimplifiedChinese, NewLines) => "修改后 "
    (TraditionalChinese, NewLines) => "修改後 "
    (Japanese, NewLines) => "変更後 "
    (English, OpenReview) => "Open in review"
    (Spanish, OpenReview) => "Abrir en revisión"
    (SimplifiedChinese, OpenReview) => "在审阅中打开"
    (TraditionalChinese, OpenReview) => "在審閱中開啟"
    (Japanese, OpenReview) => "レビューで開く"
    (English, OpenReviewLink) => "↗ Open in review"
    (Spanish, OpenReviewLink) => "↗ Abrir en revisión"
    (SimplifiedChinese, OpenReviewLink) => "↗ 在审阅中打开"
    (TraditionalChinese, OpenReviewLink) => "↗ 在審閱中開啟"
    (Japanese, OpenReviewLink) => "↗ レビューで開く"
    (English, RemoveChange) => "Remove change"
    (Spanish, RemoveChange) => "Quitar cambio"
    (SimplifiedChinese, RemoveChange) => "移除更改"
    (TraditionalChinese, RemoveChange) => "移除更改"
    (Japanese, RemoveChange) => "変更を削除"
    (English, SelectedChanges) => "Selected changes"
    (Spanish, SelectedChanges) => "Cambios seleccionados"
    (SimplifiedChinese, SelectedChanges) => "所选更改"
    (TraditionalChinese, SelectedChanges) => "所選更改"
    (Japanese, SelectedChanges) => "選択した変更"
    (English, CloseSelected) => "Close selected changes"
    (Spanish, CloseSelected) => "Cerrar cambios seleccionados"
    (SimplifiedChinese, CloseSelected) => "关闭所选更改"
    (TraditionalChinese, CloseSelected) => "關閉所選更改"
    (Japanese, CloseSelected) => "選択した変更を閉じる"
    (English, NextMessage) => "Included in your next message"
    (Spanish, NextMessage) => "Se incluirán en tu próximo mensaje"
    (SimplifiedChinese, NextMessage) => "将包含在下一条消息中"
    (TraditionalChinese, NextMessage) => "將包含在下一條訊息中"
    (Japanese, NextMessage) => "次のメッセージに含まれます"
    (English, ThisMessage) => "Included in this message"
    (Spanish, ThisMessage) => "Incluidos en este mensaje"
    (SimplifiedChinese, ThisMessage) => "已包含在此消息中"
    (TraditionalChinese, ThisMessage) => "已包含在此訊息中"
    (Japanese, ThisMessage) => "このメッセージに含まれています"
    (English, SelectedOnly) => "Only selected changes are included."
    (Spanish, SelectedOnly) => "Solo se incluyen los cambios seleccionados."
    (SimplifiedChinese, SelectedOnly) => "仅包含所选更改。"
    (TraditionalChinese, SelectedOnly) => "僅包含所選更改。"
    (Japanese, SelectedOnly) => "選択した変更のみが含まれます。"
    (English, RemoveGroup) => "Remove group"
    (Spanish, RemoveGroup) => "Quitar grupo"
    (SimplifiedChinese, RemoveGroup) => "移除此组"
    (TraditionalChinese, RemoveGroup) => "移除此組"
    (Japanese, RemoveGroup) => "グループを削除"
  }
}
