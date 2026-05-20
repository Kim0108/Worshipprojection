# Known Issues

這份文件記錄目前 review 時發現、但尚未處理的功能風險。現階段先保留作為後續開發清單。

## P1

### 從所有歌曲刪除時，今日流程可能把歌曲加回來

位置：

- `ContentView.swift`: 歌曲清單的 context menu 刪除
- `ContentView.swift`: 歌曲清單的 swipe delete
- `LyricManager.swift`: `synchronizeSongsBetweenLists()`

狀況：

從「所有歌曲」用單筆右鍵/長按刪除或滑動刪除時，目前只移除 `allSongs`。如果同一首歌仍存在於 `todaySetlist`，之後同步流程會把它重新補回 `allSongs`。

可能修法：

- 從所有歌曲刪除時同步移除今日流程中的同 ID 歌曲。
- 或把「所有歌曲刪除」定義成只從資料庫刪除，並明確清掉所有引用。

### 新增歌曲時，顏色轉換可能 crash

位置：

- `LyricManager.swift`: `addSong(...)`

狀況：

`UIColor(textColor).cgColor.components` 不一定有 RGB 三個 channel。某些灰階或系統色可能只有 2 個 components，目前直接取 `components[2]` 有越界風險。

可能修法：

- 使用 `UIColor.getRed(_:green:blue:alpha:)`。
- 若轉換失敗則 fallback 成白色。

## P2

### TXT 匯出/匯入不保留今日流程語意

位置：

- `Models.swift`: `WorshipProjectPackage.textExport()`
- `Models.swift`: `WorshipProjectPackage.textPackage(from:)`

狀況：

TXT 格式目前只輸出歌曲本體，沒有輸出今日流程 ID 或順序。匯入 TXT 時會把所有歌曲也放進今日流程，因此若使用者期待 TXT 能完整保存流程，結果會不符合預期。

可能修法：

- 在 TXT 格式中加入 `## Setlist` 區塊。
- 或在 UI 上明確標示 TXT 僅適合歌曲交換，JSON 才是完整專案包。

### 切換模式不會自動停止 Web 提詞機

位置：

- `WorshipprojectionApp.swift`: `activateMode(_:)`
- `LyricManager.swift`: `startWebTeleprompter()` / `stopWebTeleprompter()`

狀況：

iPhone 切換 A/B 模式時會停止 multipeer role，但 Web server 本身仍可能持續運作。這符合「iPhone 只開 Web 提詞機」的使用方式，但若使用者以為切模式會關閉 Web，可能造成混淆。

可能修法：

- 保持現狀，但在 UI 顯示 Web server 狀態。
- 或切換到簡報模式時提示是否停止 Web 提詞機。

## P3

### 背景影片縮圖可能造成素材頁滑動卡頓

位置：

- `ContentView.swift`: `videoThumbnail(for:)`

狀況：

影片縮圖目前在 SwiftUI render 時同步產生。若背景素材中影片很多，進入背景素材頁或滑動時可能卡頓。

可能修法：

- 匯入影片時先產生縮圖並快取。
- 或以非同步 thumbnail loader 產生並暫存。
