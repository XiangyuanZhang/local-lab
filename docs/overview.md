# Local Lab 项目完整说明

编写日期：2026-11-02。本文依据现存源码、README、发布清单、测试报告和暂停记录整理；本次只编写文档，不继续开发、重建或连接真实服务器。历史测试结果不代表当前服务或当前源码再次通过验证。

## 1. 项目目的与定位

Local Lab 是为用户在 Mac 上访问 TUM 学校 Jupyter 服务而开发的原生桌面应用。目标是在一个窗口内完成远端目录浏览、文本代码编辑、本机与服务器运行、输出查看、Markdown 阅读以及双端 shell 操作，减少在本机编辑器、浏览器和 terminal 之间反复切换。

最初设计参考 Apple Human Interface Guidelines，采用 macOS 原生侧边栏、工具栏、菜单、设置窗口、SF Symbols 和键盘操作。后续按用户要求调整为类似 PyCharm 的布局：左侧文件树，上方主编辑／目录区域，下方执行结果、本机 Terminal、服务器 Terminal 三个分页。

它的实际定位是 Python scratchpad 与远端文本文件客户端，不是完整 IDE，也不是原生 .ipynb 编辑器。遇到 Notebook 文件时交给 JupyterLab 打开。所谓同步，主要指 App 与 JupyterLab 对同一远端目录及文本文件的读取、显式保存和冲突处理；不包括两个文件系统的完整镜像。

## 2. 当前状态及交付边界

| 项目 | 当前记录 |
| --- | --- |
| 开发状态 | 2026-10-20 按用户要求暂停；后续协作转为环境配置辅助 |
| 已安装／已发布版本 | 1.0.1，面向 Apple Silicon，macOS 14+ |
| 发布方式 | 本机 .app 与 ZIP；使用固定本机证书签署，未做 Developer ID 公证或 App Store 发布 |
| 已发布 UI 修正 | 文件表格取消不透明交替行背景、侧边栏留白、本机 shell 提示符补空格修正、Terminal 横向滚动及左上对齐 |
| 未发布源码 | 独立“新建远端文件”入口、创建方法及其测试改动 |
| 未发布改动的验证 | 基础测试曾通过；整合回归出现“远端删除后保留本机副本”断言失败，未完成定位；不能视为可交付功能 |
| 构建缓存 | 暂停时删除 .build 和临时 UI 预览，清理约 773 MiB；首次恢复构建会重新生成 |
| 版本追溯 | 多次修正继续使用 1.0.1；应同时核对 release-manifest.json、SHA256SUMS 及对应测试日期 |

当前源码目录与已安装 App、发布 ZIP、源码 ZIP 不保证完全一致：最后一批远端新建文件修改只保存在源码目录，未重新打包发布。接手时不能仅凭“1.0.1”判断包含哪些修改。

## 3. 使用方法与主要工作流程

### 3.1 连接服务器

1. 保证学校主机的网络路径可达，必要时使用校园网或 VPN。
2. 在 App 的连接窗口提供个人 JupyterHub token。
3. 使用 token 的 Authorization 请求头连接固定的用户 API；不复用浏览器 cookie。
4. 获取已有核心清单，建立 App 专用 Python 核心，通过 kernel_info_reply 获取解释器版本。
5. 启用远端目录读取、文件同步和执行操作。
6. 正常退出时尝试关闭 App 专用 terminal 与核心，并再次查询确认远端对象已不存在。

源码固定的 API 地址为 `https://lecture.cs.tum.de:9000/user/go97lep/api`。它绑定现有用户路径，不是可配置的通用多账户 Jupyter 客户端。文档不包含 token 值。

README 中记录的 token scope 示例为 `access:servers!server=go97lep/`，只作为该项目当时的配置记录；实际权限及有效期由学校 JupyterHub 决定。保存到本机不会延长 token 的服务器有效期。

### 3.2 Python：本机先运行，成功后服务器复核

```text
编辑器代码快照
    ↓ 获取服务器完整 Python 版本
准备／核对相同 major.minor.patch 的本机解释器与 venv
    ↓
本机独立进程执行整个脚本
    ├─ 失败：显示退出码、stderr、traceback；不发送服务器
    └─ 成功：把同一代码快照发送至 App 专用 Jupyter 核心
                  ↓
            显示服务器输出，等待 execute_reply 与 idle
```

本机运行服务会生成临时脚本，以草稿名称编译执行，使错误信息中的文件名和行号对应编辑器；运行后清理临时目录。用户中断通过进程控制及服务器中断接口分别处理。

历史实测的本机与服务器版本均为 **Python 3.10.12**，项目打包了对应运行时。此结论来自 2026-10-13 的测试，不是学校全校统一要求的证明，也未在本次文档编写时重新检测。若服务器版本改变，App 会拒绝版本不匹配；可指定本机解释器，或在可用时通过 uv 准备相应版本。

“复核通过”表示两端均运行成功，没有自动比较两端输出是否完全一致。两次运行各有自己的文件、依赖和状态，且代码的写文件等副作用会分别发生。本机每次独立进程执行；远端核心会保留变量，直到断开／关闭核心。因此精确匹配 Python 版本仍不能保证运行环境完全等价。

### 3.3 远端文件与目录同步

- 左侧文件树可展开远端文件夹，切换文本文件；主区域提供名称、类型、大小、修改时间的目录表格。
- 每 15 秒刷新目录、已展开的文件夹以及当前远端文本文件；也可手动刷新。
- 文本文件读取上限为 1 MB；Notebook 使用浏览器中的 JupyterLab 打开。
- 用户按保存或 ⌘S 后才写回远端；本机草稿不会因为键入而立即上传。
- 已发布版本可把选中的本机草稿“另存至远端”，并可新建文件夹。
- 文件内容未在本机修改时，可接收远端更新；双方均修改时保留本机内容并提示冲突。
- 冲突处理先保留本机副本，再载入服务器版本。远端返回 404 确认删除时，保留本机副本并使用 `.deleted-copy` 名称。

保存技术流程为“读取当前内容 → 比对基线 → PUT → 再读确认”。这不是原子 compare-and-swap，不能消除检查和写入之间另一客户端修改文件的竞争。新建同名检查也不是原子 no-clobber 保证。应避免在 App 与 JupyterLab 同时保存同一文件。

独立的“新建远端文件”目前仅存在未发布源码，拟解决浏览远端目录时没有本机草稿可供另存的问题；计划在当前目录建立空文件、打开编辑、更新侧边栏，并拒绝已存在名称。由于回归尚未完成，不应描述为已发布可用。

### 3.4 两个 Terminal

本机 Terminal 使用自制 C PTY 桥接元件启动持续的 zsh shell，Swift 通过管道传入指令并接收输出。服务器 Terminal 使用 Jupyter terminals REST API 建立专用 shell，再经 WebSocket 传输 stdin/stdout。它们分别维持 shell 状态，可发送指令、回复 read、发送中断、重新连接及清除显示。

界面是可选择文字的 shell 输出记录，不是完整 VT/ANSI 终端模拟器；vim、top 等全屏 TUI 不在支持范围内。服务器 Terminal 指令直接在服务器执行，不经过 Python 编辑器的“先本机运行”流程。显示缓冲采用末尾 262,144 字符上限，README 的 256 KB 是近似描述。

### 3.5 Markdown 与背景

Markdown 由 WKWebView 本机渲染，提供预览、编辑、并排模式。Marked 解析 GFM，DOMPurify 清理 HTML，CSS 参考本机 Typora GitHub 风格；不调用第三方渲染服务。CSP 限制页面连接和资源加载，阻止文档脚本执行；普通外部／相对路径图片显示替代文字，data:image 另有代码处理。未实现完整 Typora 即时 WYSIWYG、数学公式或 Mermaid。

背景设置支持选图、拖动裁剪、比例切换、1–4 倍缩放、0–40 pt 模糊以及主操作区／侧边栏独立透明度。图片最长边导入缩至 3072 像素，输入文件上限 50 MB。确认后在本机保存原图副本、裁剪图和 JSON 设置；预览与取消不直接提交。整窗使用一张连续图片，两个区域分别叠加透明层。背景不上送服务器。

## 4. 技术路线与组件分工

| 层次 | 技术与职责 |
| --- | --- |
| App 与界面 | SwiftUI、AppKit；窗口、分栏、菜单、设置、原生文本编辑器 |
| 状态管理 | ObservableObject、@Published、@StateObject；WorkspaceStore 统一持有工作区状态 |
| 网络 | Foundation URLSession；REST 与 WebSocket 分离配置，系统 TLS 验证 |
| 核心通信 | Jupyter kernel_info_request／execute_request、parent request ID 匹配、execute_reply 与 idle 完成判定 |
| 长连接 | 持续接收、约每 20 秒心跳、执行前连通性检查；一次性 continuation 完成保护 |
| 本机执行 | Foundation Process、隔离临时脚本、stdout/stderr 收集、解释器精确版本检查 |
| Terminal | C forkpty／poll 桥接 + zsh；远端 Jupyter terminal WebSocket |
| Markdown | WebKit WKWebView + 本地 Marked／DOMPurify／CSS |
| 图像 | AppKit NSImage、ImageIO 缩略图／裁剪、SwiftUI 背景显示及模糊 |
| 持久化 | JSON 文件、Application Support、UserDefaults 偏好、macOS Keychain token |
| 构建 | SwiftPM，swift-tools-version 6.0，Swift 5 语言模式；CLT 与 shell 脚本 |
| 测试 | Swift async 断言程序、本机 aiohttp 模拟 Jupyter、原生 UI 操作与截图 |
| 打包 | Release 优化构建、.app bundle、codesign、ditto ZIP、SHA-256 校验 |

生产 App 没有前端开发服务器、Node.js 运行依赖或本机 HTTP 监听口；本机模拟器的 127.0.0.1:18768 只用于测试。UI 未最终依赖 Figma 作为实现来源。

## 5. 资源路径总表

以下为当前机器的绝对路径。用户目录、用户名和固定远端地址均具有机器／账户相关性，迁移时需要调整。用户运行数据路径是程序约定，不代表本次逐一读取了其中内容。

### 5.1 项目与交付物

| 资源 | 绝对路径 |
| --- | --- |
| 项目工作区 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268` |
| 应用源码根目录 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab` |
| Swift 源码 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab` |
| SwiftPM 清单 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Package.swift` |
| 项目说明 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/README.md` |
| 项目暂停记录 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/work/PROJECT_PAUSED.md` |
| 安装位置 | `/Applications/Local Lab.app` |
| 版本化 App | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/releases/1.0.1/Local Lab.app` |
| 版本化发布 ZIP | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/releases/1.0.1/LocalLab-1.0.1-macOS-arm64.zip` |
| 发布清单 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/releases/1.0.1/release-manifest.json` |
| 校验文件 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/releases/1.0.1/SHA256SUMS` |
| 便捷 App 副本 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/Local Lab.app` |
| 便捷发布 ZIP | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab-app.zip` |
| 已打包源码 ZIP（不含最后未发布修改） | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab-source.zip` |
| 构建缓存（已清除，可重建） | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/.build` |
| 私有签署资料目录（勿公开） | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/.local-signing` |

### 5.2 核心源码索引

| 文件 | 职责 |
| --- | --- |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/App/LocalLabApp.swift` | 启动入口、主窗口、命令菜单、设置、退出清理 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Stores/WorkspaceStore.swift` | 连接、草稿、运行状态、输出及错误管理 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Stores/RemoteSync.swift` | 远端目录缓存、轮询同步、保存、冲突／删除副本保护及未发布创建方法 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Stores/TerminalStore.swift` | 两个 terminal 的打开／重连、输出缓存、发送和关闭 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Services/JupyterClient.swift` | Jupyter REST、核心 WebSocket、心跳及一次性完成保护 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Services/LocalPythonRunner.swift` | Python 准备、精确版本校验、本机脚本运行与中断 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Services/ShellTerminal.swift` | 本机 shell 管道控制、远端 terminal 协议 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Services/TokenVault.swift` | Keychain 存储、静默读取与授权修复 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Services/DraftLibrary.swift` | 草稿 JSON 读写 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Services/BackgroundStore.swift` | 背景导入、裁剪保存、配置恢复与整窗图层 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Services/MarkdownHTML.swift` | Markdown HTML 模板、本地资源、CSP 与内容清理 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Services/AppLiveVerifier.swift` | 真实服务隔离功能检查；属于测试工具，不是闲置自动任务 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Views/ContentView.swift` | 整体分栏、工具栏、编辑区与弹窗 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Views/SidebarView.swift` | 本机草稿和远端文件树 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Views/RemoteBrowserView.swift` | 远端表格、目录导航、新建／另存名称弹窗 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Views/TerminalPane.swift` | terminal 输入、输出与滚动布局 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Views/BottomPanelView.swift` | 执行结果与两个 terminal 分页 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Views/CodeEditor.swift` | NSTextView 编辑及基础 Python 着色 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Views/OutputPane.swift` | 文本／错误／PNG 输出 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Views/MarkdownPreview.swift` | WKWebView 渲染及未改变内容的重绘去重 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Views/BackgroundEditor.swift` | 背景裁剪及透明度／模糊设置 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Views/ConnectionSheet.swift` | 连接和 token 操作 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Views/SettingsView.swift` | 编辑器、本机 Python、工作目录及凭据偏好 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Models/Workspace.swift` | 核心、草稿、输出及错误模型 |
| `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Sources/LocalLab/Models/RemoteFile.swift` | 远端条目、路径校验与文件服务协议 |

PTY C 桥接源码：`/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Support/ShellBridge.c`。打包后为 `.app/Contents/MacOS/LocalLabShellBridge`。

### 5.3 运行数据、依赖与配置

| 资源 | 路径 |
| --- | --- |
| 草稿 | `/Users/edwardwilson/Library/Application Support/LocalLab/drafts.json` |
| 默认本机工作目录 | `/Users/edwardwilson/Library/Application Support/LocalLab/Workspace` |
| 运行时目录 | `/Users/edwardwilson/Library/Application Support/LocalLab/Runtimes` |
| 3.10.12 虚拟环境 | `/Users/edwardwilson/Library/Application Support/LocalLab/Environments/3.10.12` |
| 默认 venv Python | `/Users/edwardwilson/Library/Application Support/LocalLab/Environments/3.10.12/bin/python3` |
| 运行临时脚本目录（按次清理） | `/Users/edwardwilson/Library/Application Support/LocalLab/Runs` |
| 背景配置与图片 | `/Users/edwardwilson/Library/Application Support/LocalLab/Background` |
| 背景设置 JSON | `/Users/edwardwilson/Library/Application Support/LocalLab/Background/settings.json` |
| 本地运行时压缩包 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Resources/python-3.10.12.tar.gz` |
| Marked | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Resources/marked.js` |
| DOMPurify | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Resources/purify.js` |
| Markdown 样式 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Resources/markdown.css` |
| 图标源图 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Resources/AppIcon.png` |
| macOS 图标 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Resources/AppIcon.icns` |

Marked 版本在 README 中记为 18.1.1，DOMPurify 为 3.4.17；授权文件分别为 Resources/marked-LICENSE 与 Resources/DOMPurify-LICENSE。图标来自用户提供的图片，长期资源以 Resources 内文件为准；聊天剪贴板临时路径不作为可恢复来源。

偏好设置使用 App 域 `local.edward.LocalLab` 的 UserDefaults，包括编辑字体大小、本机解释器路径、工作目录和自动连接偏好。Token 位于 macOS Keychain 的 generic password 项目，service 为 `local.edward.LocalLab`，account 为 `go97lep@lecture.cs.tum.de:9000`；不是一个可复制的明文 token 文件。本文不读取或导出 token、签署私钥及 keychain 密码。

### 5.4 构建、测试与记录

| 资源 | 路径 |
| --- | --- |
| 构建／运行／签署入口 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/script/build_and_run.sh` |
| Swift 工具链兼容封装 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/script/swift.sh` |
| 本机签署准备 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/script/setup_signing.py` |
| 原生测试入口 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/script/test.sh` |
| 主要断言测试 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Tests/Checks.swift` |
| Markdown 实际渲染测试 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Tests/MarkdownCheck.swift` |
| 本机 Jupyter 模拟器 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab/Tests/mock_jupyter.py` |
| 测试证据目录 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/app-test` |
| 历史完整测试报告 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/app-test/測試報告.md` |
| 本机先运行及双 terminal 轻量报告 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/app-test/輕量測試報告.md` |
| 长时卡顿调查资料 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/app-test/idle-investigation` |
| WindowServer 检查报告 | `/Users/edwardwilson/.codex/.chatgpt-projects/g-p-6acdcdd7b30c8191bfc44e7744162268/outputs/LocalLab-WindowServer檢查報告.md` |

原系统故障资料曾来自 `/Library/Logs/DiagnosticReports/` 与 `/Users/edwardwilson/Library/Logs/DiagnosticReports/`，可能随系统保留策略移动或删除；项目调查目录保存提取结果。不可把诊断原文中的账户、窗口或进程信息未经检查直接公开。

## 6. 构建与恢复步骤（说明，不在本次执行）

在源码根目录使用以下入口：

```sh
./script/build_and_run.sh --build-only
./script/build_and_run.sh --release
./script/test.sh
```

构建脚本在检测到 LocalLab 运行时会停止，要求先正常退出，以免跳过远端清理。默认入口支持构建并运行；另有 --verify、--debug、--logs、--telemetry。Release 构建生成优化程序、PTY 元件、资源、Info.plist，然后签署并做 deep／strict 校验。签署身份依赖原 `.local-signing/`，不能将它当作缓存删除或随源码 ZIP 公开。

本机模拟器依赖 Python aiohttp。启用模拟整合检查时：先运行 Tests/mock_jupyter.py，再设置 `LOCAL_LAB_TEST_API=http://127.0.0.1:18768/api` 运行 script/test.sh。不提供该环境变量会跳过模拟网络测试。Markdown 及合成 Keychain 检查由独立开关启用；不能仅见脚本退出成功就认定所有可选项已运行。

源包平台最低版本为 macOS 14，当前脚本面向 arm64；需要可用的 Xcode Command Line Tools／Swift 工具链。swift.sh 为现有 CLT 私有接口不一致做项目内兼容处理，不修改系统 SDK。清除 .build 后首次构建会重新生成编译及兼容缓存。

恢复开发前应先处理未完成创建功能的回归失败，确认源码与发布版差异，使用独立测试路径及合成凭据；不要直接用生产数据验证删除。随后更新版本或明确构建标识、重建发布 ZIP 并同步校验清单。

## 7. 已有验证及其边界

| 范围 | 历史证据 | 边界 |
| --- | --- | --- |
| 真实 TUM 服务 | 曾测试文件建立／修改／读回／删除、Python stdout/stderr/PNG、核心及 terminal 清理 | 只代表对应日期与构建，不是当前实时探测 |
| 本机先运行 | 实测成功后发送远端；失败与版本不匹配时阻止发送 | 套件和文件没有自动镜像 |
| 文件同步 | 模拟 REST／WebSocket、特殊文件名、冲突、删除后保留副本 | Contents API 保存仍存在并发窗口 |
| 心跳崩溃修正 | 10,000 次重复回呼、提前完成及取消保护检查通过 | 未完成所有真实网络条件的长期覆盖 |
| Markdown 去重 | 480 次内容未变更新只渲染一次，变更后继续渲染 | 不等于 480 次真实 15 秒轮询长测 |
| 2026-10-20 UI | 表格用隔离本机数据目测；已安装本机 terminal 返回 UI_LAYOUT_OK | 真实远端连接因 Keychain -25293 未复测 |
| 独立远端新建文件 | 添加代码与测试；整合回归失败尚未定位 | 未构建、安装或发布 |

README 中较早“测试均通过”“不再重复授权”的描述，应结合较新的发布清单和暂停记录阅读，不能覆盖后续观察到的问题。

## 8. 已知问题、诊断与局限

### 8.1 Keychain 授权

启动使用无交互 Keychain 读取以避免自动弹窗，保留“修复钥匙圈授权”入口。项目使用固定签署身份，仍观察到更新二进制后返回 `Keychain OSStatus -25293`，需要再次处理该项目授权。因此“每次更新后永久无需授权”没有被可靠解决。修复授权不是跳过系统保护，App 不修改系统 TLS 信任。

### 8.2 长时间卡顿与 WindowServer

用户曾报告 App 闲置 1–2 小时后系统严重卡顿、黑屏并回到登录画面。2026-10-13 的 WindowServer 报告显示其主线程 40 秒无响应后被 watchdog 终止；故障快照有 Chrome Renderer 约 6.38 GiB、Codex Renderer 约 1.49 GiB 的记录，并有分页面向磁盘等待等线索。

当时 Local Lab 已关闭，快照无法恢复它此前的峰值。短时 App 采样 footprint 约 54 MB、峰值约 81 MB，CPU 接近 0；关闭后 WindowServer 仍高负载。但这不足以排除 App 的延迟型图形／内存问题，调查没有完成 1–2 小时已连线、背景开关的完整对照测试。现有判断偏向整体内存／图形系统压力，不能将其写成已证实的唯一根因，也不能宣称已修复系统卡顿。

另发现三份 Local Lab 自身崩溃指向 JupyterClient.ping 的 continuation 重复完成；已加锁保护一次性回呼，并减少未变化 Markdown 重绘。这是有证据的应用缺陷修正，与 WindowServer 故障的因果关系没有被证实。

### 8.3 其他限制

- 非完整 Notebook 编辑器、非完整 IDE，基础语法着色不等于代码诊断或调试器。
- Python 编辑器未提供 kernel stdin 的 input() 交互；shell 的 read 可通过 terminal 输入。
- 输出主要是文字和 PNG，未开放任意 HTML/JavaScript 执行。
- UI 未提供文件删除按钮；用户仍可在 terminal 操作，或使用 JupyterLab。
- 断网、token 过期、强制退出可能遗留远端专用对象；应在 JupyterLab 检查清理。
- 远端连接固定为现有账户地址；不同用户、课程、服务器版本需重新配置。
- 本机运行用户代码会有真实系统副作用；它不是安全沙箱。

## 9. 维护与交接建议

项目目前保持暂停，不应把文档编写视为恢复开发授权。若仅辅助环境配置，以实际课程说明、服务器 kernel 版本、当前解释器和依赖清单为依据；不要把历史 3.10.12 误写为学校当前官方统一要求。

如果未来恢复项目，建议依次完成：未发布创建功能回归定位、凭据升级授权问题处理、长时间资源监测与背景对照、连接地址配置化、清晰版本／构建编号。发布时源码 ZIP 排除 .build、.git、.local-signing 与私人运行数据，校验 ZIP 的 SHA-256，保留每次构建对应的测试结果。

## 10. 设计和技术参考

以下为项目采用过的技术参考入口，不表示本次重新验证了其最新内容：

- [Apple Design](https://developer.apple.com/design/)
- [Apple Human Interface Guidelines — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Apple：Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)
- [Apple：Inside Code Signing Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- [Apple：kSecAttrAccess](https://developer.apple.com/documentation/security/ksecattraccess)
- [uv：Python versions](https://docs.astral.sh/uv/concepts/python-versions/)

内部依据以源码、README、release-manifest.json、work/PROJECT_PAUSED.md 和各阶段测试报告为主；出现冲突时优先看相关代码及较新、明确注明构建和日期的测试记录。本文未导出任何凭据，也未对学校服务器进行写入。
