# SkillGlance

常駐 macOS 選單列的 Skills 使用統計工具。整合多種 AI 工具的本機紀錄，分開呈現呼叫、已確認讀取與結果未知的請求，並保留來源供查閱。

[繁體中文官網](https://simonsun1988.github.io/SkillGlance/zh-Hant/) · [English](https://simonsun1988.github.io/SkillGlance/) · [简体中文](https://simonsun1988.github.io/SkillGlance/zh-Hans/) · [下載 0.3.1 測試版](https://github.com/SimonSun1988/SkillGlance/releases/tag/v0.3.1) · [Changelog](CHANGELOG.md)

## 目前版本

**0.3.1 Beta（Pre-release）**，適用於 Apple Silicon Mac，系統需求設定為 macOS 14 或以上版本。實機測試僅涵蓋執行 macOS 27.0.1 的開發用 Mac。

App 與官網提供英文、簡體中文、繁體中文。App 依 macOS 的語言偏好顯示。

此測試版採 ad-hoc 簽署，尚未完成 Developer ID 簽署與 Apple 公證（notarization）。macOS 可能在開啟 App 時顯示安全性提示。

## 支援的 AI 工具

| 工具 | 可解析的紀錄與限制 |
| --- | --- |
| Codex | 本機對話與封存對話中的 Skill 讀取紀錄。 |
| Claude Desktop Code | 可辨識為 Desktop Code 的本機工作階段；不包含 Claude 一般聊天。 |
| Claude Code | CLI 對話紀錄中的明確呼叫與已確認讀取。 |
| Gemini CLI | JSON／JSONL 紀錄中的 Skill 啟用與檔案讀取。已通過格式測試，目前尚無本機實際對話樣本。 |
| Cursor | 已驗證的內部 SQLite 格式（v3 與 `read_file_v2`），分別保留成功、失敗與未知結果。 |
| Antigravity | 完整對話紀錄中的明確讀取請求；結果維持未知，不計入已確認讀取。 |

實際可統計的內容取決於本機有哪些紀錄，以及 App 是否支援該格式。讀不到紀錄或遇到未知格式，會標示資料不完整，不能當作沒有使用。

## 統計方式

- **呼叫**：紀錄中可辨識的明確 Skill 呼叫，保留其結果狀態。
- **已確認讀取**：有成功結果與內容載入的依據；無法確認 AI 是否遵循其中的指示。
- **結果未知**：有讀取請求，但無法確認是否成功。不計入已確認讀取或已確認有使用的對話數。

呼叫與讀取可能來自同一次使用，兩種次數不直接相加。單純在對話中提到 Skill 名稱，不算成功使用。

可依工具、專案、worktree 與時間範圍篩選，並將重要的 Skills 標記為保護。移除建議需要完整的 90 天觀察期與足夠完整的紀錄；App 不會自動刪除 Skills。

## 安裝與更新

1. 從 [GitHub Releases](https://github.com/SimonSun1988/SkillGlance/releases/tag/v0.3.1) 下載 `SkillGlance-0.3.1-arm64.dmg` 與同名 `.sha256` 檔案。
2. 在下載目錄執行檢查碼驗證：

   ```sh
   shasum -a 256 -c SkillGlance-0.3.1-arm64.dmg.sha256
   ```

3. 若已安裝舊版，先結束 SkillGlance，並備份下方的資料目錄。
4. 開啟 DMG，將 SkillGlance 拖入 Applications（應用程式）資料夾。更新時替換舊 App，再從該資料夾開啟。

0.3.1 沿用原本的資料目錄，替換 App 不會清除統計資料。從 0.2.x 更新時，第一次掃描會重新讀取所有紀錄一次（約 20 秒），不會重建統計。

## 資料與隱私

App 不需要帳號，不收集遙測資料，也不會上傳使用紀錄。不需安裝 hook 或修改 AI 工具設定。

統計資料保存在：

```text
~/Library/Application Support/SkillsUsage/
```

目錄名稱沿用舊版，以保留統計資料。備份時，先結束 App，再複製整個目錄。

資料庫保存事件摘要、來源位置、讀取進度、專案掃描範圍與重要標記，不保存完整對話或工具輸出。專案名稱與來源路徑仍可能包含私人資訊，請勿將資料庫放進公開儲存庫。

Cursor 資料庫使用唯讀 SQLite 連線，不修改對話資料；SQLite 仍可能更新協調用的 `-shm` 檔案。

## 從原始碼建置

需要 macOS 與 Swift 6 工具鏈。App 使用 SwiftUI、AppKit 與系統 SQLite；官網使用純 HTML、CSS、JavaScript。

```sh
swift test
./scripts/build-dmg.sh
```

輸出位於 `dist/`，包含 App、DMG 與 SHA-256 檢查碼檔案。若只需要 App，可執行 `./scripts/build-app.sh`。建置腳本使用 ad-hoc 簽署，不會完成 Apple 公證。

同版本的 DMG 已存在時，腳本會停止，請先移走舊檔。`dist/`、本機資料庫與研究資料均不納入 Git 追蹤。

## 官網部署

網站原始碼位於 `site/`，不需要前端建置步驟。本機預覽可使用：

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory site
```

GitHub Pages 使用預設網域，未設定 Custom domain。部署方式：

1. 將儲存庫的 **Settings → Pages → Source** 設為 **GitHub Actions**。
2. 到 **Actions → Publish static website → Run workflow**，選擇 `main` 執行。

Workflow 僅發布 `site/`；App 安裝包則放在 GitHub Releases。

## 搜尋與回答系統

三語頁面各自提供 canonical、互相對應的 hreflang、分享預覽圖，以及與頁面內容一致的 `WebPage`／`SoftwareApplication` JSON-LD。產品介紹、支援範圍與問答直接寫在 HTML，停用 JavaScript 也能讀取。示範統計區塊使用 `data-nosnippet`，避免 Google 將示範數字當成搜尋摘要。

[Sitemap](https://simonsun1988.github.io/SkillGlance/sitemap.xml) 列出三個正式網址及語言對應。本站位於 `/SkillGlance/` 子路徑，無法透過此專案設定網域根目錄的 `robots.txt`；子目錄中的同名檔案不能取代根目錄設定。目前根目錄回傳 404，不代表禁止爬取。

部署前可執行以下檢查；GitHub Pages workflow 也會執行：

```sh
python3 scripts/check-site.py
```

結構化資料沒有虛構評分、評論或價格。Schema.org 語意驗證通過，不等於符合 Google App 複合式搜尋結果的資格；目前未提供該功能要求的價格與評分／評論欄位。

這些設定協助系統理解內容，不保證收錄、排名、複合式搜尋結果或 AI 引用。Google Search Console 的收錄狀態、sitemap 提交與成效追蹤，仍需網站所有權驗證；可使用本站完整網址作為 URL-prefix property。

## 問題回報

請透過 [GitHub Issues](https://github.com/SimonSun1988/SkillGlance/issues) 回報問題，附上 App 版本、macOS 版本、AI 工具名稱及去識別化後的錯誤訊息。請勿附上原始對話紀錄、憑證或統計資料庫。
