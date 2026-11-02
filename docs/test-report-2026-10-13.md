# Local Lab 功能測試報告

測試日期：2026-10-13。使用本機原生 App 連接真實 TUM JupyterLab，並以本機模擬服務驗證衝突與刪除保護。最終真實服務測試於 11:28–11:30（Europe/Berlin）完成，14 項檢查全部通過；另有 10 項原生回歸檢查通過。

| 項目 | 結果 | 實際驗證 |
| --- | --- | --- |
| 指令發送及結果返回 | 通過 | Python 核心回傳 execute_reply 與 idle；App 顯示執行完成 |
| 資料夾、檔案建立 | 通過 | Contents API 建立並讀回；App 新草稿另存遠端後出現在側邊欄 |
| 檔案修改及保存 | 通過 | App 修改 Python、Markdown 並保存；服務端讀回確認內容 |
| 檔案執行 | 通過 | 遠端 Python 檔案透過 runpy 執行；App 執行編輯器內容並顯示結果 |
| 檔案、資料夾刪除 | 通過 | 測試項目 DELETE 204、GET 404；App 執行受內容比對保護的刪除指令，回傳 APP_UI_DELETE_CONFIRMED True |
| Terminal 輸入／輸出 | API 通過 | 真實 terminal WebSocket 回傳 TERM_RESULT_861、TERM_ERROR_862，read 接收輸入並回傳相同標記 |
| Terminal 面板 | 未實作 | App 目前沒有 shell terminal 輸入面板，API 通過不代表介面已有此功能 |
| 檔案刪除按鈕 | 未實作 | 此次經 API 與 Python 指令測試刪除 |
| stdout／stderr 顯示 | 通過 | APP_CHECK_STDOUT_V2、APP_CHECK_STDERR_V2；錯誤輸出顯示紅色 |
| PNG 圖表顯示 | 通過 | 真實核心傳回有效 PNG，App 結果區可捲動顯示折線圖 |
| Markdown 本機渲染 | 通過 | 標題、粗體、斜體、表格、引用、任務清單、程式碼區塊；預覽／編輯／並排切換及保存後內容更新 |
| 遠端側邊欄切換 | 通過 | 展開遠端資料夾，切換 Python／Markdown 檔案 |
| 刪除同步及資料保留 | 通過 | 遠端刪除後移除失效遠端列，保留未保存內容為本機 .deleted-copy 草稿 |
| 閒置後執行 | 通過 | 閒置超過 75 秒後執行成功，約 0.97 秒完成 |
| 測試資源清理 | 通過 | 測試 terminal、專用核心、檔案及資料夾清理成功；本機測試草稿已移除，原有三份草稿保留 |

## 測試中修正

1. 原先 WebSocket 使用短期 HTTP 逾時設定，閒置後執行失敗。改為獨立長連線、持續接收、定時 ping 與執行前檢查；實際閒置與圖表執行重測通過。
2. 遠端刪除後已開啟檔案仍留在遠端側邊欄。現在確認 404 後保留本機副本，避免失去未保存內容；實際介面與自動回歸均通過。
3. Markdown 模式控制項標籤換行影響版面，已隱藏多餘可視標籤，保留可及性描述；實際渲染確認正常。

中間一轮測試的介面完成訊號等待逾時；其服務功能與清理檢查均成功。最終重新執行完整流程，完成介面檢查並送出訊號，所有檢查通過。較早測試程式的路徑轉義及 terminal 標記比對問題也已修正，並以最終結果為準。

## 驗證範圍

Markdown 並非完整 Typora 功能：數學公式、Mermaid、相對路徑／外部圖片尚未支援。Python input() 尚無互動輸入介面。保存具備內容比對與讀回驗證，但 Jupyter Contents API 不提供本 App 使用的原子衝突防護；同一檔案仍應避免兩個編輯器同時保存。

## 證據

- [真實服務測試結果](live-api-results.json)
- [原生介面測試記錄](ui-results.json)
- [原生回歸測試結果](native-regression-results.json)
- [核心產生的 PNG](kernel-output.png)

測試使用獨立建立的資源，未刪除原有文件或使用者的 JupyterLab 核心。Token 留在 App 記憶體與本機鑰匙圈，不包含於測試報告。
