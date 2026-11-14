# 全心日記（all-mo-diary-app）

一天一篇的 Android 日記 App（Flutter）。

## 開發

- Flutter 3.47.9、Dart 3.13.7（`pubspec.yaml` 釘住；套件一律釘當下最新正式版）。
- 第一次或改了 `lib/data/database.dart` 之後：`dart run build_runner build`
- 測試：`flutter test`（單元測試＋畫面流程測試，資料庫用記憶體裡的 SQLite）
- 建置：`flutter build apk --debug`；正式版需要 `android/key.properties`（不進 git），沒有時會擋下來，只在自己模擬器試 release 可設 `AMD_ALLOW_DEBUG_SIGNING=1`。
- 模擬器上的影片測試（單元測試碰不到 App 自己的 Android 影片程式，這一項要在模擬器上實際跑；需要 ffmpeg 與 adb）：
  1. `flutter build apk --debug`，再 `adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk`
  2. `tool/video_samples.sh emulator-5554`：用 ffmpeg 產生測試影片，放進 App 的資料夾
  3. `flutter test integration_test/video_channel_test.dart -d emulator-5554`

  **只能在模擬器上跑，不要對著裝了正式版的手機跑。** `flutter test` 遇到簽章不同的既有 App 會先把它移除再安裝測試版，測試結束後也會移除 App；App 一移除，手機上的日記就沒了。電腦同時接著手機時，每個指令都要指定模擬器（`-s`／`-d`）。`tool/video_samples.sh` 遇到不是模擬器的裝置會直接停下來。

  模擬器要用主機的顯示卡（`emulator -avd <名稱> -gpu host`）：影片縮小的過程用到 OpenGL，純軟體繪圖的模擬器會慢到逾時。
- Media3（影片縮小與播放）的版本只寫在 `android/build.gradle.kts` 一個地方，App 自己的程式和 `video_player` 套件用同一版。

## 結構

| 路徑 | 內容 |
|---|---|
| `lib/core/` | 限制常數、日期（台灣時間）、文字規則 |
| `lib/data/` | drift 資料庫（日記、草稿、設定）與 `Store` |
| `lib/domain/` | 日記內文（Quill Delta）、搜尋與篩選、月曆格子 |
| `lib/services/image_service.dart` | 從相簿選圖、轉正去 EXIF、縮成畫面高度 1/3 |
| `lib/services/video_service.dart` | 從相簿選影片、縮成跟圖片一樣的大小（最長 2 分鐘）、第一個畫面存成封面圖 |
| `android/.../VideoChannel.kt` | 影片的 Android 程式：系統相簿選擇器、用 Media3 Transformer 剪長度與縮小（不保留拍攝地點）、取單一畫面 |
| `lib/ui/editor/video_*.dart` | 剪長度畫面、處理進度、全螢幕播放 |
| `lib/ui/` | 頂部列與頁籤、行事曆、篩選、搜尋、日記畫面（新建／檢視／編輯）、App 設定 |
