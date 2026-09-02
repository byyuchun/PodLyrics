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
- **Audio alignment (primary sync)**: for downloaded episodes, MediaRemote also reports the path of the cached MP3. PodLyrics taps Podcasts' own audio output with a Core Audio process tap (no microphone, no other apps), and every two seconds cross-correlates the last few seconds of that output against the file on disk. The correlation peak gives the exact playback position — measured jitter is within ±1 ms at 1× and ±2 ms at 1.5×/2×, where an onset-envelope matcher takes over because time-stretched audio no longer matches the waveform sample-for-sample. Everything stays offline; typical CPU cost is well under 1%.
- **Transcript panel (fallback)**: when the episode is streaming rather than downloaded, the official transcript panel exposes its currently highlighted paragraph through the Accessibility API. PodLyrics reads that highlight, maps it back to the TTML timeline, and advances word highlighting inside the paragraph using the word timestamps and playback rate.
- **MediaRemote helper**: since macOS 15.4 the private MediaRemote framework only answers Apple-signed processes, so queries run inside an Apple-signed `/usr/bin/swift` interpreter subprocess that streams results back as JSON lines.
- If neither audio lock nor panel is available, PodLyrics falls back to rate-based extrapolation from MediaRemote's reported position and re-locks as soon as either signal returns. After a seek or speed change the audio lock is re-established within about 3–5 seconds (the captured buffer must first be entirely post-seek).

## Requirements

- macOS 14.2 or later (developed and tested on macOS 26)
- Xcode Command Line Tools (`xcode-select --install`)
- An episode with an Apple-provided transcript (most English-language podcasts have one)
- For audio alignment: the episode must be downloaded in Podcasts (streaming episodes fall back to panel sync)

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

2. **Grant Accessibility permission** (required for the transcript-panel fallback):
   - Open System Settings → Privacy & Security → Accessibility
   - Click **+**, press <kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>G</kbd> in the file dialog (`.build` is a hidden folder), enter the full path to `.build/release/PodLyrics`, and add it
   - Make sure its toggle is on. No restart needed.

3. **Open the transcript in Podcasts once**: play an episode and click the transcript (speech bubble) button in the player. This caches the transcript locally. For downloaded episodes you can close the panel afterwards — audio alignment does not need it. For streaming episodes keep it open; the Podcasts window can be covered by other windows or parked on another display/Space.

Audio alignment uses a Core Audio process tap on Podcasts. macOS may show a one-time "System Audio Recording" prompt the first time PodLyrics starts the tap; allow it (System Settings → Privacy & Security → Screen & System Audio Recording). If denied, PodLyrics silently keeps using the transcript-panel sync.

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
- Downloaded episodes get audio alignment and are immune to the Podcasts window being minimized or hidden. For streaming episodes, minimizing the window pauses its transcript panel; PodLyrics keeps scrolling on extrapolation and re-syncs the moment the window is visible again — cover the window instead of minimizing it.
- If the overlay shows “字幕尚未缓存”, open the transcript panel once for that episode.
- Run with `PODLYRICS_DEBUG=1` to log every audio lock (position, confidence, deviation from MediaRemote) to stderr.

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
- **音频对齐（主同步源）**：已下载的剧集，MediaRemote 会一并给出本地缓存 MP3 的路径。PodLyrics 用 Core Audio 进程级 tap 只采集 Podcasts 自己的输出（不开麦克风、不采其他应用），每 2 秒把最近几秒的输出与磁盘文件做互相关，峰值位置就是精确播放进度——实测 1× 抖动在 ±1 ms 内，1.5×/2× 在 ±2 ms 内（变速后波形不再逐样本匹配，改用起音包络匹配）。全程离线，CPU 占用远低于 1%。
- **字幕面板（回退）**：在线流播（未下载）的剧集，官方字幕面板当前高亮的段落会通过辅助功能（Accessibility）接口暴露，PodLyrics 读取该高亮并映射回 TTML 时间轴，段落内部再用词级时间戳按播放倍速推进逐词高亮。
- **MediaRemote 绕行**：macOS 15.4 起 MediaRemote 私有框架只对 Apple 签名进程返回数据，因此查询在 Apple 签名的 `/usr/bin/swift` 解释器子进程中执行，结果以 JSON 行流式传回。
- 音频锁定和面板都不可用时，按 MediaRemote 上报的进度做倍速外推，任一信号恢复后立即重新锁定。拖进度条或切换倍速后，音频锁定约 3–5 秒内重建（需要等采集缓冲完全变成新位置的音频）。

## 环境要求

- macOS 14.2 及以上（在 macOS 26 上开发验证）
- Xcode Command Line Tools（`xcode-select --install`）
- 剧集需有 Apple 官方 transcript（英文播客覆盖率很高）
- 音频对齐要求剧集已在 Podcasts 里下载（在线流播的剧集回退到面板同步）

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

2. **授予辅助功能权限**（字幕面板回退同步所需）：
   - 打开 系统设置 → 隐私与安全性 → 辅助功能
   - 点 **+**，在文件选择框里按 <kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>G</kbd>（`.build` 是隐藏目录），输入 `.build/release/PodLyrics` 的完整路径并添加
   - 确认开关打开。无需重启应用。

3. **在 Podcasts 里打开一次字幕面板**：播放剧集，点击播放器上的字幕（气泡）按钮，字幕会被缓存到本地。已下载的剧集之后可以关掉面板——音频对齐不依赖它；在线流播的剧集请保持面板打开，Podcasts 窗口可以被其他窗口盖住，或放到另一个显示器 / Space。

音频对齐会对 Podcasts 建立 Core Audio 进程 tap，首次启动时 macOS 可能弹出一次「系统音频录制」授权提示，请允许（系统设置 → 隐私与安全性 → 屏幕与系统音频录制）。若拒绝，PodLyrics 会静默继续使用字幕面板同步。

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
- 已下载的剧集走音频对齐，不受 Podcasts 窗口最小化/隐藏影响。在线流播的剧集最小化窗口会使字幕面板停止刷新；PodLyrics 会继续按倍速滚动，窗口恢复可见后立即重新对齐——用其他窗口盖住它而不是最小化。
- 悬浮窗提示「字幕尚未缓存」时，给该集打开一次字幕面板即可。
- 用 `PODLYRICS_DEBUG=1` 启动可在 stderr 看到每次音频锁定的位置、置信度和相对 MediaRemote 的偏差。

## 限制

- 仅支持 Apple 提供 transcript 的剧集。
- 依赖 MediaRemote 私有框架与 Podcasts 辅助功能树结构，macOS 大版本升级后可能需要适配。

## 许可证

MIT
