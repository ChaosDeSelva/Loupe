#!/usr/bin/env python3
"""Package a built .love for love.js 11.4.1 compatibility mode, without changing native source.

Analytics: the .love inside gets a keyless analytics.config.lua naming the
distribution (the game then shows its analytics disclosure); any config already in
the archive is dropped. The public key, when RAVENSIGHT_PUBLIC_KEY is set, goes
only into the page. Without it the page installs the bridge as a sink and
sends nothing. The bridge and the ravensight JavaScript SDK (pinned below) are
copied beside index.html.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analytics_config  # noqa: E402

# The ravensight npm package the page loads. 0.4.x is what ravensight-love
# 0.3.0's bridge needs; bump together with the bridge.
RAVENSIGHT_JS_VERSION='0.4.2'

parser=argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('game',type=Path)
parser.add_argument('output',type=Path)
parser.add_argument('--builder',default='love.js')
parser.add_argument('--distribution',required=True,choices=('web-pages','web-itch'))
parser.add_argument('--js-sdk',type=Path,help='the installed ravensight npm package directory '
                    '(default: beside the love.js builder in node_modules)')
args=parser.parse_args()
key=analytics_config.public_key()
api_url=analytics_config.api_url()
sdk_dir=args.js_sdk
if sdk_dir is None and Path(args.builder).parent.name=='.bin':
    sdk_dir=Path(args.builder).parent.parent/'ravensight'
sdk_source=None
if sdk_dir is not None and (sdk_dir/'package.json').is_file():
    found=json.loads((sdk_dir/'package.json').read_text()).get('version')
    if found!=RAVENSIGHT_JS_VERSION:
        raise SystemExit(f'ravensight JS SDK {found} found, {RAVENSIGHT_JS_VERSION} pinned: install ravensight@{RAVENSIGHT_JS_VERSION}')
    sdk_source=sdk_dir/'src/index.js'
if key and sdk_source is None:
    raise SystemExit('RAVENSIGHT_PUBLIC_KEY is set but the ravensight JS SDK was not found; pass --js-sdk')
game_version='1.0.0'
with tempfile.TemporaryDirectory() as directory:
    game=Path(directory)/'web.love'
    with zipfile.ZipFile(args.game) as source, zipfile.ZipFile(game,'w',zipfile.ZIP_DEFLATED) as dest:
        for info in source.infolist():
            data=source.read(info)
            if info.filename=='conf.lua':
                data=data.replace(b't.version = "11.5"',b't.version = "11.4"')
            if info.filename=='main.lua':
                data=data.replace(b'local browserBuild = false', b'local browserBuild = true')
            if info.filename==analytics_config.NAME:
                continue
            if info.filename=='src/version.lua':
                match=re.search(rb'version = "([0-9A-Za-z.+-]+)"',data)
                if match: game_version=match.group(1).decode()
            dest.writestr(info,data)
        dest.writestr(analytics_config.NAME,analytics_config.render(args.distribution,web=True))
    subprocess.run([args.builder,'-c','-t','AFTERIMAGE / The Glass Reach','-m','268435456',str(game),str(args.output)],check=True)
template=Path(__file__).parent/'web'
shutil.copy2(template/'index.html',args.output/'index.html')
shutil.copy2(template/'love.css',args.output/'theme/love.css')
for notice in template.glob('*.txt'): shutil.copy2(notice,args.output/notice.name)
shutil.copy2(template/'ravensight-love-bridge.js',args.output/'ravensight-love-bridge.js')
if sdk_source is not None:
    (args.output/'ravensight').mkdir(exist_ok=True)
    shutil.copy2(sdk_source,args.output/'ravensight/index.js')
    shutil.copy2(sdk_source.parent.parent/'LICENSE',args.output/'ravensight/LICENSE')
print(args.output.resolve())

logo=Path(__file__).resolve().parents[1]/'assets/afterimage-logo.png'
if logo.exists(): shutil.copy2(logo,args.output/'afterimage-logo.png')

# Expose the virtual FS for a canvas-size mailbox; no host filesystem access.
runtime=args.output/'love.js'
code=runtime.read_text()
anchor='Module["FS_createDataFile"]=FS.createDataFile;'
assert code.count(anchor)==2, 'love.js runtime changed: review the FS export patch'
code=code.replace(anchor, anchor+'Module["FS"]=FS;')
# HTML owns fullscreen. SDL mode updates must not exit it while resizing.
anchor='function _emscripten_exit_fullscreen(){'
assert code.count(anchor)==1, 'love.js fullscreen export changed'
code=code.replace(anchor, anchor+'if(Module["htmlFullscreen"])return 0;')
# Match LÖVE logical coordinates: backing pixels divided by the display DPI scale.
anchor='HEAP32[idx+11]=e.clientX-rect.left;HEAP32[idx+12]=e.clientY-rect.top'
assert code.count(anchor)==1, 'love.js mouse event layout changed'
replacement='var sx=1,sy=1;if(target===Module["canvas"]){try{var dims=FS.readFile("/tmp/afterimage-input.txt",{encoding:"utf8"}).split(" ");sx=Number(dims[0])/rect.width;sy=Number(dims[1])/rect.height;}catch(err){}}HEAP32[idx+11]=(e.clientX-rect.left)*sx;HEAP32[idx+12]=(e.clientY-rect.top)*sy;HEAP32[idx+9]=(e["movementX"]||0)*sx;HEAP32[idx+10]=(e["movementY"]||0)*sy'
code=code.replace(anchor,replacement)
runtime.write_text(code)

# Bind both the IndexedDB package and browser script caches to this exact build.
package_hash=hashlib.sha256((args.output/'game.data').read_bytes()).hexdigest()
loader=args.output/'game.js'
loader_code=loader.read_text()
loader_code,count=re.subn(r'"package_uuid"\s*:\s*"[^"]+"', '"package_uuid":"'+package_hash+'"', loader_code)
assert count==1, 'love.js package metadata changed'
loader_code=loader_code.replace("var REMOTE_PACKAGE_BASE = 'game.data';", "var REMOTE_PACKAGE_BASE = 'game.data?v="+package_hash[:16]+"';")
loader.write_text(loader_code)
page=args.output/'index.html'
html=page.read_text()
html=html.replace('{{RAVENSIGHT_PUBLIC_KEY}}',key).replace('{{RAVENSIGHT_API_URL}}',api_url)
html=html.replace('{{AFTERIMAGE_VERSION}}',game_version)
assert '{{' not in html, 'unreplaced template token in index.html'
for name in ['ravensight-love-bridge.js','ravensight/index.js']:
    if (args.output/name).exists():
        digest=hashlib.sha256((args.output/name).read_bytes()).hexdigest()[:16]
        html=html.replace("import('./"+name+"')","import('./"+name+"?v="+digest+"')")
print('Analytics:', 'public key in the page ('+args.distribution+')' if key else 'keyless page, bridge is a sink')
for name in ['game.js','love.js','theme/love.css']:
    digest=hashlib.sha256((args.output/name).read_bytes()).hexdigest()[:16]
    html=html.replace('src="'+name+'"', 'src="'+name+'?v='+digest+'"')
    html=html.replace('href="'+name+'"', 'href="'+name+'?v='+digest+'"')
page.write_text(html)

# Remove upstream compiler home directories from diagnostic strings without
# changing byte lengths or offsets in the compiled module.
wasm=args.output/'love.wasm'
blob=wasm.read_bytes()
pattern=rb'/Users/[^/\\\x00\s]+/'
blob,count=re.subn(pattern, lambda match: b'/build/'+b'_'*(len(match[0])-8)+b'/', blob)
wasm.write_bytes(blob)
print('Sanitized upstream build-path prefixes:', count)
# Version the binary fetch too, so a cached runtime cannot retain an old module.
wasm_hash=hashlib.sha256(blob).hexdigest()[:16]
html=page.read_text().replace('htmlFullscreen:true,', 'htmlFullscreen:true, locateFile(path){return path+(path.includes("?")?"&":"?")+"v='+wasm_hash+'";},')
page.write_text(html)
