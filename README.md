# PodLyrics

Floating real-time transcript overlay for Apple Podcasts on macOS — like desktop lyrics, but for podcasts.

macOS 悬浮字幕工具：实时显示 Apple Podcasts 正在播放剧集的字幕，逐词高亮，类似音乐软件的桌面歌词。

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## 原理

- **字幕数据**：Apple Podcasts 会把剧集的官方 transcript 缓存在本地（带词级时间戳的 TTML 文件），路径在 `~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache/Assets/TTML/`。当前播放剧集对应哪个文件，从 MediaRemote 的 now-playing 信息里拿（`UserInfo.podEpTrId`）。
- **同步方式**：不做时间估算，直接跟随官方字幕面板——面板当前高亮的段落会通过辅助功能（Accessibility）接口暴露出来，读到它就能映射回 TTML 里的时间窗口，悬浮窗和官方面板由同一个信号驱动。段落内部再用词级时间戳按倍速推进逐词高亮。
- **MediaRemote 绕行**：macOS 15.4+ 起 MediaRemote 私有接口只对 Apple 签名进程返回数据，所以查询跑在一个 `/usr/bin/swift` 解释器 helper 子进程里，JSON 行流式传回主应用。

## 构建与运行

```bash
swift build -c release
.build/release/PodLyrics &
```

首次运行需要授权：

1. **辅助功能**：系统设置 → 隐私与安全性 → 辅助功能，添加并勾选 PodLyrics 二进制（文件选择框里按 Cmd+Shift+G 输入路径，`.build` 是隐藏目录）。
2. 在 Apple Podcasts 里**打开字幕面板**（点击播放器上的字幕按钮）——这是同步的信号源，保持打开效果最准。

## 使用

- 悬浮窗置顶于所有窗口和全屏 Space，可拖动。
- 右键悬浮窗：隐藏 / 退出。
- 菜单栏字幕气泡图标：显示/隐藏、退出。

## 限制

- 仅支持 Apple 官方提供 transcript 的剧集（英文播客覆盖率高）。
- 某集如从未打开过字幕面板，本地可能还没缓存 TTML，悬浮窗会提示。
- 关闭字幕面板时退回 MediaRemote 外推模式，精度略降。
- 依赖 MediaRemote 私有 API 与 Podcasts 的辅助功能树结构，系统大版本升级可能需要适配（当前在 macOS 26 上验证）。

## Known issues

- 偶发悬浮字幕停住不动，快进/换段后恢复（面板文本与 TTML 匹配失败的边界情况，修复中）。

## License

MIT
