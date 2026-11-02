# 新功能輕量測試報告

2026-10-13，更新版 Local Lab。8 項原生自動檢查均通過，並完成實際 App 操作。只使用測試程式與獨立 terminal，不修改使用者原有文件。

| 測試 | 結果／證據 |
| --- | --- |
| 本機成功 → 真實伺服器覆核 | 通過；兩階段均顯示 Hello from local API、Total: 20 |
| 本機失敗不送遠端 | 通過；自動檢查確認伺服器 execute 次數不增加，App 顯示「本機錯誤 · 未送出」 |
| 錯誤定位 | 通過；scratch-5.py 第 2 行、ValueError: LOCAL_UI_BLOCKED、traceback 可見 |
| Python 完整版本 | 通過；伺服器與本機皆 3.10.12，不相符版本被阻擋 |
| 本機 terminal 指令／版本 | 通過；LOCAL_UI_42、Python 3.10.12 |
| 本機 shell 狀態與 read | 通過；後續指令取得 LOCAL_STATE_42，互動回覆 LOCAL_REPLY_light-local-42 |
| 伺服器 terminal 指令與 stderr | 通過；真實服務回傳 REMOTE_FINAL_OK、REMOTE_FINAL_STDERR |
| 伺服器 terminal 互動 read | 通過；REMOTE_UI_RESULT_861、REMOTE_UI_REPLY_light-check-42 |
| 鑰匙圈 | 固定憑證與 App identifier 綁定；多次重建後 requirement 一致。多次重新啟動／重用已保存 token 未觀察到重複授權提示；重用不重寫 token 項目 |
| 簽署 | macOS 正常鑰匙圈環境的 deep／strict 檢查通過，包含本機 PTY 元件 |

測試期間曾因 VPN 中斷而逾時；恢復後已完成真實伺服器 terminal 重測。本機 terminal 最初採用系統 script 元件時，App 內即時輸出異常；改成獨立 PTY 橋接元件後，實際介面與自動檢查均通過。

本機測試草稿已移除，保留原有四份草稿。正常結束 App 會清理此次開啟的 shell、App 專用 terminal 與核心；重新開啟後的新工作階段供使用者繼續使用。

Python 版本一致，套件與資料檔不會自動鏡像。兩階段成功表示兩端執行成功，未自動比較輸出內容。Terminal 支援互動 shell 指令、輸入回覆及中斷；全螢幕 ANSI TUI 尚未支援。

[機器可讀結果](lightweight-results.json) · [使用说明](../LocalLab/README.md)
