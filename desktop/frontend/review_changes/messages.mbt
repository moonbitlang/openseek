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
    (SimplifiedChinese, ReviewSelected) => "查看所选更改"
    (Japanese, ReviewSelected) => "選択した変更をレビュー"
    (English, RemoveSelected) => "Remove selected changes"
    (SimplifiedChinese, RemoveSelected) => "移除所选更改"
    (Japanese, RemoveSelected) => "選択した変更を削除"
    (English, OldLines) => "Old "
    (SimplifiedChinese, OldLines) => "原始 "
    (Japanese, OldLines) => "変更前 "
    (English, NewLines) => "New "
    (SimplifiedChinese, NewLines) => "修改后 "
    (Japanese, NewLines) => "変更後 "
    (English, OpenReview) => "Open in review"
    (SimplifiedChinese, OpenReview) => "在审阅中打开"
    (Japanese, OpenReview) => "レビューで開く"
    (English, OpenReviewLink) => "↗ Open in review"
    (SimplifiedChinese, OpenReviewLink) => "↗ 在审阅中打开"
    (Japanese, OpenReviewLink) => "↗ レビューで開く"
    (English, RemoveChange) => "Remove change"
    (SimplifiedChinese, RemoveChange) => "移除更改"
    (Japanese, RemoveChange) => "変更を削除"
    (English, SelectedChanges) => "Selected changes"
    (SimplifiedChinese, SelectedChanges) => "所选更改"
    (Japanese, SelectedChanges) => "選択した変更"
    (English, CloseSelected) => "Close selected changes"
    (SimplifiedChinese, CloseSelected) => "关闭所选更改"
    (Japanese, CloseSelected) => "選択した変更を閉じる"
    (English, NextMessage) => "Included in your next message"
    (SimplifiedChinese, NextMessage) => "将包含在下一条消息中"
    (Japanese, NextMessage) => "次のメッセージに含まれます"
    (English, ThisMessage) => "Included in this message"
    (SimplifiedChinese, ThisMessage) => "已包含在此消息中"
    (Japanese, ThisMessage) => "このメッセージに含まれています"
    (English, SelectedOnly) => "Only selected changes are included."
    (SimplifiedChinese, SelectedOnly) => "仅包含所选更改。"
    (Japanese, SelectedOnly) => "選択した変更のみが含まれます。"
    (English, RemoveGroup) => "Remove group"
    (SimplifiedChinese, RemoveGroup) => "移除此组"
    (Japanese, RemoveGroup) => "グループを削除"
  }
}
