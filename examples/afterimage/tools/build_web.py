#!/usr/bin/env python3
"""Package a built .love for love.js 11.4.1 compatibility mode, without changing native source."""
import argparse
import hashlib
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('game',type=Path)
parser.add_argument('output',type=Path)
parser.add_argument('--builder',default='love.js')
args=parser.parse_args()
with tempfile.TemporaryDirectory() as directory:
    game=Path(directory)/'web.love'
    with zipfile.ZipFile(args.game) as source, zipfile.ZipFile(game,'w',zipfile.ZIP_DEFLATED) as dest:
        for info in source.infolist():
            data=source.read(info)
            if info.filename=='conf.lua':
                data=data.replace(b't.version = "11.5"',b't.version = "11.4"')
            if info.filename=='main.lua':
                data=data.replace(b'local browserBuild = false', b'local browserBuild = true')
            dest.writestr(info,data)
    subprocess.run([args.builder,'-c','-t','AFTERIMAGE / The Glass Reach','-m','268435456',str(game),str(args.output)],check=True)
template=Path(__file__).parent/'web'
shutil.copy2(template/'index.html',args.output/'index.html')
shutil.copy2(template/'love.css',args.output/'theme/love.css')
for notice in template.glob('*.txt'): shutil.copy2(notice,args.output/notice.name)
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
