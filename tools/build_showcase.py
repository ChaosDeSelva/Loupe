#!/usr/bin/env python3
"""Build the Pages game and standalone downloads from the canonical Afterimage example."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'mcp'))
from server import Server

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--builder', default='love.js')
    args = parser.parse_args()
    game = ROOT / 'examples/afterimage'
    archive = Server(game, None, 'love').call('game_build', {})['artifact']
    subprocess.run([sys.executable, str(game/'tools/build_web.py'), archive,
                    str(ROOT/'site/play'), '--builder', args.builder], check=True)
    downloads = ROOT/'site/downloads'
    downloads.mkdir(exist_ok=True)
    shutil.copy2(archive, downloads/'Afterimage.love')
    with zipfile.ZipFile(downloads/'afterimage-source.zip', 'w', zipfile.ZIP_DEFLATED) as output:
        for base, prefix in [(game, ''), (ROOT/'loupe', 'loupe/')]:
            for source in sorted(base.rglob('*')):
                rel = source.relative_to(base)
                if not source.is_file() or source.is_symlink(): continue
                if any(x.startswith('.') or x in {'dist','__pycache__'} for x in rel.parts): continue
                if source.name == 'loupe_overrides.lua' or source.suffix == '.pyc': continue
                output.write(source,prefix+str(rel))
    print('Built site/play and site/downloads from examples/afterimage.')

if __name__ == '__main__': main()
