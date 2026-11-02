> Current release: **1.1.1** (build 5). `VERSION` and `BUILD_NUMBER` are authoritative. See [CHANGELOG.md](CHANGELOG.md), [AI review guide](docs/ai-review.md) and [release conventions](docs/version-management.md). Historical test reports describe the build/date stated in each report.

# Local Lab

原生 SwiftUI macOS App，透過整合於本機 App 的 Jupyter 連線服務，在 TUM 遠端 Python 核心執行程式。沒有雲端 UI 或本機 HTTP 監聽埠。

## 專案狀態

目前正式版為 1.1.1（build 5），包含 DeepSeek AI 審碼、人格／Key 本機保存、修改預覽與真實狀態欄。全屏背景與卡片透明度修復見 `docs/verification-1.1.1.md`；AI 功能與測試範圍見 `docs/verification-1.1.0.md`。2026-10-20 的概覽及狀態報告為歷史記錄。本倉庫不包含建置產物、簽署憑證或使用者資料。

## 倉庫結構

- `Sources/LocalLab/` — App 程式碼（App／Models／Services／Stores／Views／Design）
- `Tests/` — 原生 async 斷言程式與本機 Jupyter 模擬器
- `Support/ShellBridge.c` — 本機 PTY 橋接元件
- `script/` — 建置、簽署、測試腳本
- `Resources/` — 圖示、Markdown 渲染器與打包的 CPython 3.10.12
- `docs/` — 專案說明、測試報告、事故檢查與版本清單；`docs/design/` 收錄視覺與動效規範

## AI 審碼（1.1.0）

工具列「AI 審碼」或 ⇧⌘R 開啟右側面板，保持原有編輯器與下方 terminal 佈局。AI 不需要先連線到學校伺服器。

1. 開啟「AI 設定」，填寫 DeepSeek API Key，儲存一次。預設根網址 `https://api.deepseek.com`、模型 `deepseek-flash`；可改模型及兼容接口。
2. 選擇／編輯人格預設（嚴謹審閱者、耐心導師、最小修改工程師），或新增自己的提示詞。人格會自動加入每次請求。
3. 「僅審碼」只顯示問題；「審碼並修改」會生成完整建議內容，經預覽和明確套用後才改編輯器。可還原上次套用，但不覆蓋後續人工編輯。
4. 每次只發送目前檔案、選定人格和本次要求。不自動上傳遠端、執行程式、讀取其他檔案或在背景呼叫 AI。

Key 與設定分開存在 `~/Library/Application Support/LocalLab/AIReview/`，目錄權限 0700、檔案 0600；不用反覆輸入或批准鑰匙圈。不同 API 根網址有獨立 Key。審碼內容及結果只在記憶體中保留，套用程式碼仍使用原本草稿保存流程。這是本機私有檔案儲存，不宣稱額外加密。

AI 修改會比對送審時的檔案身分和內容，檔案切換、內容變更、執行或同步中會拒絕套用。AI 回應仍需人工判斷；程式碼與補充要求有單次大小上限。完整行為、測試與資料範圍見 [docs/ai-review.md](docs/ai-review.md)。

## 使用

1. 先依「開發」章節執行 `./script/build_and_run.sh` 建置，再開啟產生的 **Local Lab.app**。
2. 按「連線」。若這個版本內建 token（`Resources/builtin-token.txt`），直接按「連線」即可；否則貼上個人 JupyterHub token，會存到本機檔案（0600 權限）供下次自動連線。測試可先選 1 Hour，scope 為 `access:servers!server=go97lep/`。
3. 編輯 Python 草稿，再按「執行」或 **⌘ Return**。
4. 用 **⌘ .** 中斷 App 專用核心。其他 JupyterLab 核心不會被中斷。
5. 透過工具列選單「關閉專用核心」，或正常結束 App，以清理核心。

連線目的地固定為 `https://lecture.cs.tum.de:9000/user/go97lep/api`。需保持可存取校內主機的網路路徑。token 到期後在連線面板更新；內建 token 則修改 `Resources/builtin-token.txt` 後重新建置。本機保存不會延長伺服器端有效期。設定可關閉自動連線或移除已保存 token。

## 外觀與動效

介面沿用參考設計的極光漸層與玻璃質感：未設定背景圖片時顯示會緩慢流動的極光底，卡片為大圓角、細白邊與柔和陰影，選中項目以滑動膠囊表示。

設定 › 外觀 可即時調整：強調色（長春花／珊瑚／天藍／薄荷，或點色環自訂任意顏色）、極光節奏與強度、面板質感（磨砂／實心／通透）、圓角、動效節奏（含蓄／標準／活潑），並附即時預覽與「恢復預設外觀」。所有動效尊重系統「減少動態效果」；視窗不在前景時極光自動停止漂移。完整令牌、曲線與逐項動效對照見 `docs/design/motion.md`。

## 功能

- 系統側邊欄、工具列、SF Symbols、深淺色、設定視窗與鍵盤命令。
- Python 編輯器：等寬字體、基本語法色彩、4 個空白的 Tab、自動關閉智慧引號與拼字修正。
- 草稿保存於 `~/Library/Application Support/LocalLab/drafts.json`。只保存本機程式；不自動修改遠端筆記本。
- 匯入及匯出 Python 檔案；設定字體大小。
- 即時 stdout/stderr、例外 traceback、text/plain 與 PNG 圖表顯示。HTML/JavaScript 輸出不執行。
- 收到相同 request ID 的 execute_reply 與 idle，才標示完成。
- Python 程式先在本機執行；核對完整 Python 版本，成功後才送至伺服器覆核。
- 編輯器下方提供本機與伺服器兩個互動 shell terminal，支援發送指令、回覆 read、保留 shell 狀態、中斷及重新連線。
- 使用 URLSession 的系統 TLS 驗證，不停用憑證檢查。
- token 只會來自 App 內建的 `builtin-token.txt`，或使用者貼上後存放於 `~/Library/Application Support/LocalLab/credential.txt`（0600 權限）；不寫入鑰匙圈、UserDefaults、cookie，也不經命令列傳遞。設定中可移除（內建 token 除外）。
- 專用核心由 App 建立；關閉時 DELETE 後再以 GET 404 確認。清理失败會顯示核心 ID，保留重試機會。

## Markdown 與 token

Markdown（.md / .markdown）預設使用本機閱讀預覽，可切換「編輯」及「並排」。版面參考本機 Typora GitHub 主題的閱讀寬度、行距、標題、引用、表格和程式碼區塊，跟隨深淺色模式。文件不送到第三方渲染服務。支援 GFM 表格、清單、任務清單與程式碼區塊；HTML 經清理，文件中的腳本不執行。外部或相對路徑圖片目前顯示替代文字；數學公式、Mermaid 與 Typora 的完整即時 WYSIWYG 編輯尚未實作。

首次連線成功後，App 會把 token 存到 `~/Library/Application Support/LocalLab/credential.txt`（0600 權限）；下次啟動直接讀取並建立新的專用核心。若建置時放入了 `Resources/builtin-token.txt`，則完全跳過輸入與檔案，啟動即連線。設定可停用自動連線、移除 token；移除本機 token 不等於撤銷 JupyterHub 端 token。

## 內建 token（個人建置）

把 token 寫進 `Resources/builtin-token.txt`（這個檔案已列入 `.gitignore`，不會進版控），再執行 `./script/build_and_run.sh`：建置腳本會把整個 `Resources/` 複製進 `Contents/Resources/`，App 啟動時偵測到就自動連線，完全不需要鑰匙圈或手動輸入。刪掉該檔再重新建置即恢復為手動輸入。

## 檔案與目錄同步

- 側邊欄直接顯示遠端檔案樹；展開資料夾，單擊檔案即可像本機草稿一樣切換編輯。已展開的資料夾在更新時保留，並重新取得內容。
- 「遠端檔案」也提供包含大小、類型與修改時間的目錄表格。雙擊資料夾或使用「開啟選取項目」瀏覽。
- 目錄與目前開啟的遠端文字檔每 15 秒更新，也可手動重新整理。
- 遠端 UTF-8 文字檔（最多 1 MB）可在原生編輯器開啟。Notebook 由 JupyterLab 開啟。
- 遠端檔案按 **⌘ S** 或「儲存至遠端」才會寫回。未保存修改以本機草稿形式保留。
- 使用工作區選單「另存至遠端」把本機草稿保存至目前遠端目錄；同名項目會被拒絕。
- 遠端瀏覽器可建立資料夾；保存後會重新讀取目錄。
- 若遠端內容有變更且本機沒有修改，會載入新內容；若雙方都修改，保留本機內容並提示衝突。
- 衝突處理「保留副本並載入遠端」會先建立本機草稿副本，再載入遠端版本。
- 斷線或無權限時保留快取內容。確認遠端檔案已刪除（404）後，會移至本機草稿，命名為 .deleted-copy，保留未儲存內容並移除遠端側邊欄項目。

保存採用 Jupyter Contents API 的讀取比對、寫入、再次讀取確認。此 API 沒有本 App 可用的原子 compare-and-swap 保證，因此在比對與写入之間另一個編輯器仍可能改動檔案；同一檔案請避免在兩個編輯器同時保存。本版不包含指定本機資料夾的完整鏡像同步。

## 限制

這是 Python scratchpad，而非完整 .ipynb 編輯器。App 已提供本機及伺服器 terminal 面板。檔案刪除按鈕尚未提供，可透過 terminal 操作。Python input() 互動輸入與其他 MIME 圖表格式尚未支援。本機每次以獨立 Python 程序執行完整腳本；伺服器則保留同一專用核心的 Python 變數，直到關閉連線。強制結束、網路中斷或 token 到期可能阻止清理；屆時需在 JupyterLab 關閉該專用核心。

原生 App 已在真實 TUM 服務執行 Hello 範例，收到 `Hello from local API` 與 `Total: 20`，核對 execute_reply/idle 後顯示執行完成（0.38 秒）；測試專用核心正常關閉。真實 TUM 服務已完成隔離資料夾、檔案建立／修改／讀回／刪除、Python 執行、stdout／stderr／PNG，以及 terminal WebSocket 互動輸入輸出測試。原生介面另驗證 Markdown 渲染／編輯／保存、側邊欄切換、Python 輸出顯示與刪除後本機副本保留。詳見 `docs/test-report-2026-10-13.md`。

## 開發

目前工作副本可放於任意本機資料夾；本次使用 `/Users/edwardwilson/Documents/Codex/local-lab`。生成物集中到被 Git 忽略的 `dist/` 與 `.build/`，不再混入原工作區的 outputs。`./script/test_ai.sh` 會自動建立與關閉 loopback 模擬服務；不需要真實 API Key。`python3 script/package_release.py` 只接受乾淨的已提交源码，輸出 `dist/<version>/` 的 ZIP、manifest 與 SHA256SUMS。


本機 Apple Silicon 版本，macOS 14+。使用 SwiftPM，使用者不需安裝 Python、Node.js 或其他執行環境；Markdown 解析器 Marked 18.1.1 與 DOMPurify 3.4.17 已打包於 App，附授權文件。

```sh
./script/build_and_run.sh
./script/test.sh
```

Codex Run action 已設定至 `script/build_and_run.sh`。支援 `--build-only`、`--verify`、`--debug`、`--logs`、`--telemetry`。建置時若 App 正在執行會停止，請正常結束 App 以完成遠端清理。

`script/swift.sh` 偵測本機 CLT 殘留過舊的 PackageDescription 私有介面時，會在專案 .build/ 複製 Apple 現有公開介面作為隔離相容處理，不修改系統 SDK。

本機僅安裝 Command Line Tools，沒有 XCTest，因此測試腳本會編譯原生 async 斷言程式。整合測試可由 `LOCAL_LAB_TEST_API` 指定本機 Jupyter 模擬服務；未提供時會跳過該項。本次模擬器僅用測試憑證與本機核心資料，不傳送真實 token。

## 設計依據

- https://developer.apple.com/design/
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/design/human-interface-guidelines/accessibility

以系統原生控制項呈現導覽及操作層，避免自訂材質覆蓋系統工具列；內容使用可選取文字、清楚的狀態描述及鍵盤替代操作。

## 驗證結果

最終版本十項原生自動檢查均通過：未登入禁止執行、專用核心清理、清理失敗重試狀態、草稿保存、已儲存 token 重用與移除、macOS 鑰匙圈合成項目讀寫、WebKit Markdown 解析與 HTML 清理、目錄／衝突／特殊檔名、REST/WebSocket request ID 比對、側邊欄資料夾與檔案切換／未保存內容保護。另已驗證原生系統 TLS 可讀取 TUM API 版本。

本機模擬器位於 `Tests/mock_jupyter.py`，測試環境需 aiohttp。啟動模擬器後，可執行：

```sh
LOCAL_LAB_TEST_API=http://127.0.0.1:18768/api LOCAL_LAB_VERIFY_KEYCHAIN=1 LOCAL_LAB_VERIFY_MARKDOWN=1 ./script/test.sh
```

鑰匙圈測試使用唯一名稱的合成項目，完成後移除；不讀取真實 token。

2026-10-13 完整功能測試後，已修正 WebSocket 閒置連線：獨立長連線設定、持續接收、定時 ping 與執行前連線檢查。閒置超過 75 秒後的實際執行通過。新增遠端刪除回歸檢查，保留未保存內容並移除失效遠端列。

## 本機先執行與伺服器覆核

伺服器 Python 版本由 kernel_info_reply 讀取，核對完整 major.minor.patch。本 App 已打包 CPython 3.10.12；初次執行會解壓至本機 Application Support/LocalLab/Runtimes，並建立專用虛擬環境。使用者不需額外安裝 Python。伺服器版本變更時，若有 uv 可下載對應版本，也可在設定指定精確相符的 Python 執行檔；版本不符時停止，不改用其他版本。

按執行後先顯示本機 stdout/stderr。SyntaxError 或執行例外會顯示原草稿檔名、行號與 traceback；非零結束碼、版本不符或環境準備失敗皆不送出程式。只有本機成功，才用同一份程式快照送至伺服器。伺服器成功顯示「本機與伺服器通過」，失敗顯示「伺服器覆核失敗」；此狀態確認執行結果，沒有自動比對兩端文字輸出是否完全一致。

本機工作目錄預設為 ~/Library/Application Support/LocalLab/Workspace；可於設定更改，亦可指定自己的 Python/venv。程式所用套件與資料檔需在本機準備；Python 版本一致不等於 macOS 與 Linux 的所有套件／資料一致。可在本機 terminal 用 python3 -m pip 安裝需要的套件；本機 terminal 在環境已準備時使用同一 Python/venv。本機成功的程式會在兩端各執行一次，檔案修改等副作用也各自發生。

## Terminal

下方面板「本機 Terminal」使用 PTY 與持續 zsh shell；「伺服器 Terminal」建立 App 專用 Jupyter terminal，使用 token header 與 WebSocket 通訊。兩者可切換、輸入指令、傳送 read 回覆、中斷、重新連線與清除顯示。文字輸出上限 256 KB。介面是可選取文字的 shell 記錄，尚未實作完整 ANSI 游標畫面，因此 vim/top 等全螢幕 TUI 不在本版支援範圍。伺服器 shell 指令直接在伺服器執行，不經 Python 編輯器的本機先行流程。

正常結束 App 會關閉本機 shell 並 DELETE／GET 404 確認 App 專用遠端 terminal；不關閉其他使用者 terminal。強制結束或失去網路仍可能阻止遠端清理。

## 憑證存放（2026-11-02 起）

App 已改用 `FileTokenVault` 把 token 存在應用程式支援目錄的明文檔案（0600），不再讀寫 macOS 鑰匙圈；因此重建造成的簽章變化不會再觸發 `Keychain OSStatus -25293`。舊鑰匙圈項目留著不影響運作，可自行在「鑰匙圈存取」中刪除。若 bundle 內含 `builtin-token.txt`，啟動時直接用它連線，連檔案都不需要。

## 固定簽署與鑰匙圈（歷史）

開發建置由 ad hoc 簽署改為固定本機憑證，designated requirement 綁定 App identifier 與同一憑證 SHA-1，沒有改成允許任意 App，也未改動系統 TLS 信任。自動連線與使用已保存 token 不再重寫鑰匙圈項目。固定簽署未能單獨解決舊 token 的授權問題。現在啟動時使用無互動讀取，不自動彈出授權視窗；連線或設定中的「修復鑰匙圈授權」會更新該 token 項目的 ACL，只信任目前已簽署的 Local Lab。舊項目修復需要 macOS 確認；本次修復完成後，已確認新程序重新開啟時可靜默讀取 token 並自動連線。

私有簽署資料位於 .local-signing/，受權限保護並排除 Git／來源 ZIP；勿刪除它，否則下次建置會產生新身分。這是供本機使用的簽署，並非 Developer ID 公開發行或公證。

2026-10-13 新功能輕量測試詳見 `docs/test-report-lightweight-2026-10-13.md`；原完整測試報告記錄的是上一版本的功能狀態。

簽署依據：[Apple Code Signing Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。Python 管理依據：[uv Python versions](https://docs.astral.sh/uv/concepts/python-versions/)。

2026-10-13 版面更新：主編輯器／檔案瀏覽在上方，下方面板包含「執行結果」「本機 Terminal」「伺服器 Terminal」三個分頁，可拖曳分隔線調整高度。本次只進行建置及開啟／重新啟動檢查，未執行完整測試。鑰匙圈修改依據：[Apple kSecAttrAccess](https://developer.apple.com/documentation/security/ksecattraccess)。

## 本机发布版 1.0.1

发布产物（1.0.1 的 App 与 ZIP）因含建置产物与签名二进制，不纳入此仓库。图标使用用户提供的 PNG，保留透明背景，转为多尺寸 AppIcon.icns。使用 --release 进行优化构建及固定身分签署。尚未进行 Developer ID 公证或 App Store 发布。

## 1.0.1 背景设置

工具栏右上角菜单「更换背景…」，或设置中的「背景」。选择图片后拖动图片平移裁剪区域，可选 16:10／16:9／4:3／1:1，缩放范围 1–4 倍。透明度 0% 为不透明、100% 为完全透明；高斯模糊范围 0–40 pt。预览修改不影响当前背景；点击「确认设置背景」后复制图片与裁剪结果到本机 Application Support/LocalLab/Background，并原子保存设置。重启自动恢复；「恢复默认」清除背景。图片不上送服务器。背景以整窗统一画布渲染，侧边栏、主操作区及标题栏保持连续；主操作区与侧边栏透明度可分别调整。编辑器及 Markdown 支持透明背景。

本次发布已覆盖 1.0.0，仅做建置、启动与背景设置预览检查。

1.0.1 背景补充：背景设置现有「主操作区透明度」「侧边栏透明度」两个独立滑块。旧版单一透明度设置会自动作为两区域的初始值，不改变既有图片、裁剪或模糊设置。侧边栏调整宽度或隐藏时，同一张图片继续按整窗定位。
