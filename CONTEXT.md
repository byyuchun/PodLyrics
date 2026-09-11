# PodLyrics

macOS 菜单栏悬浮字幕：读取 Apple Podcasts 已缓存的官方字幕并与播放同步；在此之上做英语听力学习辅助（词汇标注、生词本）。

## Language

### 字幕

**Transcript（字幕稿）**:
一集播客的完整官方字幕，来自 Apple Podcasts 缓存的 TTML，含句子级 Line 和词级时间戳。
_Avoid_: 歌词、subtitle 文件、转写结果

**Line（字幕行）**:
Transcript 中的一个句子单位，是悬浮窗一次显示的基本单元。
_Avoid_: 句子、段落

### 剧集

**Episode（剧集）**:
Apple Podcasts 资料库里的一集，元数据（标题、节目、时长、播放状态）来自 Podcasts 自己的本地数据库，应用只读不写。
_Avoid_: 音频文件、节目（那是 Podcast/Show）

**Library（剧集库）**:
本机上 Transcript 已被 Podcasts 缓存的 Episode 集合，是预习和复盘的入口。Library 不做任何下载。
_Avoid_: 已下载列表、播放列表

### 词汇

**Lexicon（内置词典）**:
随应用打包的离线词表（裁剪自 ECDICT），提供词形还原、词频、考试标签和通用中文释义。不联网、不依赖用户配置。
_Avoid_: 词库、字典 API、爬取数据

**Headword（词条）**:
一个词的原形（negotiate），是 Lexicon、Wordbook、Known 的统一键。字幕中的任何变形（negotiating、negotiated）都归到同一个 Headword；不在 Lexicon 中的词（人名、品牌等）没有 Headword，永不标注。
_Avoid_: 单词、原形、lemma

**Level（词汇档位）**:
用考试阶段表达的词汇难度刻度：高中、四级、六级、考研、托福雅思、GRE。每个词由 Lexicon 的考试标签归档，无标签的词按词频归入最接近的档。用户也用同一刻度声明自己的水平。
_Avoid_: 难度分数、CEFR、词频排名（内部实现，不对用户暴露）

**Proficiency（我的水平）**:
用户用 Level 刻度声明的自身词汇水平。该档及以下的词视为已掌握，字幕中不标注；只标注高于此档的词。
_Avoid_: 难度设置、目标档位、备考目标

### 个人词表

**Wordbook（生词本）**:
用户主动收藏的、想要学习的词，每个词带它在本机哪些 Episode 的哪些 Line 出现过。其中的词无论 Level 多低，字幕中一律标注。不含复习算法，学习闭环靠"下次听到时被标注"完成。
_Avoid_: 词库、收藏、单词表、复习卡

**Known（已掌握）**:
用户明确标记为认识的词。其中的词无论 Level 多高，字幕中一律不标注。
_Avoid_: 忽略、屏蔽、白名单

**Annotation（标注）**:
字幕行中某个词被判定为需要提示，并在悬浮窗中展示释义的行为。判定顺序：Known 不标，Wordbook 必标，其余按 Level 是否高于 Proficiency。
_Avoid_: 高亮（已被"词级播放高亮"占用）、翻译

**Episode Wordlist（剧集词表）**:
从一集 Transcript 全文算出的、当前会被 Annotation 的词的集合，按 Level 分组，每个词带释义、出现次数和例句。听前打开是预习，听后打开是复盘，两者是同一张表。用户在此批量加入 Wordbook 或标为 Known。
_Avoid_: 遇词记录、本集单词、历史

### 释义

**Gloss（语境释义）**:
由用户自备的 LLM 针对某一集中某个 Headword 生成的、结合其首次出现句子的简短中文解释。每集每词条一条，是 Lexicon 通用释义的可选增强，而非替代；未开启或未到达时字幕展示 Lexicon 释义。
_Avoid_: 翻译、注释、AI 释义

**Provider（模型服务）**:
用户自行提供的 OpenAI 兼容接口配置（Base URL、API Key、模型名），是生成 Gloss 的唯一网络出口。默认关闭。
_Avoid_: 后端、云服务、AI 设置
