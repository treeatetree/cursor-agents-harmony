#!/usr/bin/env python3
"""Copy Cursor desktop accessibility-signal MP3s into rawfile/ unchanged.

Do not trim, convert, or remix — the phone should play the same files
as Cursor.app (VS Code accessibilitySignal, MIT).
"""
import os
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'entry', 'src', 'main', 'resources', 'rawfile'))
CURSOR_MEDIA = (
    '/Applications/Cursor.app/Contents/Resources/app/out/'
    'vs/platform/accessibilitySignal/browser/media'
)

# App kind → Cursor desktop file (same mapping the desktop uses)
MAP = {
    'snd_commit.mp3': 'requestSent.mp3',
    'snd_ok.mp3': 'taskCompleted.mp3',
    'snd_fail.mp3': 'taskFailed.mp3',
    'snd_warn.mp3': 'warning.mp3',
}


def main() -> None:
    if not os.path.isdir(CURSOR_MEDIA):
        print(f'Cursor media not found: {CURSOR_MEDIA}', file=sys.stderr)
        sys.exit(1)
    os.makedirs(ROOT, exist_ok=True)
    for dest_name, src_name in MAP.items():
        src = os.path.join(CURSOR_MEDIA, src_name)
        if not os.path.isfile(src):
            print(f'missing {src}', file=sys.stderr)
            sys.exit(1)
        dest = os.path.join(ROOT, dest_name)
        shutil.copy2(src, dest)
        print(f'{src_name} → {dest_name} ({os.path.getsize(dest)} bytes)')
    for stale in ('snd_click.wav', 'snd_commit.wav', 'snd_toggle.wav',
                  'snd_ok.wav', 'snd_fail.wav', 'snd_warn.wav'):
        path = os.path.join(ROOT, stale)
        if os.path.isfile(path):
            os.remove(path)
            print(f'removed {stale}')


if __name__ == '__main__':
    main()
