# 材质规范

依据 Apple Human Interface Guidelines Materials 与 SwiftUI Liquid Glass 官方说明。

- 工具栏、导航与状态胶囊：macOS 26+ 使用系统 regular Liquid Glass，统一中性色 tint；旧系统回退 regularMaterial。
- 编辑器、文件栏、输出和 AI 面板：统一 ultraThinMaterial（材质层 opacity 0.68）、0.04 中性色遮罩、0.32 白色边框、0.8pt 线宽；不按组件自行改变模糊半径。
- 不在同一控件的父子层叠加玻璃；按钮仅以轻量状态底色表示按压。
- 系统“降低透明度”开启后使用不透明语义底色。
- 背景图片的高斯模糊仅用于图片预处理，不用于模拟面板材质；主区与侧栏已有透明度设置仍独立生效，额外遮罩上限统一为 0.35，避免与系统磨砂叠加后变得不透明。
- 原生全屏条使用 onHover，保留系统窗口操作；工作区按钮仅在界面内显示一次。

参考：
- https://developer.apple.com/design/human-interface-guidelines/materials
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/documentation/swiftui/windowtoolbarfullscreenvisibility/onhover
