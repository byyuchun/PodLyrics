# PodLyrics

**中文** | [English](#english)

听 Apple Podcasts 时，把官方逐词字幕叠在桌面上——类似桌面歌词，专门给播客用。已下载的剧集会按你听到的声音对齐；超出你水平的词会在字幕里标出中文释义，并带剧集词表和生词本，听前预习、听后复盘。

![macOS](https://img.shields.io/badge/macOS-14.2%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

不需要账号。默认完全离线：字幕、对齐和词典都来自本机已有数据。可选的语境释义才会访问你自己配置的模型接口。

## 功能

- 半透明置顶悬浮窗，可拖动，盖在其他应用和全屏 Space 上；无 Dock 图标，由菜单栏控制
- 上一句 / 当前句 / 下一句，说到哪个词就亮哪个词
- 已下载剧集：用 Podcasts 进程的真实音频对齐字幕，并处理动态插入的广告（广告时段当前行留空，「下一句」预告节目恢复处）
- 跟随暂停、拖进度条、跳过、章节跳转和倍速（Podcasts 支持的 0.8×–2×）
- 在线流播（未下载）时退回官方字幕面板同步，精度较低
- 可选一行同步监控，显示当前同步源和偏移
- **词汇标注**（默认按「四级」）：高于你水平的词显示为 `word(释义)`；每集有词表和全文；生词本带本机例句；可接入自己的 OpenAI 兼容接口做语境释义

## 环境要求

- macOS 14.2 或更高（需要 Core Audio process tap；在较新的 macOS 上开发，含 macOS 26）
- [Xcode Command Line Tools](https://developer.apple.com/download/all/?q=command%20line%20tools)（`xcode-select --install`）：编译需要；运行时也要用到带 Apple 签名的 `/usr/bin/swift` 去查询 MediaRemote
- 剧集需有 Apple 官方 transcript（英文节目覆盖率较高）

## 安装

```bash
git clone https://github.com/byyuchun/PodLyrics.git
cd PodLyrics
./make-app.sh --install   # 编译 PodLyrics.app 并安装到 /Applications
```

只生成当前目录下的 `.app`、不安装：`./make-app.sh`。

之后从启动台或 Spotlight 打开 **PodLyrics**。它只出现在菜单栏（字幕气泡图标），没有 Dock 图标。开机自启：系统设置 → 通用 → 登录项 → **+** → PodLyrics。

也可以直接跑二进制：

```bash
swift build -c release && .build/release/PodLyrics &
```

## 第一次使用

1. 打开 PodLyrics。屏幕底部中央出现半透明悬浮窗（还没在播时显示「等待播放…」），菜单栏出现气泡图标。
2. 按系统提示授权：
   - **辅助功能** — 启动时就会请求。音频锁还没握住时（在线流播，或已下载但仍在搜索），用来读官方字幕面板正在高亮的段落。系统设置 → 隐私与安全性 → 辅助功能 → **+** → 选 `/Applications/PodLyrics.app`。若跑的是裸二进制，按 <kbd>⌘</kbd><kbd>⇧</kbd><kbd>G</kbd> 输入 `.build/release/PodLyrics` 的完整路径（`.build` 是隐藏目录）。
   - **屏幕与系统音频录制** — 第一次对已下载剧集做音频对齐时会问。只监听 Podcasts 这一个进程的输出，不录麦克风、不采其他应用。系统设置 → 隐私与安全性 → 屏幕与系统音频录制。
3. 在 Apple Podcasts 里：
   1. **下载**这一集（剧集旁的下载箭头）。已下载走音频对齐；只在线播放则走字幕面板回退。
   2. **播放**，并点一次播放器上的**字幕（气泡）按钮**，让 Podcasts 把 TTML 缓存到本机。音频锁定之后可以关掉面板；走字幕面板回退时需要保持打开（见下方限制）。
4. 悬浮窗在检测到播放后开始跟读。右键悬浮窗 → **我的水平**，把档位调成你的水平（默认 **四级**）。该档及以下的词不标，只标更难的词。

第一次访问 Podcasts 的缓存目录时，系统也可能再弹一次文件夹权限，允许即可。

## 日常使用

| 操作 | 方式 |
| --- | --- |
| 移动悬浮窗 | 直接拖动 |
| 隐藏 / 显示 | 菜单栏图标 →「显示/隐藏字幕」，或右键悬浮窗 →「隐藏（菜单栏图标可再显示）」 |
| 窗口拖丢了 | 菜单栏图标 →「重置字幕位置」（回到屏幕底部中央） |
| 再显示出来 | 启动台 / Spotlight 再点一次 PodLyrics（已在运行时会把悬浮窗唤回可见区域） |
| 调整我的水平 | 右键悬浮窗 →「我的水平」，或主窗口 → 设置 / 剧集页工具栏 |
| 打开主窗口 | 菜单栏图标 →「打开 PodLyrics…」，或右键悬浮窗 |
| 同步监控 | 右键悬浮窗 →「显示同步监控」 |
| 退出 | 菜单栏图标 →「退出」，或右键悬浮窗 →「退出 PodLyrics」 |
| 命令行停止 | `pkill -x PodLyrics` |

菜单栏菜单上标了快捷键：<kbd>⌘O</kbd> 打开主窗口，<kbd>⌘T</kbd> 显示/隐藏字幕，<kbd>⌘R</kbd> 重置位置，<kbd>⌘Q</kbd> 退出。它们是该菜单的快捷键，不是系统全局热键。

### 主窗口

菜单栏 →「打开 PodLyrics…」：

- **剧集库** — 本机已缓存字幕的剧集（在 Podcasts 里打开一次字幕面板就会出现）。可搜索节目/标题。选中一集看 **词表**（按档位分组，带释义、次数、例句）或带标注的 **全文**。听前预习、听后复盘用的是同一页；书签收入生词本，勾选标为已掌握。
- **生词本** — 收藏的词，以及它们在本机哪些剧集的哪句话里出现过。工具栏可切到 **已掌握**。
- **设置** —「我的水平」和可选的语境释义。

空的剧集库会提示：「没有已缓存字幕的剧集」——先去 Podcasts 打开一次字幕面板。

### 词汇学习

内置一份裁剪过的 [ECDICT](https://github.com/skywind3000/ECDICT) 1.0.28（约 4.3 万词条，约 7 MB，离线）。字幕里的词会还原到原形（`negotiated → negotiate`），并对应考试档位：初中 / 高中 / 四级 / 六级 / 考研 / 托福雅思 / GRE。

**我的水平**可选初中到托福雅思（没有 GRE：选「我认识全部 GRE 词」就没什么可标了）。GRE 档的词一律视为高于你的水平，会被标注。默认四级。两个个人列表会覆盖档位：

- **生词本**里的词无论多简单都标
- **已掌握**的词无论多难都不标
- 不在词典里的词（人名、品牌等）永不标注

**语境释义（可选，默认关）。** ECDICT 给通用释义；播客里一个词常用某个义项（*pitch*、*chunk*）。设置里打开「启用语境释义」，填任意 OpenAI 兼容接口的 Base URL（填到 `/v1` 即可）、模型名和 API Key，然后点「保存」。可先「测试连接」。开启后，当前被标注的词连同各自首次出现的句子会按每批 40 个发给该接口，从当前播放位置往后优先。剧集详情里也可以点「生成语境释义」。结果按剧集和模型缓存在 `~/Library/Application Support/PodLyrics/user.sqlite`，不会重复请求。API Key 存在钥匙串。

关闭语境释义时应用完全离线。开启后，只有你播放（或手动生成）的那些字幕句子会发到你配置的那个服务，不含音频、不含资料库。

### 同步监控

右键悬浮窗打开后，字幕下会多一行等宽小字，例如：

```
音频锁定 · 文件 6:31.93 · 字幕 5:43.04 (-48.9s) · 3 段
```

| 字段 | 含义 |
| --- | --- |
| **音频锁定** / **字幕面板** / **搜索中 ±6s** / **MediaRemote 外推** | 当前同步源，精度大致从高到低。「搜索中 ±…s」表示正在放宽搜索范围 |
| **文件** | 正在播放的音频文件里的位置 |
| **字幕** | 映射到官方字幕时间轴的位置；括号里是偏移（这一点之前插入广告的累计时长） |
| **N 段** | 恒定偏移分段数（大约是广告段数 + 1） |
| **广告中** | 正在播广告；「下一句」会预告节目恢复后的第一句 |
| **正在校准时间轴…** | 刚切到新剧集，正在后台建广告映射 |

字幕看起来不对时，先看这一行：音频锁有没有握住、用的是哪个偏移。

## 故障排查

| 现象 | 原因 / 处理 |
| --- | --- |
| 「等待播放…」或「没有正在播放的内容」 | 先在 Apple Podcasts 里播放一集 |
| 「字幕尚未缓存：请在 Podcasts 里打开一次字幕面板」 | 给这一集打开一次字幕面板，让 Podcasts 下载 TTML |
| 「本集没有字幕（Apple 未提供 transcript）」 | Apple 没有为这一集提供 transcript |
| 已下载剧集的监控一直是「字幕面板」或「MediaRemote 外推」 | 系统音频录制未允许，或 process tap 失败。检查 隐私与安全性 → 屏幕与系统音频录制 |
| 监控长时间（>10 秒）显示「搜索中」 | Podcasts 没在出声（暂停、静音，或输出到 tap 跟不到的设备），或磁盘文件和正在播放的内容不一致 |
| 在线流播时字幕停住 | Podcasts 窗口被最小化，面板不再渲染。用别的窗口盖住即可，不要最小化 |
| 悬浮窗拖到屏幕外、抓不到 | 菜单栏 →「重置字幕位置」 |
| 认识的词被标了 / 不认识的没标 | 在剧集词表里标为已掌握或收入生词本；档位只是默认值 |
| 想看详细日志 | `PODLYRICS_DEBUG=1 .build/release/PodLyrics`，锁定、拒绝和时间轴分段会打到 stderr |
| 不播放也想看某一行 | 见下方 `PODLYRICS_PREVIEW` |

## 开发说明

`make-app.sh` 默认做 ad-hoc 签名；若登录钥匙串里有名为 `PodLyrics Dev` 的代码签名证书（或设置了 `PODLYRICS_SIGN_IDENTITY`）则用它。辅助功能权限绑在签名上，ad-hoc 每次重编都会被当成新 App，系统会再问一次。稳定签名可以让权限在重建后仍然有效（自签证书即可）。

其它环境变量：

| 变量 | 用途 |
| --- | --- |
| `PODLYRICS_DEBUG=1` | 对齐与时间轴的调试日志（stderr） |
| `PODLYRICS_PREVIEW` | 不播放，直接显示某份已缓存字幕的某一行。值为 transcriptID 和秒数，中间用一条竖线分隔 |
| `PODLYRICS_API_KEY` | 语境释义用的 Key，跳过钥匙串（方便调试） |
| `PODLYRICS_SIGN_IDENTITY` | `make-app.sh` 使用的签名身份，默认 `PodLyrics Dev` |

预览某一行（竖线分隔 transcriptID 和秒数）：

```bash
PODLYRICS_PREVIEW="<transcriptID>|<seconds>" .build/release/PodLyrics
```

词典 `Sources/PodLyrics/Resources/lexicon.sqlite` 由 `tools/build-lexicon.py` 从 ECDICT 1.0.28 生成。设计取舍见 `docs/adr/`。

## 原理（简要）

**字幕。** Apple Podcasts 把官方 transcript 缓存成带词级时间戳的 TTML：`~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache/Assets/TTML/`。MediaRemote 告诉我们当前在播哪一集、对应哪份字幕；已下载时还会给出缓存音频路径。

**音频对齐。** 对 Podcasts 挂 Core Audio 进程 tap，把最近几秒输出留在内存里，每隔约 2 秒与磁盘上的剧集文件做互相关（Accelerate FFT）。相关峰给出「某个墙钟时刻对应文件里的位置」，悬浮窗以此为锚、按倍速推进。1× 匹配波形；其它倍速下 Podcasts 做了保音高时间拉伸，改用起音包络。词高亮按 100 ms 刷新。作者实测相邻两次锁定的抖动：1× 约 0–1 ms，2× 约 2 ms。

**广告。** 下载文件常含动态广告，TTML 却按无广告的干净版本计时。Podcasts 在字幕旁附了干净音频的 ShazamKit 指纹。PodLyrics 读取这份指纹，每隔 5 秒探测文件，把偏移一致的探测点合并成分段，再用二分收紧边界。映射不到的空洞就是广告。建图在后台进行。

**跳转。** 比较 MediaRemote 上报位置和本地推算；差距大就丢掉旧锁，从上报位置附近重新搜，连续失败则放宽到全集（约 1 秒）。跳转后一般要 3–5 秒才能重新锁上，因为采集缓冲必须全部换成跳转后的音频。

**回退。** 音频锁未握住时（在线流播，或已下载但仍在搜索），用辅助功能读取官方字幕面板正在高亮的段落，映射回 TTML 再在段内外推——面板需打开（可以盖住，不能最小化）。两种信号都没有时，按 MediaRemote 的进度和倍速外推。

**MediaRemote。** macOS 15.4 起只对 Apple 签名进程返回数据，因此查询跑在 `/usr/bin/swift` 子进程里，结果以 JSON 行流回。

**词汇。** 词典保留有词频或考试标签的词条，并用 ECDICT 的 `exchange` 字段建变形表。档位取最低考试标签，无标签则按 COCA/BNC 词频兜底。剧集库元数据来自 Podcasts 的 `MTLibrary.sqlite` 只读快照；读失败时仍列出已缓存的 TTML，只是没有标题。

## 限制

- 只支持 Apple 提供 transcript 的剧集。
- 音频对齐和广告映射要求剧集已下载；在线流播用精度较低的面板同步，且面板必须打开。
- 内置词典是英→中，标注面向英语节目。
- 依赖 MediaRemote 私有框架、Podcasts 的缓存布局和辅助功能树，macOS 大版本升级后可能需要适配。

## 许可证

MIT

---

# English

[中文](#podlyrics)

Floating, always-on-top transcript overlay for Apple Podcasts on macOS — desktop lyrics, but for podcasts. Downloaded episodes lock to the audio you actually hear. Words above your level are glossed inline in Chinese, with an episode wordlist and a wordbook for preview before listening and review afterwards.

No account. Offline by default: transcripts, alignment and the dictionary all come from data Apple Podcasts already caches. The only optional network use is context glosses against an endpoint you configure.

## Features

- Translucent, draggable, always-on-top overlay over any app and fullscreen Spaces; menu-bar only, no Dock icon
- Previous / current / next line, with word-by-word highlighting
- Downloaded episodes: aligned to Podcasts’ own audio output, including dynamically inserted ads (current line goes blank during a break; “next” previews where the show resumes)
- Follows pause, seeking, skip, chapter jumps and Podcasts’ 0.8×–2× speed
- Streaming (not downloaded) falls back to the official transcript panel — less precise
- Optional one-line sync monitor (source + offset)
- **Vocabulary** (default level **四级** / CET-4): harder words render as `word(释义)`; per-episode wordlist and full text; a wordbook with real sentences from your library; optional OpenAI-compatible context glosses

## Requirements

- macOS 14.2 or later (Core Audio process taps; developed on recent macOS, including macOS 26)
- [Xcode Command Line Tools](https://developer.apple.com/download/all/?q=command%20line%20tools) (`xcode-select --install`) — needed to build, and at runtime for the Apple-signed `/usr/bin/swift` MediaRemote helper
- An episode with an Apple-provided transcript (common on English-language shows)

## Install

```bash
git clone https://github.com/byyuchun/PodLyrics.git
cd PodLyrics
./make-app.sh --install   # build PodLyrics.app and move it to /Applications
```

Build a local `.app` without installing: `./make-app.sh`.

Launch **PodLyrics** from Launchpad or Spotlight. It lives in the menu bar (captions-bubble icon) and has no Dock icon. Open at login: System Settings → General → Login Items → **+** → PodLyrics.

Or run the binary directly:

```bash
swift build -c release && .build/release/PodLyrics &
```

## First run

1. Open PodLyrics. A translucent panel appears at the bottom centre of the screen (it says「等待播放…」until something is playing). A bubble icon appears in the menu bar.
2. Grant the prompts macOS shows:
   - **Accessibility** — requested at launch. Used whenever the audio lock is not held (streaming, or a download still searching) to read the paragraph the official transcript panel is highlighting. System Settings → Privacy & Security → Accessibility → **+** → `/Applications/PodLyrics.app`. For the bare binary, press <kbd>⌘</kbd><kbd>⇧</kbd><kbd>G</kbd> and enter the full path to `.build/release/PodLyrics` (`.build` is hidden).
   - **Screen & System Audio Recording** — asked the first time audio alignment starts on a downloaded episode. Podcasts’ output only; never the microphone or other apps. System Settings → Privacy & Security → Screen & System Audio Recording.
3. In Apple Podcasts:
   1. **Download** the episode (the download arrow). Downloaded episodes use audio sync; streaming uses the panel fallback.
   2. **Play** it and tap the **transcript (speech bubble)** button once so Podcasts caches the TTML. After an audio lock you can close the panel; keep it open if you are on the panel fallback (see Limitations).
4. The overlay starts following once playback is detected. Right-click the overlay → **我的水平** and pick your level (default **四级**). Words at or below that level are treated as known.

The first time the app reads Podcasts’ cache folder, macOS may also ask for folder access.

## Daily use

| Action | How |
| --- | --- |
| Move the overlay | Drag it |
| Hide / show | Menu-bar icon →「显示/隐藏字幕」, or right-click the overlay →「隐藏（菜单栏图标可再显示）」 |
| Lost off-screen | Menu-bar icon →「重置字幕位置」(bottom centre again) |
| Bring it back | Open PodLyrics again from Launchpad / Spotlight (if already running, this re-shows and clamps the overlay) |
| Change my level | Right-click the overlay →「我的水平」, or main window → Settings / episode toolbar |
| Open the main window | Menu-bar icon →「打开 PodLyrics…」, or right-click the overlay |
| Sync monitor | Right-click the overlay →「显示同步监控」 |
| Quit | Menu-bar icon →「退出」, or right-click →「退出 PodLyrics」 |
| Stop from a terminal | `pkill -x PodLyrics` |

The menu-bar menu shows <kbd>⌘O</kbd> (main window), <kbd>⌘T</kbd> (toggle overlay), <kbd>⌘R</kbd> (reset position), <kbd>⌘Q</kbd> (quit). These are menu key equivalents, not global hotkeys.

### Main window

Menu-bar icon →「打开 PodLyrics…」:

- **剧集库** — every episode whose transcript is cached on this Mac (open the transcript panel once in Podcasts to cache one). Search by show or title. Select an episode for its **词表** (annotated words grouped by level, with meaning, count and an example) or the annotated **全文**. Same page for pre-listen preview and post-listen review; bookmark into the Wordbook or mark Known.
- **生词本** — your saved words and every sentence they appear in across cached episodes. The toolbar switches to **已掌握**.
- **设置** — your level and the optional gloss provider.

An empty library shows「没有已缓存字幕的剧集」— open a transcript panel in Podcasts first.

### Vocabulary

Ships a trimmed [ECDICT](https://github.com/skywind3000/ECDICT) 1.0.28 (~43k headwords, ~7 MB, offline). Each transcript token is mapped to a headword (`negotiated → negotiate`) and an exam level: 初中 / 高中 / 四级 / 六级 / 考研 / 托福雅思 / GRE.

**我的水平** offers 初中 through 托福雅思 (not GRE — “I know every GRE word” would leave nothing to mark). GRE-level words are always treated as above your level. Default is 四级. Two personal lists override the level:

- **Wordbook (生词本)** — always annotated
- **Known (已掌握)** — never annotated
- Tokens not in the lexicon (names, brands, …) are never annotated

**Context glosses (optional, off).** ECDICT is a general dictionary; a podcast often uses one sense (*pitch*, *chunk*). In Settings, enable「启用语境释义」, set any OpenAI-compatible Base URL (through `/v1`), model and API key, then「保存」.「测试连接」checks the endpoint. Annotated words of the current episode — plus the sentence each first appears in — are sent in batches of 40, preferring words from the current playback position onward. Episode detail also has「生成语境释义」. Results are cached per episode and model in `~/Library/Application Support/PodLyrics/user.sqlite`. The API key lives in the Keychain.

With the provider off, the app is fully offline. With it on, only transcript sentences you play (or generate glosses for) go to the endpoint you configured — not audio, not your library.

### Sync monitor

Right-click the overlay to enable it. A monospaced line appears under the subtitles, for example:

```
音频锁定 · 文件 6:31.93 · 字幕 5:43.04 (-48.9s) · 3 段
```

| Field | Meaning |
| --- | --- |
| **音频锁定** / **字幕面板** / **搜索中 ±6s** / **MediaRemote 外推** | Sync source, roughly most to least precise.「搜索中 ±…s」means the search window is widening |
| **文件** | Position inside the audio file Podcasts is playing |
| **字幕** | Matching position on the transcript timeline; the offset in parentheses is cumulative inserted-ad time |
| **N 段** | Constant-offset segments (about ad-breaks + 1) |
| **广告中** | An ad is playing; the “next line” slot previews where the programme resumes |
| **正在校准时间轴…** | First seconds of a new episode, building the ad map |

If the subtitles look wrong, this line tells you whether the audio lock is held and which offset is applied.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| 「等待播放…」or「没有正在播放的内容」 | Play an episode in Apple Podcasts |
| 「字幕尚未缓存：请在 Podcasts 里打开一次字幕面板」 | Open the transcript panel once so Podcasts downloads the TTML |
| 「本集没有字幕（Apple 未提供 transcript）」 | Apple has not published a transcript |
| Monitor stays on 字幕面板 or MediaRemote 外推 for a downloaded episode | System Audio Recording denied, or the tap failed. Check Privacy & Security → Screen & System Audio Recording |
| Monitor shows 搜索中 for more than ~10 s | Podcasts is not outputting audio (paused, muted, or a device the tap cannot follow), or the file on disk is not what is playing |
| Streaming subtitles freeze | The Podcasts window is minimized; the panel stops rendering. Cover it instead |
| Overlay dragged off-screen | Menu bar →「重置字幕位置」 |
| A word you know is marked / one you don’t isn’t | Mark it Known or bookmark it in the episode wordlist; the level is only a default |
| Verbose logs | `PODLYRICS_DEBUG=1 .build/release/PodLyrics` — locks, rejections and timeline segments go to stderr |
| Check a line without playing | See `PODLYRICS_PREVIEW` below |

## Development

`make-app.sh` ad-hoc signs the bundle unless a `PodLyrics Dev` codesigning certificate is in the login keychain (or `PODLYRICS_SIGN_IDENTITY` is set). Accessibility TCC is tied to that signature, so an ad-hoc rebuild looks like a new app. A stable identity keeps the permission across rebuilds (self-signed is fine).

| Variable | Purpose |
| --- | --- |
| `PODLYRICS_DEBUG=1` | Alignment / timeline debug logs on stderr |
| `PODLYRICS_PREVIEW` | Show one line of a cached transcript without playback. Value is transcriptID and seconds, separated by a vertical bar |
| `PODLYRICS_API_KEY` | Gloss API key, skipping the Keychain |
| `PODLYRICS_SIGN_IDENTITY` | Identity used by `make-app.sh` (default `PodLyrics Dev`) |

Preview one line (vertical bar between transcriptID and seconds):

```bash
PODLYRICS_PREVIEW="<transcriptID>|<seconds>" .build/release/PodLyrics
```

`Sources/PodLyrics/Resources/lexicon.sqlite` is produced by `tools/build-lexicon.py` from ECDICT 1.0.28. Design notes: `docs/adr/`.

## How it works (short)

**Transcripts.** Apple Podcasts caches official transcripts as word-timed TTML under `~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache/Assets/TTML/`. MediaRemote identifies the playing episode and its transcript; for downloads it also yields the cached audio path.

**Audio alignment.** A Core Audio process tap on Podcasts keeps the last few seconds of output. About every two seconds that buffer is cross-correlated with the episode file (FFT via Accelerate). The peak is a file position at a known wall-clock instant; the overlay advances from that anchor at the playback rate. At 1× the raw waveform matches; at other speeds Podcasts time-stretches, so an onset-envelope correlation is used instead. Word highlighting refreshes every 100 ms. Measured lock-to-lock jitter: about 0–1 ms at 1×, about 2 ms at 2×.

**Ads.** Downloaded files usually contain inserted ads, while TTML is timed against the clean programme. Podcasts ships a ShazamKit signature of the clean audio next to each transcript. PodLyrics probes the file every 5 s against that signature, merges agreeing offsets into segments and refines edges by bisection. Gaps are ads. The map is built in the background.

**Seeks.** A jump is MediaRemote’s position disagreeing with ours; the stale lock is dropped and search widens from the reported position up to the whole file (~1 s). Re-lock typically takes 3–5 s after the last jump, because the capture buffer must be entirely post-seek audio.

**Fallbacks.** When the audio lock is not held (streaming, or a download still searching), Accessibility reads the paragraph the official panel is highlighting, maps it back to TTML and extrapolates inside that paragraph — the panel must stay open (covered is fine, minimized is not). With neither signal, MediaRemote’s position and rate are extrapolated.

**MediaRemote.** Since macOS 15.4 the private API only answers Apple-signed processes, so the query runs inside `/usr/bin/swift` and streams JSON lines back.

**Vocabulary.** The lexicon keeps headwords that have a frequency rank or an exam tag, plus an inflection table from ECDICT’s `exchange` field. Level is the lowest exam tag, else a COCA/BNC-rank fallback. Episode metadata is a read-only snapshot of Podcasts’ `MTLibrary.sqlite`; if that fails, the library still lists cached TTML files, just without titles.

## Limitations

- Only episodes for which Apple publishes a transcript.
- Audio alignment and ad mapping need a download; streaming uses the less precise panel sync, and the panel must stay open.
- The bundled dictionary is English→Chinese; annotations target English shows.
- Relies on the private MediaRemote framework, Podcasts’ cache layout and its accessibility tree. Major macOS updates may break this.

## License

MIT
