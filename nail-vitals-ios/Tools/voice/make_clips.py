#!/usr/bin/env python3
"""Turn one recording of the voice cues into the app's clips.

Read the 11 lines below in order, with a pause of about 2 seconds between
them, and record it in one go (Voice Memos is fine). Then:

    python3 Tools/voice/make_clips.py recording.m4a

It finds the pauses, cuts out each line, trims the silence, evens out the
loudness, and writes voice-<cue>.m4a into the app's Voice folder, where
VoiceCoach plays them. Needs ffmpeg. Use only your own voice: recordings
of Apple's built-in voices can't ship in the app.
"""
import os, re, subprocess, sys

CUES = [  # (file name, line to read) -- same order and wording as VoiceCoach.Cue
    ("no-finger", "Hold your index finger up, side on, inside the frame."),
    ("move-closer", "Move closer."),
    ("move-back", "Move back."),
    ("move-left", "Move left."),
    ("move-right", "Move right."),
    ("move-up", "Move up."),
    ("move-down", "Move down."),
    ("straighten", "Straighten your finger."),
    ("turn-sideways", "Turn your finger fully sideways."),
    ("hold-still", "Hold still."),
    ("got-it", "Got it."),
]
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(HERE, "..", "..", "NailVitals", "NailVitals", "NailVitals", "Voice")
TARGET_MEAN_DB = -20.0   # average loudness of each clip
MAX_PEAK_DB = -1.5       # never louder than this


def run(args):
    return subprocess.run(args, capture_output=True, text=True)


def speech_segments(path, noise_db, min_pause):
    """(start, end) of each stretch of speech, from ffmpeg's silence detector."""
    log = run(["ffmpeg", "-hide_banner", "-i", path, "-af",
               f"silencedetect=noise={noise_db}dB:d={min_pause}", "-f", "null", "-"]).stderr
    duration = float(re.search(r"Duration: (\d+):(\d+):([\d.]+)", log).groups()[2]) + \
        60 * float(re.search(r"Duration: (\d+):(\d+)", log).groups()[1]) + \
        3600 * float(re.search(r"Duration: (\d+)", log).groups()[0])
    starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", log)]
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", log)]
    segments, cursor = [], 0.0
    for s, e in zip(starts, ends + [duration] * (len(starts) - len(ends))):
        if s - cursor > 0.15:
            segments.append((cursor, s))
        cursor = e
    if duration - cursor > 0.15:
        segments.append((cursor, duration))
    return segments


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        print("Lines to read:")
        for i, (_, line) in enumerate(CUES, 1):
            print(f"  {i:2}. {line}")
        sys.exit(1)
    src, out = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT)
    os.makedirs(out, exist_ok=True)

    # Try a few silence thresholds until the recording splits into exactly 11 lines.
    for noise_db, pause in [(-35, 0.6), (-40, 0.6), (-30, 0.6), (-35, 0.9), (-45, 0.6), (-28, 0.5)]:
        segments = speech_segments(src, noise_db, pause)
        if len(segments) == len(CUES):
            break
    else:
        print(f"Found {len(segments)} lines, expected {len(CUES)}. Re-record with a clear ~2 s pause "
              "between lines, and no extra words or noises.")
        sys.exit(2)

    for (name, line), (start, end) in zip(CUES, segments):
        start, end = max(0.0, start - 0.08), end + 0.15  # keep the natural edges
        stats = run(["ffmpeg", "-hide_banner", "-ss", f"{start}", "-to", f"{end}", "-i", src,
                     "-af", "volumedetect", "-f", "null", "-"]).stderr
        mean = float(re.search(r"mean_volume: (-?[\d.]+)", stats).group(1))
        peak = float(re.search(r"max_volume: (-?[\d.]+)", stats).group(1))
        gain = min(TARGET_MEAN_DB - mean, MAX_PEAK_DB - peak)
        length = end - start
        dest = os.path.join(out, f"voice-{name}.m4a")
        result = run(["ffmpeg", "-hide_banner", "-y", "-ss", f"{start}", "-to", f"{end}", "-i", src,
                      "-af", f"volume={gain:.2f}dB,afade=t=in:d=0.03,afade=t=out:st={max(0, length - 0.1):.3f}:d=0.1",
                      "-ac", "1", "-ar", "44100", "-c:a", "aac", "-b:a", "64k", dest])
        if result.returncode != 0:
            print(result.stderr)
            sys.exit(3)
        print(f"{name:14} {length:4.1f} s  gain {gain:+5.1f} dB  \"{line}\"")
    print(f"Wrote {len(CUES)} clips to {os.path.normpath(out)}")


if __name__ == "__main__":
    main()
