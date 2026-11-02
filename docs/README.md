# 文件索引

本目錄收錄 Local Lab 的專案說明、測試證據與事故檢查。程式碼與建置方式見根目錄 [README](../README.md)。

## 專案

| 文件 | 內容 |
| --- | --- |
| [overview.md](overview.md) | 專案完整說明：定位、目標、現況、流程、技術路線、組件分工、資源路徑、建置與驗證邊界、已知問題、限制、交接建議（2026-11-02 編寫） |
| [status-2026-10-20.md](status-2026-10-20.md) | 開發暫停記錄：已發布版本、未完成改動、保留的檔案 |

## 測試與驗證

| 文件 | 內容 |
| --- | --- |
| [api-test-2026-10-13.md](api-test-2026-10-13.md) | Jupyter REST + WebSocket 首次連通驗證（建立核心、執行、關閉清理） |
| [test-report-2026-10-13.md](test-report-2026-10-13.md) | 對真實 TUM 服務的完整功能測試，14 項介面檢查與 10 項原生回歸 |
| [test-report-lightweight-2026-10-13.md](test-report-lightweight-2026-10-13.md) | 本機先執行／伺服器覆核、terminal、鑰匙圈與簽署的輕量測試 |

## 事故與發布

| 文件 | 內容 |
| --- | --- |
| [incident-windowserver-2026-10-13.md](incident-windowserver-2026-10-13.md) | WindowServer 看門狗故障的系統快照分析與排查建議；未能歸因於本 App |
| [release-manifest-1.0.1.json](release-manifest-1.0.1.json) | 1.0.1 發布清單：SHA-256、平台、背景功能清單與驗證紀錄 |

## 第三方元件

`Resources/` 內含：

- `marked.js`（Marked 18.1.1，MIT）、`purify.js`（DOMPurify 3.4.17，Apache-2.0／MPL-2.0），授權文件同目錄。
- `python-3.10.12.tar.gz`：供 Apple Silicon 使用的預先建置 CPython 3.10.12（python-build-standalone 命名格式），首次本機執行時解壓，讓使用者不必自行安裝 Python。授權為 PSF-2.0。

> 測試報告記錄的是當時版本的狀態；1.0.1 之後的介面修正與未發布改動以程式碼與 `status-2026-10-20.md` 為準。
