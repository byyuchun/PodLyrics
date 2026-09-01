# PodLyrics

**English** | [中文](#中文)

Floating real-time transcript overlay for Apple Podcasts on macOS — like desktop lyrics, but for podcasts.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

- Always-on-top floating subtitle window, visible over any app and fullscreen Spaces
- Word-by-word highlighting, synced with the official Podcasts transcript panel
- Previous / current / next line display with smooth scrolling animation
- Draggable, translucent, menu-bar controlled — no Dock icon
- No configuration, no account, fully offline: reads the transcript Apple Podcasts already caches on your Mac

## How it works

- **Transcript data**: Apple Podcasts caches official episode transcripts locally as TTML files with word-level timestamps (under `~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache/Assets/TTML/`). The file for the currently playing episode is identified via MediaRemote's now-playing metadata.
- **Synchronization**: no clock guessing — the official transcript panel exposes its currently highlighted paragraph through the Accessibility API. PodLyrics reads that highlight, maps it back to the TTML timeline, and advances word highlighting inside the paragraph using the word timestamps and playback rate. The floating window and the official panel are driven by the same signal.
- **MediaRemote helper**: since macOS 15.4 the private MediaRemote framework only answers Apple-signed processes, so queries run inside an Apple-signed `/usr/bin/swift` interpreter subprocess that streams results back as JSON lines.
- If the transcript panel is not rendering (closed or minimized), PodLyrics automatically falls back to rate-based extrapolation and re-locks to the panel as soon as its highlight moves again.

## Requirements

- macOS 14 or later (developed and tested on macOS 26)
- Xcode Command Line Tools (`xcode-select --install`)
- An episode with an Apple-provided transcript (most English-language podcasts have one)

## Build

```bash
git clone https://github.com/byyuchun/PodLyrics.git
cd PodLyrics
swift build -c release
```

The binary is produced at `.build/release/PodLyrics`.

## First-time setup

1. **Start the app**:

   ```bash
   .build/release/PodLyrics &
   ```

2. **Grant Accessibility permission** (required for syncing with the transcript panel):
   - Open System Settings → Privacy & Security → Accessibility
   - Click **+**, press <kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>G</kbd> in the file dialog (`.build` is a hidden folder), enter the full path to `.build/release/PodLyrics`, and add it
   - Make sure its toggle is on. No restart needed.

3. **Open the transcript in Podcasts**: play an episode and click the transcript (speech bubble) button in the player. This caches the transcript locally and provides the sync signal. Keep the panel open for best accuracy — the Podcasts window can be covered by other windows or parked on another display/Space.

## Daily use

| Action | How |
| --- | --- |
| Move the window | Drag it anywhere |
| Hide / show | Click the menu-bar captions icon → “显示/隐藏字幕”, or right-click the window → hide |
| Quit | Right-click the window → quit, or menu-bar icon → 退出 |
| Start on demand | `.build/release/PodLyrics &` |
| Stop from terminal | `pkill -f PodLyrics` |

Tips:

- Playback position, speed changes (1×/1.5×/2×), seeking, and chapter jumps are all followed automatically.
- Minimizing the Podcasts window pauses its transcript panel; PodLyrics keeps scrolling on extrapolation and re-syncs the moment the window is visible again. For maximum precision, cover the window instead of minimizing it.
- If the overlay shows “字幕尚未缓存”, open the transcript panel once for that episode.

## Limitations

- Only works with episodes for which Apple provides a transcript.
- Relies on the private MediaRemote framework and the Podcasts accessibility tree; major macOS updates may require adjustments.

## License

MIT

---

# 中文

macOS 悬浮字幕工具：实时显示 Apple Podcasts 正在播放剧集的字幕，逐词高亮，类似音乐软件的桌面歌词。

## 功能

- 悬浮字幕窗置顶于所有应用与全屏 Space
- 逐词高亮，与官方字幕面板同步
- 上一句 / 当前句 / 下一句三行显示，平滑滚动动画
- 可拖动、半透明、菜单栏控制，无 Dock 图标
- 无需配置、无需账号、完全离线：直接读取 Podcasts 已缓存在本机的官方字幕

## 原理

- **字幕数据**：Apple Podcasts 会把剧集官方 transcript 缓存为带词级时间戳的 TTML 文件（位于 `~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache/Assets/TTML/`），当前播放剧集对应哪个文件由 MediaRemote 的 now-playing 信息给出。
- **同步方式**：不做时间估算——官方字幕面板当前高亮的段落会通过辅助功能（Accessibility）接口暴露，PodLyrics 读取该高亮并映射回 TTML 时间轴，段落内部再用词级时间戳按播放倍速推进逐词高亮。悬浮窗与官方面板由同一个信号驱动。
- **MediaRemote 绕行**：macOS 15.4 起 MediaRemote 私有框架只对 Apple 签名进程返回数据，因此查询在 Apple 签名的 `/usr/bin/swift` 解释器子进程中执行，结果以 JSON 行流式传回。
- 字幕面板不在渲染时（关闭或最小化），自动退回按倍速外推，面板高亮恢复移动后立即重新锁定。

## 环境要求

- macOS 14 及以上（在 macOS 26 上开发验证）
- Xcode Command Line Tools（`xcode-select --install`）
- 剧集需有 Apple 官方 transcript（英文播客覆盖率很高）

## 构建

```bash
git clone https://github.com/byyuchun/PodLyrics.git
cd PodLyrics
swift build -c release
```

产物位于 `.build/release/PodLyrics`。

## 首次配置

1. **启动应用**：

   ```bash
   .build/release/PodLyrics &
   ```

2. **授予辅助功能权限**（与字幕面板同步所必需）：
   - 打开 系统设置 → 隐私与安全性 → 辅助功能
   - 点 **+**，在文件选择框里按 <kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>G</kbd>（`.build` 是隐藏目录），输入 `.build/release/PodLyrics` 的完整路径并添加
   - 确认开关打开。无需重启应用。

3. **在 Podcasts 里打开字幕面板**：播放剧集，点击播放器上的字幕（气泡）按钮。这一步会把字幕缓存到本地，同时它就是同步信号源。保持面板打开精度最高——Podcasts 窗口可以被其他窗口盖住，或放到另一个显示器 / Space。

## 日常使用

| 操作 | 方式 |
| --- | --- |
| 移动悬浮窗 | 直接拖动 |
| 隐藏 / 显示 | 菜单栏字幕气泡图标 →「显示/隐藏字幕」，或右键悬浮窗 → 隐藏 |
| 退出 | 右键悬浮窗 → 退出，或菜单栏图标 → 退出 |
| 启动 | `.build/release/PodLyrics &` |
| 命令行停止 | `pkill -f PodLyrics` |

小贴士：

- 播放进度、倍速切换（1×/1.5×/2×）、拖进度条、章节跳转都会自动跟随。
- 最小化 Podcasts 窗口会使其字幕面板停止刷新；PodLyrics 会继续按倍速滚动，窗口恢复可见后立即重新对齐。想要最高精度，用其他窗口盖住它而不是最小化。
- 悬浮窗提示「字幕尚未缓存」时，给该集打开一次字幕面板即可。

## 限制

- 仅支持 Apple 提供 transcript 的剧集。
- 依赖 MediaRemote 私有框架与 Podcasts 辅助功能树结构，macOS 大版本升级后可能需要适配。

## 许可证

MIT
