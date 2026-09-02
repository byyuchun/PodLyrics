# PodLyrics

A macOS overlay that shows the official Apple Podcasts transcript in sync with whatever is playing.

## Language

**Now Playing**:
The episode Apple Podcasts is currently playing, identified by MediaRemote metadata.
_Avoid_: track, song, current item

**Transcript**:
The official timed text for an episode, cached locally as TTML with word-level timestamps.
_Avoid_: captions file, lyrics file, subtitle file

**Panel Highlight**:
The paragraph the official Podcasts transcript panel is currently marking as active.
_Avoid_: AX highlight, selected line, current subtitle

**Playback Position**:
The current moment on the episode timeline used to decide which words have been spoken.
_Avoid_: elapsed, playhead, clock

**Playback Anchor**:
A trusted Playback Position paired with a wall-clock instant, used to extrapolate until the next correction.
_Avoid_: timestamp, sync point

**Local Episode Asset**:
A complete audio file for an episode, stored on disk.
_Avoid_: mp3, local path, stream

**Stream Cache**:
Audio Podcasts may keep while streaming, with hashed names and no stable link to Now Playing.
_Avoid_: local mp3, downloaded file

**Waveform Offset**:
The time shift that aligns a live audio snippet with the episode audio.
_Avoid_: delay, latency, drift
