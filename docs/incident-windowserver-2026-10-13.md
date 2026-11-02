# Local Lab／WindowServer 故障檢查（2026-10-13）

目前不能證實這次 WindowServer 故障由 Local Lab 引起，也不能排除 App 在故障前曾增加負擔。現有證據更支持系統圖形服務失去回應並伴隨大量記憶體使用。App 自身另有已證實的網路回呼崩潰缺陷，已修正；它與 WindowServer 故障是否相關，尚無證據。

## 系統故障證據

- 17:28:53 的系統快照、17:29:02 的 WindowServer 報告：WATCHDOG 終止，主執行緒 40 秒沒有回應。黑屏並回到登入畫面與此事件吻合；不是從這份報告判定整台機器重新開機。
- 堆疊集中在 SkyLight／QuartzCore 圖層處理，部分採樣涉及 Metal、檔案分頁。報告沒有把問題圖層對應至 Local Lab 的窗口，不能据此認定是 App 的背景圖片。
- 機型 MacBookAir10,1，實體記憶體 8 GB。
- 故障快照中的 reported residentMemoryBytes：Chrome Renderer PID 65590 為 6,848,782,352 bytes（6.38 GiB）；Codex Renderer PID 82197 為 1,600,392,888 bytes（1.49 GiB）；WindowServer 約 952 MB。這些是報告欄位，不能簡單相加成機器實體使用量，也不能單憑數值斷定某一網頁洩漏；Chrome 程序是優先排查對象。
- Local Lab 在故障快照中不存在，符合使用者先關閉 App 的敘述。這不能證明它在關閉前沒有問題。
- 17:21–17:26 Local Lab 記錄的是網路逾時、離線及代理解析失敗；未找到直接把 WindowServer 故障歸因於它的錯誤。
- 09:59–10:02 已有另一次 WindowServer CPU 資源報告（平均 54%）；時間較早，本次沒有完整核對當時 App 狀態，不能用它作為 App 無責任的證明。

## App 原始碼檢查

檢查了背景圖片／模糊、SwiftUI 更新、Markdown WebView、遠端同步、WebSocket 心跳及接收、Python 本機執行、terminal、輸出上限、退出清理。

- 閒置同步每 15 秒一次，串行並以 fileBusy 阻止重疊；心跳每 20 秒一次。沒有發現閒置自動執行 Python 的路徑。
- terminal 顯示尾端限制為 262,144 字元；核心接收暫存最多 1,000 則；執行文字與圖片有上限。這些是靜態檢查結果，不能排除超大單則訊息或高流量 terminal 在使用中造成瞬間負担；本次使用者描述為閒置。
- 背景圖匯入縮至最長邊 3072 像素；現有設定的高斯模糊為 0。背景顯示仍含透明圖層，需要長時 A/B 測試才能排除圖形合成問題。
- Markdown 原先在任意父視圖更新時都重新執行渲染，包括沒有改動內容的閒置同步。已加入內容及透明狀態比對，未變更時跳過重繪。Apple 的性能文件也指出頻繁、無必要的更新會消耗資源：[Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)。這是實際的效率缺陷，但尚不能說它導致本次 WindowServer 故障。

## 已證實的 App 崩潰及修正

今天 11:11、14:10、14:21 的三份 LocalLab crash report 均記錄 CheckedContinuation.resume(throwing:) 的 assertion failure，來源為 JupyterClient.ping 的 sendPing 回呼。原始碼直接 resume，未防範重複完成。已改用鎖保護的單次完成機制，將正常回應、錯誤、8 秒逾時及取消統一處理；遲到或重複回呼不會再 resume 第二次。這是 App 自身的崩潰，不能把它等同為 WindowServer 崩潰。

## 本次驗證與限制

- 原安裝版受控閒置約 3 分鐘，保留現有背景，Python 編輯器及本機 terminal；真實伺服器連線逾時，因此沒有完整涵蓋已連線狀態。
- App 啟動後 CPU 接近 0%；系統 sample 實際 footprint 約 53.9 MB，峰值約 81 MB；主執行緒 2533／2534 個採樣停在事件等待，沒有發現忙循環。
- 關閉 App 後約 45 秒對照，WindowServer CPU 仍約 29.5–46.5%。其他程式仍在使用，這不是完全隔離的實驗，不能當成嚴格因果證明。
- 並發 10,000 次重複回呼、回呼先於 continuation 安裝、提前取消測試通過。
- 本機模擬 Jupyter 的 REST／WebSocket、檔案同步、衝突與刪除保留、專用核心清理回歸通過。不使用真實 token。
- Markdown 實際 WebKit 測試通過：480 次內容不變更新只渲染一次；變更內容後正常重新渲染。修正版已構建、簽署、覆蓋 /Applications/Local Lab.app，版本保持 1.0.1；啟動及 Markdown 顯示確認後正常退出。修正版啟動出現 Keychain -25293，未進行憑證授權修復，真實遠端功能本次不作成功聲明。
- 本次未完成 1–2 小時實際已連線／有無背景對照測試；短測與原始碼檢查不能排除延遲型 GPU、記憶體或系統框架問題。

建議下一次長測同時記錄 App、WindowServer、Chrome Renderer 的 footprint／CPU 與系統記憶體壓力，依序比較無 App、App 無背景、App 有背景、已連線／離線。若再次卡頓，保留故障時刻和新 WindowServer 報告，才能追查故障前的資源走勢。本次不修改其他 App、不關閉瀏覽器分頁、不改系統圖形設定。

## 深入排查補充與建議

後續讀取 watchdog spin 的程序資料：Chrome Renderer PID 65590 的 Footprint 為 6531.51 MB，Time Since Fork 103461 秒（約 28.7 小時），並非只在 Local Lab 開啟的最近 1–2 小時才建立。其主執行緒部分採樣經過 APFS、儲存堆疊與 NVMe 等待；Codex Renderer 與 WindowServer 也有分頁／檔案等待採樣。這支持記憶體與磁碟分頁壓力的推論，但沒有連續壓力走勢或已識別的 Chrome 網頁，不能證明記憶體洩漏。

17:23:11 有 kernel「Memory pressure corpse purge」記錄。17:22 左右 Wi-Fi 驅動記錄 BCMWLAN Cmdr Pending Queue Stall、watchdog 與 firmware trap，是另一路系統異常；它可解釋當時网络問題，與圖形故障是否同源尚不確定。當前磁碟可用約 19 GiB；早上報告約 12.52 GB，屬空間偏緊但沒有證明交換空間耗盡。

優先順序：
1. 保存工作後完整退出並重開 Chrome，而不只關閉一兩個分頁；同樣重開長時間運行的 Codex／ChatGPT。使用 Chrome 任务管理器按記憶體排序，找出逐步增長的頁面或擴充套件。舊 PID 在登入重啟後無法可靠對應至目前分頁，不猜測特定網站。
2. Chrome 啟用 Memory Saver，減少非必要擴充與常駐頁面。活動監視器觀察記憶體壓力及交換量的變化，不能單凭累積 swap 數字判定目前故障。
3. 整理磁碟空間，目標預留約 25–30 GB 作為本機操作建議而非 Apple 規定，避免空間不足放大分頁問題。
4. 若記憶體壓力已正常仍再現，單獨試驗關閉 Chrome 圖形加速並重開 Chrome；如果沒有改善則恢復。這是圖形路徑的診斷試驗，可能增加 CPU 使用，不保證有效。
5. 更新到此電腦可用的穩定 macOS／Chrome／Codex 版本，不假定已存在針對這次故障的修補。
6. Local Lab 暫用無自訂背景做 1–2 小時對照，再恢復背景比較。若只在有背景時再現，應改成一次預處理模糊並快取的靜態背景，減少透明合成與視圖重繪；目前沒有足夠證據需直接移除背景功能。

來源：[Chrome 記憶體問題排查](https://developer.chrome.com/docs/devtools/memory-problems)、[Chrome Memory Saver](https://support.google.com/chrome/answer/12929150)、[Chrome 圖形加速排錯](https://support.google.com/chrome/answer/142063)、[Apple 記憶體壓力說明](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac)。
