#!/usr/bin/env python3
"""Build the Pages game and standalone downloads from the canonical Afterimage example.

Analytics: with RAVENSIGHT_PUBLIC_KEY set (the Pages workflow passes the
repository secret), the web page and site/downloads/Afterimage.love carry the
public key. The source zip never does, nor any analytics.config.lua. Without the
variable, as in any fork, every artifact is keyless and sends nothing.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'mcp'))
sys.path.insert(0, str(ROOT / 'examples/afterimage/tools'))
from server import Server  # noqa: E402
import analytics_config  # noqa: E402

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--builder', default='love.js')
    parser.add_argument('--js-sdk', help='the installed ravensight npm package directory')
    args = parser.parse_args()
    key = analytics_config.public_key()
    game = ROOT / 'examples/afterimage'
    archive = Server(game, None, 'love').call('game_build', {})['artifact']
    web = [sys.executable, str(game/'tools/build_web.py'), archive, str(ROOT/'site/play'),
           '--builder', args.builder, '--distribution', 'web-pages']
    if args.js_sdk: web += ['--js-sdk', args.js_sdk]
    subprocess.run(web, check=True)
    downloads = ROOT/'site/downloads'
    downloads.mkdir(exist_ok=True)
    # game_build never includes a config; the official download gets one only here.
    with zipfile.ZipFile(archive) as source, zipfile.ZipFile(downloads/'Afterimage.love', 'w', zipfile.ZIP_DEFLATED) as dest:
        for info in source.infolist():
            if info.filename != analytics_config.NAME: dest.writestr(info, source.read(info))
        if key:
            dest.writestr(analytics_config.NAME, analytics_config.render('native-release', key, analytics_config.api_url()))
    print('Afterimage.love:', 'public key injected (native-release)' if key else 'keyless')
    with zipfile.ZipFile(downloads/'afterimage-source.zip', 'w', zipfile.ZIP_DEFLATED) as output:
        for base, prefix in [(game, ''), (ROOT/'loupe', 'loupe/')]:
            for source in sorted(base.rglob('*')):
                rel = source.relative_to(base)
                if not source.is_file() or source.is_symlink(): continue
                if any(x.startswith('.') or x in {'dist','__pycache__'} for x in rel.parts): continue
                if source.name in {'loupe_overrides.lua', analytics_config.NAME} or source.suffix == '.pyc': continue
                output.write(source,prefix+str(rel))
    print('Built site/play and site/downloads from examples/afterimage.')

if __name__ == '__main__': main()
