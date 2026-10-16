#!/usr/bin/env python3
"""Build afterimage-itch-html5.zip, the itch.io HTML5 upload, from examples/afterimage.

With RAVENSIGHT_PUBLIC_KEY set, the zip's index.html carries that public key
by design (distribution "web-itch"); the game inside stays keyless and asks
the player before anything is sent. Without it the page is keyless. The zip
is written to dist/ and is never committed.

    RAVENSIGHT_PUBLIC_KEY=gt_pub_... python3 tools/build_itch.py \\
        --builder .webtools/node_modules/.bin/love.js
"""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'mcp'))
from server import Server  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--builder', default='love.js')
    parser.add_argument('--js-sdk', help='the installed ravensight npm package directory')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/afterimage-itch-html5.zip')
    args = parser.parse_args()
    game = ROOT / 'examples/afterimage'
    archive = Server(game, None, 'love').call('game_build', {})['artifact']
    with tempfile.TemporaryDirectory() as directory:
        site = Path(directory) / 'itch'
        command = [sys.executable, str(game / 'tools/build_web.py'), archive, str(site),
                   '--builder', args.builder, '--distribution', 'web-itch']
        if args.js_sdk:
            command += ['--js-sdk', args.js_sdk]
        subprocess.run(command, check=True)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(args.output, 'w', zipfile.ZIP_DEFLATED) as output:
            for path in sorted(site.rglob('*')):
                if path.is_file() and not path.is_symlink():
                    output.write(path, str(path.relative_to(site)))
    print('Built', args.output.relative_to(ROOT) if args.output.is_relative_to(ROOT) else args.output)


if __name__ == '__main__':
    main()
