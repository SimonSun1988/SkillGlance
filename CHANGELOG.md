# Changelog

## [Unreleased]

## [0.2.0] - 2026-10-28

此版本為測試版（Pre-release），適用於 Apple Silicon Mac。

### 新增

- 加入 Claude Code、Gemini CLI、Cursor 與 Antigravity 的 Skills 紀錄解析，與既有的 Codex、Claude Desktop Code 統計整合。
- 依 AI 工具篩選統計，分開呈現呼叫、已確認讀取與結果未知的讀取請求。
- 顯示各來源的讀取狀態與資料完整性；來源缺漏或格式尚未支援時，暫停移除建議。
- 提供英文、簡體中文與繁體中文的一頁式官網，使用純 HTML、CSS 與 JavaScript。
- 加入 GitHub Pages 手動部署 workflow，只發布 `site/` 目錄。
- 提供 Apple Silicon 的 App 與 DMG 建置腳本，產生 SHA-256 檢查碼檔案。

### 修正

- 避免將 Claude Desktop Code 的子代理紀錄重複計入 Claude Code。
- 避免不同 AI 工具使用相同對話識別碼時，統計被錯誤合併。
- 重新掃描取得的結果不完整時，保留先前已確認的讀取紀錄。
- 調整官網繁中與簡中文案，並補上 footer copyright。

### 安全與隱私

- 官網僅使用示範資料，不讀取或上傳本機使用紀錄。
- 建置時移除執行檔中的個人建置路徑；本機資料庫、研究資料與安裝包不納入 Git 追蹤。

### 已知限制

- Antigravity 目前只能確認讀取請求，結果維持未知，不計入已確認讀取。
- Cursor 僅支援已驗證的紀錄格式。SQLite 使用唯讀連線，但仍可能更新協調用的 `-shm` 檔案，不修改對話資料。
- Gemini CLI 已透過格式測試驗證，目前尚無本機實際對話樣本。
- 安裝包採 ad-hoc 簽署，尚未完成 Apple 公證（notarization）。
