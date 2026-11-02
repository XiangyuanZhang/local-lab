# Local Lab 視覺與動效規範

這份文件記錄 2026-11-02 這輪 UI 改造的設計依據、設計令牌與動效規則。所有改動只涉及外觀與過場，不改資料流、同步、執行或終端行為。

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
| `Aurora.periwinkle` | `#A090F1` | `#453B7A` | 品牌紫、背景重色 |
| `Aurora.blush` | `#F190A0` | `#5A2A36` | 暖色背景 |
| `Aurora.cream` | `#F2E68C` | `#3A3520` | 右上角奶油光斑 |
| `Aurora.brand` | `#A090F1` | `#B4A6FF` | 選中、焦點、主要按鈕 |
| `Aurora.coral` | `#F190A0` | `#FFA3B1` | 執行中、錯誤、未儲存 |
| `Aurora.azure` | `#90BEF1` | `#9CC8F7` | 連結、遠端同步 |
| `Aurora.mint` | `#3AE31C` | `#63F04B` | 已連線狀態點 |
| `Aurora.panelTint` | 白 50% | 深底 50% | 玻璃面板上的提亮／壓暗層 |

漸層：

- `Aurora.wordmark`：粉色 → 藍色，用於標題與對話框標題。
- `Aurora.signature`：粉 → 品牌紫 → 藍，用於圖示底光與空狀態。
- `Aurora.canvas`：天藍 → 淡紫 → 長春花 → 天藍的斜向底。

面板材質：

- `glassPanel(radius:borderOpacity:)`：`regularMaterial` + `panelTint` + 0.8pt 白邊 + 柔和陰影，用於側邊欄、狀態膠囊、空狀態卡。
- `cardSurface(radius:opacity:)`：`controlBackgroundColor` 93–94% 不透明 + 白邊 + 陰影，用於編輯器與下方結果面板（保證程式碼可讀性）。

## 3. 動效令牌（`Motion`）

| 名稱 | 曲線 | 時長 | 用途 |
| --- | --- | --- | --- |
| `Motion.snappy` | spring(response 0.30, damping 0.82) | ≈0.30s | 點擊、頁籤切換、滑動膠囊、選取 |
| `Motion.gentle` | spring(response 0.48, damping 0.88) | ≈0.48s | 面板切換、橫幅出現、連線狀態、背景交替 |
| `Motion.quick` | easeOut 0.16s | 0.16s | 按壓回饋、hover、文字淡入 |
| `Motion.entrance` | spring(response 0.60, damping 0.90) | ≈0.60s | 視窗首次出現 |

## 4. 元件動效對照

| 觸發 | 元素 | 效果 | 曲線 |
| --- | --- | --- | --- |
| 啟動 | 整個工作區 | 由 96% 透明度、下移 6pt 淡入 | `entrance` |
| 點擊側邊欄按鈕 | 側邊欄 | 由左滑入／滑出 + 淡入淡出 | `gentle` |
| 切換下方頁籤 | 選中膠囊 | `matchedGeometryEffect` 滑動至新位置，內容交叉淡入 | `snappy` / `quick` |
| 切換 Markdown 檢視 | 三段膠囊 | 同上，白底膠囊滑動 | `snappy` |
| 按鈕按下 | 所有 `PressableStyle` 按鈕 | 縮至 96.5%、透明度 90% | `quick` |
| 滑鼠移入卡片 | `hoverLift` | 放大 1.004 + 陰影加深 | `snappy` |
| 連線中／已連線 | 狀態圓點 `PulseDot` | 外圈呼吸擴散，1.8s 循環 | 線性循環 |
| 連線狀態變化 | 側邊欄底部卡片、終端標題晶片 | 文字與晶片淡入切換 | `gentle` |
| 執行狀態變化 | 結果頁籤「執行中」晶片 | 由 90% 縮放淡入 | `gentle` |
| 出現錯誤 | 頂部橫幅 | 由上滑入 + 淡入；關閉時反向 | `gentle` |
| 切換自訂背景／極光 | 背景層 | 交叉淡入 | `gentle` |
| 長時間停留 | 極光背景 | 光斑 26s 來回漂移 | easeInOut 循環 |
| 輸出文字更新 | 結果區 | 既有「滾到底部」行為保留，捲動本身不額外加動畫 | — |

## 5. 無障礙與效能

- 全部動效尊重系統「減少動態效果」：`PressableStyle`、`HoverLift`、`PulseDot` 會停用縮放與脈動，`AuroraBackground` 停止漂移。
- 設定頁新增「極光背景緩慢流動」開關（`@AppStorage("auroraMotion")`，預設開啟）。
- 視窗不在前景（`controlActiveState == .inactive`）時極光停止漂移，避免無謂的 GPU 唤醒。
- 所有動畫皆為 SwiftUI 屬性動畫與單一 `matchedGeometryEffect`，沒有計時器、沒有 CADisplayLink。
- `CodeEditor` 的語法著色正則改為一次性編譯（`static let rules`），每次按鍵不再重新編譯三個 `NSRegularExpression`。

## 6. 刻意不改的部分

- 遠端同步節奏（15s 輪詢）、儲存流程（讀→比對→PUT→再讀確認）、衝突與 `.deleted-copy` 規則。
- 本機 Python 版本校驗、執行順序（本機成功才送伺服器）、核心清理。
- 編輯器快捷鍵（⌘N／⌘S／⌘Return／⌘.）、分頁內容、終端 PTY 行為。
- 自訂背景圖片的裁切、模糊、透明度語義；有背景圖時極光不顯示。
