# 直接只读 Podcasts 的私有 SQLite 库，不自建剧集元数据

剧集库需要标题、节目名、时长、播放状态。这些信息只存在于 Apple Podcasts 的 Core Data 库 `~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Documents/MTLibrary.sqlite`。我们选择把 `.sqlite`、`-wal`、`-shm` 三个文件整体拷到临时目录后只读打开，联表查询 `ZMTEPISODE` 与 `ZMTPODCAST`，用 `ZTRANSCRIPTIDENTIFIER` 与 TTML 缓存目录对上。

原因：应用的原则是不联网、不自己下载任何东西，那么剧集元数据只能来自本机；MediaRemote 只报告"正在播放"的一集，无法列出历史。直接打开 Podcasts 正在写的库有锁冲突和 WAL 读不到最新数据的风险，拷贝三件套能拿到一致快照且绝不会写坏原库。代价是表结构属于 Apple 私有实现，macOS 大版本升级可能改列名，因此 `PodcastLibrary` 在读库失败时退化为只枚举 TTML 目录：剧集仍然列得出来，只是没有标题。

剧集库只列"字幕已缓存"的集，而不是"已下载音频"的集——预习和复盘依赖字幕文本，音频只是加分项（可音频同步）。
