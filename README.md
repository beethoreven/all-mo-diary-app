# 全心日記（all-mo-diary-app）

一天一篇的 Android 日記 App（Flutter）。

## 開發

- Flutter 3.47.9、Dart 3.13.7（`pubspec.yaml` 釘住；套件一律釘當下最新正式版）。
- 第一次或改了 `lib/data/database.dart` 之後：`dart run build_runner build`
- 測試：`flutter test`（單元測試＋畫面流程測試，資料庫用記憶體裡的 SQLite）
- 建置：`flutter build apk --debug`；正式版需要 `android/key.properties`（不進 git），沒有時會擋下來，只在自己模擬器試 release 可設 `AMD_ALLOW_DEBUG_SIGNING=1`。

## 結構

| 路徑 | 內容 |
|---|---|
| `lib/core/` | 限制常數、日期（台灣時間）、文字規則 |
| `lib/data/` | drift 資料庫（日記、草稿、設定）與 `Store` |
| `lib/domain/` | 日記內文（Quill Delta）、搜尋與篩選、月曆格子 |
| `lib/services/image_service.dart` | 從相簿選圖、轉正去 EXIF、縮成畫面高度 1/3 |
| `lib/ui/` | 頂部列與頁籤、行事曆、篩選、搜尋、日記畫面（新建／檢視／編輯）、App 設定 |
