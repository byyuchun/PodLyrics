# PodLyrics

**English** | [中文](#中文)

Floating real-time transcript overlay for Apple Podcasts on macOS — like desktop lyrics, but for podcasts. Millisecond-accurate, fully offline.

![macOS](https://img.shields.io/badge/macOS-14.2%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## What it does

While you listen to an episode in Apple Podcasts, PodLyrics shows a translucent always-on-top window with the previous, current and next sentence of the official transcript, highlighting each word as it is spoken. It follows play/pause, seeking, skipping and speed changes, works over fullscreen apps, and needs no account, no internet and no configuration.

Unlike the built-in transcript panel, it stays visible over whatever you are doing, and it is synced to the **actual audio coming out of the Podcasts process**, not to an estimated clock.

## Features

- Always-on-top floating subtitle window, visible over any app and fullscreen Spaces
- Word-by-word highlighting with ±1 ms alignment to the audio you hear
- Previous / current / next line with smooth scrolling animation
- Handles dynamically inserted ads: subtitles stay correct after every ad break, and show "ad" while one plays
- Follows seeking, skip buttons, chapter jumps and 0.8×–2× playback speed
- Draggable, translucent, menu-bar controlled — no Dock icon
- Optional one-line sync monitor so you can see exactly what it is doing
- No configuration, no account, fully offline: everything comes from data Apple Podcasts already caches on your Mac

## Quick start

```bash
git clone https://github.com/byyuchun/PodLyrics.git
cd PodLyrics
swift build -c release
.build/release/PodLyrics &
```

Then, in Apple Podcasts:

1. **Download** the episode (the download arrow next to it). Downloaded episodes get audio-based sync; streaming episodes fall back to the transcript-panel method described below.
2. **Play** it and click the **transcript (speech bubble) button** in the player once. This makes Podcasts cache the transcript locally. You can close the panel afterwards.
3. The floating window appears at the bottom of your screen and starts following along within a few seconds.

Two macOS permissions may be requested on first run:

- **System Audio Recording** — PodLyrics listens to Podcasts' own audio output (only that process; never the microphone, never other apps). Allow it under System Settings → Privacy & Security → Screen & System Audio Recording.
- **Accessibility** — only needed for the fallback sync method used with streaming (non-downloaded) episodes. System Settings → Privacy & Security → Accessibility → **+** → press <kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>G</kbd> and enter the full path to `.build/release/PodLyrics` (`.build` is hidden).

## Requirements

- macOS 14.2 or later (developed and tested on macOS 26)
- Xcode Command Line Tools (`xcode-select --install`) — used both to build and, at runtime, as the Apple-signed `swift` interpreter for the MediaRemote helper
- An episode with an Apple-provided transcript (most English-language podcasts have one)

## Daily use

| Action | How |
| --- | --- |
| Move the window | Drag it anywhere |
| Hide / show | Menu-bar captions icon → “显示/隐藏字幕”, or right-click the window → hide |
| Show the sync monitor | Right-click the window → “显示同步监控” |
| Quit | Right-click the window → quit, or menu-bar icon → 退出 |
| Start | `.build/release/PodLyrics &` |
| Stop from a terminal | `pkill -x PodLyrics` |

### The sync monitor

Turn it on from the window's context menu. A small monospaced line appears under the subtitles, for example:

```
音频锁定 · 文件 6:31.93 · 字幕 5:43.04 (-48.9s) · 3 段
```

- **音频锁定 / 字幕面板 / 搜索中 / MediaRemote 外推** — which sync source is currently driving the subtitles, from most to least precise.
- **文件** — position inside the audio file Podcasts is playing.
- **字幕** — the corresponding position on the transcript's timeline, with the offset in parentheses. The offset is the cumulative length of inserted ads before this point.
- **N 段** — how many constant-offset segments the episode was split into (one more than the number of ad breaks found).
- **广告中** replaces the transcript position while an ad plays; the "next line" slot shows where the programme resumes.
- **正在校准时间轴…** appears for the first few seconds of a new episode while the ad map is being built.

If the subtitles ever look wrong, this line tells you whether the audio lock is held and which offset is being applied.

## How it works

**Transcript data.** Apple Podcasts caches official transcripts as TTML files with word-level timestamps under `~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache/Assets/TTML/`. The private MediaRemote framework tells us which transcript belongs to the episode playing now, and — for downloaded episodes — the path of the cached MP3.

**Audio alignment.** PodLyrics attaches a Core Audio *process tap* to Podcasts and keeps the last few seconds of its output in memory. Every two seconds it cross-correlates that buffer with the episode file on disk (FFT-based, via Accelerate). The correlation peak gives the exact file position at a known wall-clock instant; the overlay then advances from that anchor at the playback rate. At 1× this matches the raw waveform; at other speeds Podcasts time-stretches the audio so the waveform no longer lines up, and an onset-envelope correlation takes over. Measured jitter between consecutive locks is 0–1 ms at 1× and about 2 ms at 2×. CPU cost is well under 1%.

**Ad breaks.** Downloaded episodes usually contain dynamically inserted ads, while the TTML is timed against the clean programme, so a file position is off by the total ad length so far (49 s and 97 s in one test episode). Podcasts solves this for its own panel by shipping a ShazamKit signature of the clean audio next to every transcript. PodLyrics reads that signature, probes the file every 5 s against it, merges probes with the same offset into segments and refines the boundaries by bisection. The resulting piecewise map translates file time into transcript time; gaps are ads. Building the map takes about 3 s per episode and runs in the background.

**Seeking and speed changes.** A jump is detected by comparing MediaRemote's reported position with our own; the stale audio lock is dropped and a new search begins around the reported position, widening step by step up to the whole episode if MediaRemote's report turns out to be off (a full-episode search costs about a second). Re-lock typically takes 3–5 s after the last jump, because the captured buffer must be entirely post-seek audio.

**Fallbacks.** For streaming episodes there is no file to correlate against. PodLyrics then reads the paragraph the official transcript panel is highlighting through the Accessibility API, maps it back to the TTML timeline and extrapolates inside the paragraph — the panel must be open (it may be covered, but not minimized). With neither signal available it extrapolates from MediaRemote's reported position and rate.

**MediaRemote helper.** Since macOS 15.4 MediaRemote only answers Apple-signed processes, so the query runs inside the Apple-signed `/usr/bin/swift` interpreter as a child process that streams now-playing info back as JSON lines.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| “字幕尚未缓存” | Open the transcript panel once for this episode so Podcasts downloads the TTML. |
| “本集没有字幕” | Apple has not published a transcript for this episode. |
| Monitor shows 字幕面板 or MediaRemote 外推 for a downloaded episode | System Audio Recording permission was denied, or the tap failed. Check System Settings → Privacy & Security → Screen & System Audio Recording. |
| Monitor shows 搜索中 for more than ~10 s | Podcasts is not outputting audio (paused, muted, or routed to a device the tap cannot follow), or the file on disk differs from what is playing. |
| Subtitles freeze for a streaming episode | The Podcasts window is minimized; the panel stops rendering. Cover it instead. |
| Want detailed logs | Run with `PODLYRICS_DEBUG=1 .build/release/PodLyrics` — every lock, rejection and timeline segment is logged to stderr. |

## Limitations

- Only works with episodes for which Apple provides a transcript.
- Audio alignment and ad mapping require the episode to be downloaded; streaming episodes use the less precise panel-based sync.
- Relies on the private MediaRemote framework, Podcasts' cache layout and its accessibility tree; major macOS updates may require adjustments.

## License

MIT

---

# 中文

macOS 悬浮字幕工具：实时显示 Apple Podcasts 正在播放剧集的官方字幕，逐词高亮，类似音乐软件的桌面歌词。毫秒级同步，完全离线。

## 它是什么

你在 Apple Podcasts 里听节目时，PodLyrics 在屏幕上叠一个半透明、置顶的小窗，显示官方字幕的上一句 / 当前句 / 下一句，说到哪个词就亮哪个词。播放、暂停、拖进度条、快进快退、切倍速都会自动跟随，在全屏应用上也能显示；不需要账号、不需要联网、不需要任何配置。

和 Podcasts 自带的字幕面板不同，它始终浮在你正在做的事情上面，而且同步依据是 **Podcasts 进程真实输出的音频**，不是估算的时钟。

## 功能

- 悬浮字幕窗置顶于所有应用与全屏 Space
- 逐词高亮，与你听到的声音对齐误差 ±1 ms
- 上一句 / 当前句 / 下一句三行显示，平滑滚动动画
- 正确处理动态插入的广告：每段广告之后字幕依然对得上，广告播放时显示「广告中」
- 跟随拖进度条、快进快退按钮、章节跳转和 0.8×–2× 倍速
- 可拖动、半透明、菜单栏控制，无 Dock 图标
- 可选的一行同步监控，随时看清它在用什么信号、偏移多少
- 无需配置、无需账号、完全离线：所有数据都来自 Apple Podcasts 已经缓存在本机的内容

## 快速开始

```bash
git clone https://github.com/byyuchun/PodLyrics.git
cd PodLyrics
swift build -c release
.build/release/PodLyrics &
```

然后在 Apple Podcasts 里：

1. **下载**这一集（剧集旁边的下载箭头）。已下载的剧集走音频同步；在线流播的剧集退回到下文的字幕面板方式。
2. **播放**，并点一次播放器上的**字幕（气泡）按钮**，让 Podcasts 把字幕缓存到本地。之后面板可以关掉。
3. 屏幕底部出现悬浮窗，几秒内开始跟随。

首次运行 macOS 可能弹出两个权限请求：

- **系统音频录制** —— PodLyrics 只监听 Podcasts 自己的音频输出（仅这个进程；不开麦克风、不采其他应用）。在 系统设置 → 隐私与安全性 → 屏幕与系统音频录制 里允许。
- **辅助功能** —— 仅在线流播（未下载）剧集的回退同步需要。系统设置 → 隐私与安全性 → 辅助功能 → **+** → 按 <kbd>Cmd</kbd>+<kbd>Shift</kbd>+<kbd>G</kbd> 输入 `.build/release/PodLyrics` 的完整路径（`.build` 是隐藏目录）。

## 环境要求

- macOS 14.2 及以上（在 macOS 26 上开发验证）
- Xcode Command Line Tools（`xcode-select --install`）—— 编译需要，运行时也需要它提供的 Apple 签名 `swift` 解释器来查询 MediaRemote
- 剧集需有 Apple 官方 transcript（英文播客覆盖率很高）

## 日常使用

| 操作 | 方式 |
| --- | --- |
| 移动悬浮窗 | 直接拖动 |
| 隐藏 / 显示 | 菜单栏字幕气泡图标 →「显示/隐藏字幕」，或右键悬浮窗 → 隐藏 |
| 显示同步监控 | 右键悬浮窗 →「显示同步监控」 |
| 退出 | 右键悬浮窗 → 退出，或菜单栏图标 → 退出 |
| 启动 | `.build/release/PodLyrics &` |
| 命令行停止 | `pkill -x PodLyrics` |

### 同步监控

在悬浮窗右键菜单里打开，字幕下方会多一行等宽小字，例如：

```
音频锁定 · 文件 6:31.93 · 字幕 5:43.04 (-48.9s) · 3 段
```

- **音频锁定 / 字幕面板 / 搜索中 / MediaRemote 外推** —— 当前驱动字幕的同步源，精度从高到低。
- **文件** —— 在 Podcasts 正在播放的音频文件里的位置。
- **字幕** —— 对应到字幕时间轴上的位置，括号里是偏移量，等于这一点之前插入广告的累计时长。
- **N 段** —— 这一集被切成几个恒定偏移的分段（等于发现的广告数加一）。
- **广告中** —— 广告播放期间替代字幕位置显示，「下一句」位置会预告节目恢复后的第一句。
- **正在校准时间轴…** —— 切到新剧集的头几秒，正在后台建立广告映射。

字幕看起来不对时，看这一行就知道音频锁有没有握住、用的是哪个偏移。

## 原理

**字幕数据。** Apple Podcasts 会把官方 transcript 缓存为带词级时间戳的 TTML 文件（`~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache/Assets/TTML/`）。私有框架 MediaRemote 告诉我们当前播放的剧集对应哪个字幕文件，已下载的剧集还会给出缓存 MP3 的路径。

**音频对齐。** PodLyrics 对 Podcasts 进程挂一个 Core Audio 进程级 tap，把最近几秒的输出留在内存里，每 2 秒与磁盘上的剧集文件做一次互相关（基于 Accelerate 的 FFT）。相关峰给出「某个墙钟时刻对应文件里的精确位置」，悬浮窗以此为锚点按倍速推进。1× 时直接匹配波形；其他倍速下 Podcasts 做了保音高的时间拉伸，波形不再对齐，改用起音包络做互相关。实测相邻两次锁定之间抖动 1× 为 0–1 ms、2× 约 2 ms，CPU 占用远低于 1%。

**广告处理。** 下载的剧集通常含动态插入的广告，而 TTML 是按无广告的干净版本标的时间，所以文件位置会比字幕时间多出前面所有广告的总长（测试剧集里分别是 49 秒和 97 秒）。Podcasts 自己的解法是在每份字幕旁边附一份干净音频的 ShazamKit 指纹；PodLyrics 读取这份指纹，每 5 秒探测一次文件，把偏移一致的探测点合并成分段，再用二分把边界精确化。得到的分段映射把文件时间换成字幕时间，映射不到的空洞就是广告。整集建图约 3 秒，后台进行。

**拖动与倍速。** 通过比较 MediaRemote 上报的进度和我们自己的进度来发现跳转；发现后丢弃旧的音频锁，在上报位置附近重新搜索，连续找不到就逐级放宽，直到全集搜索（约 1 秒），以应对连按快进后 MediaRemote 上报滞后的情况。最后一次跳转后一般 3–5 秒重新锁定，因为要等采集缓冲完全变成跳转后的音频。

**回退。** 在线流播的剧集没有文件可比对，此时通过辅助功能接口读取官方字幕面板正在高亮的段落，映射回 TTML 时间轴并在段落内外推——面板需保持打开（可以被盖住，不能最小化）。两种信号都没有时，按 MediaRemote 上报的进度和倍速外推。

**MediaRemote 绕行。** macOS 15.4 起 MediaRemote 只对 Apple 签名进程返回数据，因此查询在 Apple 签名的 `/usr/bin/swift` 解释器子进程中执行，结果以 JSON 行流式传回。

## 故障排查

| 现象 | 原因 / 处理 |
| --- | --- |
| 「字幕尚未缓存」 | 给这一集打开一次字幕面板，让 Podcasts 下载 TTML。 |
| 「本集没有字幕」 | Apple 没有为这一集提供 transcript。 |
| 已下载剧集的监控显示「字幕面板」或「MediaRemote 外推」 | 系统音频录制权限被拒，或 tap 建立失败。检查 系统设置 → 隐私与安全性 → 屏幕与系统音频录制。 |
| 监控长时间（>10 秒）显示「搜索中」 | Podcasts 没有在输出音频（暂停、静音，或输出到 tap 跟不到的设备），或磁盘文件与正在播放的内容不一致。 |
| 在线流播剧集字幕停住 | Podcasts 窗口被最小化，面板停止渲染。用其他窗口盖住它即可。 |
| 想看详细日志 | `PODLYRICS_DEBUG=1 .build/release/PodLyrics`，每次锁定、拒绝和时间轴分段都会输出到 stderr。 |

## 限制

- 仅支持 Apple 提供 transcript 的剧集。
- 音频对齐和广告映射要求剧集已下载；在线流播的剧集使用精度较低的面板同步。
- 依赖 MediaRemote 私有框架、Podcasts 的缓存目录结构与辅助功能树，macOS 大版本升级后可能需要适配。

## 许可证

MIT
