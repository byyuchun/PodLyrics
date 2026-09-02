# PodLyrics

**English** | [中文](#中文)

Floating real-time transcript overlay for Apple Podcasts on macOS — like desktop lyrics, but for podcasts.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

- Always-on-top floating subtitle window, visible over any app and fullscreen Spaces
- Word-by-word highlighting, synced with the official Podcasts transcript panel
- Previous / current / next line display with smooth scrolling animation
- Draggable, translucent, menu-bar controlled — no Dock icon
- No configuration, no account: reads the transcript Apple Podcasts already caches on your Mac
- Waveform alignment for tighter word timing — **the episode must be downloaded in Podcasts**, not streamed

## How it works

- **Transcript data**: Apple Podcasts caches official episode transcripts locally as TTML files with word-level timestamps (under `~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache/Assets/TTML/`). The file for the currently playing episode is identified via MediaRemote's now-playing metadata.
- **Synchronization**: MediaRemote gives the playhead (how far the episode has already played). PodLyrics then matches a short snippet of system audio against the local episode file and applies that small waveform offset to the playhead before looking up TTML words. Seeking follows the new playhead immediately; the next snippet re-fits the offset around the new time.
- **Local episode file**: waveform alignment needs the complete audio on disk. Download the episode in Apple Podcasts (the download button on the episode). Streaming-only playback has no stable local file to correlate against. If Podcasts has not downloaded it yet, PodLyrics will fetch the enclosure into `~/Library/Caches/PodLyrics/assets/` — downloading in Podcasts first is still the reliable path.
- **Official panel**: while the transcript panel is open, a paragraph jump that the playhead does not yet know about (skip / scrub) is followed until MediaRemote catches up.
- **MediaRemote helper**: since macOS 15.4 the private MediaRemote framework only answers Apple-signed processes, so queries run inside an Apple-signed `/usr/bin/swift` interpreter subprocess that streams results back as JSON lines.

## Requirements

- macOS 14 or later (developed and tested on macOS 26)
- Xcode Command Line Tools (`xcode-select --install`)
- An episode with an Apple-provided transcript (most English-language podcasts have one)
- That episode **downloaded to this Mac** in Apple Podcasts (not stream-only)
- Screen Recording permission (used only to capture Podcasts audio for waveform alignment)

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

3. **Download the episode in Podcasts**: open the episode and tap the download button so the audio is stored on this Mac. Streaming is not enough for waveform alignment.

4. **Grant Screen Recording permission** (required to capture the playing audio):
   - Open System Settings → Privacy & Security → Screen Recording
   - Add `.build/release/PodLyrics` the same way as in step 2, and turn it on

5. **Open the transcript in Podcasts**: play the downloaded episode and click the transcript (speech bubble) button in the player. This caches the transcript locally. Keep the panel open when seeking — a skip is picked up faster from the official highlight. The Podcasts window can be covered by other windows or parked on another display/Space.

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
- If word timing feels loose, confirm the episode shows as downloaded in Podcasts (not just in your queue) and that Screen Recording is enabled for PodLyrics.

## Limitations

- Only works with episodes for which Apple provides a transcript.
- Waveform alignment needs a local audio file. Download the episode in Podcasts before playing; stream-only playback falls back to the transcript panel / playhead extrapolation.
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
- 无需配置、无需账号：直接读取 Podcasts 已缓存在本机的官方字幕
- 用本地音频做波形对齐，逐词更跟口型——**剧集必须先在 Podcasts 里下载到本机**，只在线播放不够

## 原理

- **字幕数据**：Apple Podcasts 会把剧集官方 transcript 缓存为带词级时间戳的 TTML 文件（位于 `~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache/Assets/TTML/`），当前播放剧集对应哪个文件由 MediaRemote 的 now-playing 信息给出。
- **同步方式**：MediaRemote 给出已经播到第几分几秒。PodLyrics 再把一小段系统声音和本机音频文件做波形对齐，把这个很小的偏移加到播放进度上，然后去 TTML 里取词。快进先跟新的播放进度，下一段录音再在新位置重新对齐。
- **本地音频**：波形对齐需要完整的音频文件。请在 Apple Podcasts 里点该集的下载按钮，把它存到这台 Mac 上；只在线播放没有稳定的本地文件可对。若 Podcasts 还没下完，应用会把 enclosure 拉到 `~/Library/Caches/PodLyrics/assets/`——仍然更推荐先在 Podcasts 里下载。
- **官方面板**：字幕面板开着时，若面板已经跳到播放进度还不知道的段落（快进 / 拖进度条），会先跟面板，等 MediaRemote 追上。
- **MediaRemote 绕行**：macOS 15.4 起 MediaRemote 私有框架只对 Apple 签名进程返回数据，因此查询在 Apple 签名的 `/usr/bin/swift` 解释器子进程中执行，结果以 JSON 行流式传回。

## 环境要求

- macOS 14 及以上（在 macOS 26 上开发验证）
- Xcode Command Line Tools（`xcode-select --install`）
- 剧集需有 Apple 官方 transcript（英文播客覆盖率很高）
- **该集必须已在 Podcasts 下载到本机**（不能只是在线播）
- 需要屏幕录制权限（只用来采集 Podcasts 正在播出的声音，做波形对齐）

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

3. **在 Podcasts 里下载本集**：打开剧集，点下载按钮，等音频存到这台 Mac。只在线播放无法做波形对齐。

4. **授予屏幕录制权限**（采集正在播放的声音所必需）：
   - 打开 系统设置 → 隐私与安全性 → 屏幕录制
   - 用和第 2 步相同的方式加入 `.build/release/PodLyrics`，并打开开关

5. **在 Podcasts 里打开字幕面板**：播放已下载的剧集，点击播放器上的字幕（气泡）按钮。这一步会把字幕缓存到本地。快进时请保持面板打开，官方高亮能更快跟上跳段。Podcasts 窗口可以被其他窗口盖住，或放到另一个显示器 / Space。

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
- 逐词对不齐时，先确认 Podcasts 里该集已显示为已下载（不是只在收听队列里），并且给 PodLyrics 开了屏幕录制。

## 限制

- 仅支持 Apple 提供 transcript 的剧集。
- 波形对齐需要本地音频文件。播放前请先在 Podcasts 下载本集；只在线播放时会退回字幕面板 / 播放进度外推。
- 依赖 MediaRemote 私有框架与 Podcasts 辅助功能树结构，macOS 大版本升级后可能需要适配。

## 许可证

MIT
