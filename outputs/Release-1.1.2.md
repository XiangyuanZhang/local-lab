# Local Lab 1.1.2 发布记录

- 正式 App：`/Applications/Local Lab.app`，版本 1.1.2，构建 6。
- 源码：`/Users/edwardwilson/Documents/Codex/local-lab`。
- 发布：https://github.com/XiangyuanZhang/local-lab/releases/tag/v1.1.2
- 正式提交：e9f7fc5（PR #3）；main 检查：https://github.com/XiangyuanZhang/local-lab/actions/runs/41586192892
- 三项发布资产的 GitHub SHA256 与本地文件逐项一致；安装版本和严格签名校验通过。正式版启动恢复了服务器连接，无 Keychain 授权提示。
- 本机 7 组基础检查、12 组 AI/状态/HTTP 检查通过；学校服务器隔离 CRUD、执行输出、PNG、终端交互和清理重测通过。初次测试程序的 os 导入错误已修复，旧测试目录另以不读缓存的 GET 确认 404。
- 一次 DeepSeek 实测返回 deepseek-flash，共 628 tokens。未在发布包中包含 API Key 或个人 Jupyter 凭证。
- 未声称完成多小时稳定性、多显示器或全部辅助功能设置组合覆盖。详细证据：`docs/verification-1.1.2.md`。

发布后优化进入独立分支，不修改已发布标签。
