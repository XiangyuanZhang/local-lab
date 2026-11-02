# Local Lab 視覺與動效規範

這份文件記錄 2026-11-02 兩輪 UI 改造的設計依據、設計令牌、可自訂外觀與動效規則。所有改動只涉及外觀與過場，不改資料流、同步、執行或終端行為。

## 1. 設計來源

參考 Figma 檔案 `sXro1JaLt8UsoVgSEDeaJ9`（Agog 騎行 App）：

- 極光式柔和漸層底：天藍、長春花、淡紫、珊瑚粉之間緩慢過渡。
- 白色／半透明大圓角卡片，連續圓角（continuous corner curve），極細白邊與柔和陰影。
- 標題採「粉 → 藍」漸層字。
- 分段控制與底部導覽用「滑動膠囊」表示選中項。
- 強調色使用粉色（敘事）、藍色（資料）與紫色（選中描邊）。

從 Assets 頁取樣到的原始色票：`#90BEF1` 天藍、`#F190A0` 珊瑚粉、`#A090F1` 長春花、`#BAABCF` 淡紫、`#F2E68C` 奶油黃、`#3AE31C` 螢光綠（狀態點）、文字近黑 `#1D1B20`。

## 2. 顏色令牌（`Design/Aurora.swift`）

| 令牌 | 淺色 | 深色 | 用途 |
| --- | --- | --- | --- |
| `Aurora.sky` | `#90BEF1` | `#1B2740` | 背景冷色、一般資訊 |
| `Aurora.lilac` | `#BAABCF` | `#2B2542` | 背景過渡紫 |
| `Aurora.periwinkle` | `#A090F1` | `#453B7A` | 背景重色 |
| `Aurora.blush` | `#F190A0` | `#5A2A36` | 暖色背景 |
| `Aurora.cream` | `#F2E68C` | `#3A3520` | 右上角奶油光斑 |
| `Aurora.brand` | `#A090F1` | `#B4A6FF` | 預設強調色（長春花） |
| `Aurora.coral` | `#F190A0` | `#FFA3B1` | 執行中、錯誤、未儲存 |
| `Aurora.azure` | `#90BEF1` | `#9CC8F7` | 連結、遠端同步 |
| `Aurora.mint` | `#3AE31C` | `#63F04B` | 已連線狀態點 |
| `Aurora.accent` | 依設定 | 依設定 | 目前強調色（`customAccent` → `accentChoice`） |
| `Aurora.panelTint` | 白 50% | 深底 50% | 玻璃面板上的提亮／壓暗層 |

漸層：

- `Aurora.wordmark`：粉色 → 藍色，用於標題與對話框標題。
- `Aurora.signature`：粉 → 強調色 → 藍，用於圖示底光與空狀態。
- `Aurora.canvas`：天藍 → 淡紫 → 長春花 → 天藍的斜向底。

面板材質（`PanelBackdrop`，跟隨「面板質感」設定）：

- `frosted`：`regularMaterial` + `panelTint`，預設。
- `solid`：`windowBackgroundColor`，適合喜歡乾淨實底的人。
- `clear`：`ultraThinMaterial`，讓背景圖更明顯。

內容卡：

- `cardSurface(radius:opacity:)`：`controlBackgroundColor` + 白邊 + 陰影，用於編輯器與下方結果面板；不透明度隨面板質感 76–98% 調整（保證程式碼可讀性）。
- `glassPanel(radius:borderOpacity:)`：磨砂 + 白邊 + 柔和陰影，用於側邊欄底部卡片、空狀態。

## 3. 可自訂外觀（設定 › 外觀）

所有選項即時生效並保存在 `UserDefaults`（bundle id `local.edward.LocalLab`），不需要重啟。

| 選項 | 按鍵 | 值 | 影響 |
| --- | --- | --- | --- |
| 強調色 | `accentChoice` | `periwinkle`（預設）/ `coral` / `sky` / `mint` | 選中膠囊描邊、主要按鈕、品牌晶片、終端提示符、極光光斑、視窗 tint |
| 自訂強調色 | `customAccent` | `RRGGBB` 十六進位；設定色環開啟系統色盤 | 覆寫上面四種預設；清除即回預設 |
| 極光節奏 | `auroraPace` | `still` / `slow` / `standard`（預設）/ `brisk` | 光斑漂移一輪 0 / 44 / 26 / 15 秒；靜止時完全停止 |
| 極光強度 | `auroraIntensity` | 0.4 – 1.8（預設 1.0） | 所有光斑與強調色光斑的強度倍率 |
| 面板質感 | `panelFinish` | `frosted`（預設）/ `solid` / `clear` | 側邊欄與狀態膠囊材質，連帶調整內容卡不透明度 |
| 圓角 | `cornerDensity` | `compact` 12 / `regular` 16（預設）/ `grand` 22 | 編輯器、下方結果面板、側邊欄底部卡片 |
| 動效節奏 | `motionLevel` | `calm` 0.55× / `standard` 1×（預設）/ `lively` 1.45× | 所有 spring 的 response 與 fade 時長倍率 |

設定頁上方有即時預覽卡：會自動在三個分段選項間巡覽（2.6 秒一次），顯示目前強調色、面板材質、圓角與動效節奏；「恢復預設外觀」可一鍵還原。

背景圖片仍由原本的 `BackgroundStore` 管理（`~/Library/Application Support/LocalLab/Background`），可調裁剪、比例、模糊與雙區域透明度；設了圖片就不顯示極光。

## 4. 動效令牌（`Motion`）

基礎曲線（乘以 `motionLevel` 的倍率）：

| 名稱 | 曲線 | 時長 | 用途 |
| --- | --- | --- | --- |
| `Motion.snappy` | spring(response 0.30, damping 0.82) | ≈0.30s | 點擊、頁籤切換、滑動膠囊、選取 |
| `Motion.gentle` | spring(response 0.48, damping 0.88) | ≈0.48s | 面板切換、橫幅出現、連線狀態、背景交替 |
| `Motion.quick` | easeOut 0.16s | 0.16s | 按壓回饋、hover、文字淡入 |
| `Motion.entrance` | spring(response 0.60, damping 0.90) | ≈0.60s | 視窗首次出現 |

## 5. 元件動效對照

| 觸發 | 元素 | 效果 | 曲線 |
| --- | --- | --- | --- |
| 啟動 | 整個工作區 | 96% 透明度、下移 6pt、99.3% 縮放淡入 | `entrance` |
| 點擊側邊欄按鈕 | 側邊欄 | 由左滑入／滑出 + 淡入淡出 | `gentle` |
| 切換下方頁籤 | 選中膠囊 | `matchedGeometryEffect` 滑動至新位置，內容交叉淡入 | `snappy` / `quick` |
| 切換 Markdown 檢視 | 三段膠囊 | 同上，白底膠囊滑動 | `snappy` |
| 按鈕按下 | 所有 `PressableStyle` 按鈕 | 縮至 96.5%、透明度 90% | `quick` |
| 滑鼠移入卡片／新增草稿 | `hoverLift` | 放大 1.004–1.012 + 陰影加深 | `snappy` |
| 連線中 | 狀態球 `StatusOrb` | 外圈 1.1s 順時針旋轉弧線 | 線性循環 |
| 已連線 | 狀態球 | 內點呼吸擴散，1.8s 循環 | 線性循環 |
| 執行中 | 結果晶片、狀態列晶片 | 圖示 0.85s 明暗呼吸，晶片淡入 | 線性循環 / `gentle` |
| 執行中（空結果） | 結果區圖示 | `PulseRing` 1.5s 擴散光環 | easeOut 循環 |
| 新輸出到達 | 結果項目 | 由下 8pt 滑入 + 淡入；文字更新仍滾到底 | `gentle` |
| 同步提示變化 | 狀態列文字 | `PopOnChange` 短暫放大 1.06 | `quick` |
| 終端輸入聚焦 | 輸入膠囊 | 描邊轉強調色、整體放大 1.004 | `snappy` |
| 遠端整理中 | 重新整理圖示 | 0.9s／圈持續旋轉 | 線性循環 |
| 出現錯誤 | 頂部橫幅 | 由上滑入 + 淡入；關閉時反向 | `gentle` |
| 切換自訂背景／極光 | 背景層 | 交叉淡入 | `gentle` |
| 長時間停留 | 極光背景 | 光斑依節奏漂移 + 極輕微 1.02 縮放呼吸 | easeInOut 循環 |
| 設定視窗 | 預覽卡 | 每 2.6 秒巡覽一次分段選項 | `snappy` |

## 6. 無障礙與效能

- 全部動效尊重系統「減少動態效果」：`PressableStyle`、`HoverLift`、`PulseDot`、`PulseRing`、`StatusOrb`、`PopOnChange`、極光漂移與設定頁預覽巡覽全部停用。
- 視窗不在前景（`controlActiveState == .inactive`）時極光停止漂移，避免無謂的 GPU 唤醒。
- 所有動畫皆為 SwiftUI 屬性動畫與單一 `matchedGeometryEffect`；唯一的計時迴圈是設定頁預覽（僅在設定視窗開啟時執行，`.task` 隨視窗關閉取消）。
- `CodeEditor` 的語法著色正則改為一次性編譯（`static let rules`），每次按鍵不再重新編譯三個 `NSRegularExpression`。

## 7. 刻意不改的部分

- 遠端同步節奏（15s 輪詢）、儲存流程（讀→比對→PUT→再讀確認）、衝突與 `.deleted-copy` 規則。
- 本機 Python 版本校驗、執行順序（本機成功才送伺服器）、核心清理。
- 編輯器快捷鍵（⌘N／⌘S／⌘Return／⌘.）、分頁內容、終端 PTY 行為。
- 自訂背景圖片的裁切、模糊、透明度語義；有背景圖時極光不顯示。
