#!/usr/bin/env python3
"""Loupe MCP: stdio JSON-RPC + opt-in local LÖVE mailbox. Python stdlib only."""
import argparse
import json
import math
import base64
import shutil
import hashlib
import struct
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid
import zipfile

PROTOCOLS = ('2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05')
MAX_MESSAGE = 1024 * 1024
ASSETS = {'.png', '.jpg', '.jpeg', '.ogg', '.wav', '.ttf', '.otf'}
MAX_ASSET = 32 * 1024 * 1024
EDITABLE = {'.lua', '.md', '.txt', '.json', '.glsl', '.html', '.css', '.js', '.svg'}
BLOCKED = {'.git', '.codex', '.agents', '.aws', '.env', 'dist', '__pycache__'}

def schema(properties=None, required=None):
    return {'type': 'object', 'properties': properties or {}, 'required': required or [], 'additionalProperties': False}

STR = {'type': 'string'}
PATH_SCHEMA = {'type': 'array', 'items': {'type': ['string', 'integer']}, 'maxItems': 16, 'default': []}

def tool(name, description, inputs, read=False):
    return {'name': name, 'description': description, 'inputSchema': inputs,
            'annotations': {'readOnlyHint': read, 'destructiveHint': not read, 'openWorldHint': False}}

TOOLS = [
    tool('loupe_status', 'Read watched roots and the inspector clock. Game must enable mcp=true.', schema(), True),
    tool('loupe_inspect', 'Read a bounded snapshot of a watched root or nested path.', schema({'root': STR, 'path': PATH_SCHEMA}, ['root']), True),
    tool('loupe_set', 'Edit an existing scalar via Loupe undo/save history. No arbitrary code execution.', schema({'root': STR, 'path': PATH_SCHEMA, 'value': {'type': ['number', 'string', 'boolean']}}, ['root', 'path', 'value'])),
    tool('loupe_control', 'Pause/resume/step, show/hide inspector, undo/redo, or explicitly save overrides.', schema({'action': {'enum': ['pause', 'resume', 'step', 'open', 'close', 'undo', 'redo', 'save']}}, ['action'])),
    tool('project_files', 'List source files within the configured game project.', schema(), True),
    tool('project_read', 'Read a text source file within the configured game project.', schema({'path': STR}, ['path']), True),
    tool('project_write', 'Write a source file within the configured game project; preserve previous bytes under .loupe-backups.', schema({'path': STR, 'content': STR}, ['path', 'content'])),
    tool('game_scaffold', 'Create a minimal game or the complete editable Afterimage example in an empty project.', schema({'template': {'enum': ['minimal', 'afterimage'], 'default': 'minimal'}})),
    tool('project_assets', 'List image, audio and font assets with sizes and PNG dimensions.', schema(), True),
    tool('asset_import', 'Copy an image/audio/font from the explicitly configured asset inbox into assets/. Existing files are never overwritten.', schema({'source': STR, 'path': STR}, ['source', 'path'])),
    tool('game_capabilities', 'Read supported authoring workflows, reusable runtime helpers and platform limits.', schema(), True),
    tool('loupe_screenshot', 'Capture the running game window as a PNG image.', schema(), True),
    tool('game_build', 'Package the configured LÖVE project as dist/game.love, excluding local state and metadata.', schema()),
    tool('game_launch', 'Launch the configured local game. Source is executable; use only on a trusted project.', schema({'smoke_frames': {'type': 'integer', 'minimum': 1, 'maximum': 36000}})),
    tool('game_stop', 'Stop only the game process launched by this MCP server.', schema()),
]

SCAFFOLD = '''local game={x=480,y=320,r=30,speed=220,color={0.3,0.9,0.8}}
function love.update(dt)
  if love.keyboard.isDown('right','d') then game.x=game.x+game.speed*dt end
  if love.keyboard.isDown('left','a') then game.x=game.x-game.speed*dt end
end
function love.draw()
  love.graphics.clear(0.02,0.04,0.07)
  love.graphics.setColor(game.color)
  love.graphics.circle('fill',game.x,game.y,game.r)
  love.graphics.setColor(1,1,1)
  love.graphics.print('A/D moves. F1 opens Loupe. AI can inspect the game root.',30,30)
end
local enabled=false
for _,v in ipairs(arg or {}) do if v=='--mcp' then enabled=true end end
local loupe=require('loupe')
loupe.watch(game,'game')
loupe.attach({mcp=enabled,center=true})
'''

class Server:
    def __init__(self, project, bridge, love, asset_inbox=None):
        self.project = Path(project).resolve()
        if not self.project.is_dir():
            raise ValueError('project directory does not exist')
        self.bridge = Path(bridge).expanduser().resolve() if bridge else None
        self.asset_inbox = Path(asset_inbox).resolve() if asset_inbox else None
        self.love = love
        self.process = None
        self.initialized = False

    def source_path(self, relative, extensions=EDITABLE):
        if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
            raise ValueError('use a relative project path')
        parts = Path(relative).parts
        if '..' in parts or any(p in BLOCKED or p.startswith('.') for p in parts):
            raise ValueError('hidden, generated, or traversal paths are not allowed')
        candidate = self.project
        for part in parts:
            candidate = candidate / part
            if candidate.is_symlink():
                raise ValueError('symlink paths are not allowed')
        path = candidate.resolve()
        if not path.is_relative_to(self.project) or path.suffix.lower() not in extensions:
            raise ValueError('path must be an allowed text file inside the project')
        return path

    def rpc_game(self, action, root='', path=None, value=None):
        if not self.bridge or not (self.bridge / 'session').is_file():
            raise ValueError('No live bridge. Start the game with loupe.attach({mcp=true}) and configure --bridge-dir.')
        def enc(s): return str(s).encode('utf-8').hex()
        path = path or []
        if not isinstance(root, str) or not isinstance(path, list) or len(path) > 16:
            raise ValueError('invalid root/path')
        for k in path:
            if type(k) not in (str, int): raise ValueError('path keys must be strings or integers')
        if isinstance(value, bool): kind, raw = 'boolean', str(value).lower()
        elif isinstance(value, (int, float)):
            if not math.isfinite(value): raise ValueError('number must be finite')
            kind, raw = 'number', str(value)
        elif isinstance(value, str):
            if len(value.encode('utf-8')) > 2048: raise ValueError('string too long')
            kind, raw = 'string', value
        elif value is None: kind, raw = 'nil', ''
        else: raise ValueError('only scalar values are supported')
        ident = uuid.uuid4().hex
        request = self.bridge / (ident + '.request')
        response = self.bridge / (ident + '.response')
        temporary = self.bridge / (ident + '.tmp')
        session = (self.bridge / 'session').read_text()
        data = '\n'.join([session, str(int(time.time()) + 8), action, enc(root),
                          '/'.join(('n' if type(k) is int else 's') + enc(k) for k in path), kind, enc(raw)])
        if len(data) > 16384: raise ValueError('request too large')
        temporary.write_text(data)
        os.replace(temporary, request)
        deadline = time.monotonic() + 10
        try:
            while time.monotonic() < deadline:
                if response.exists():
                    result = json.loads(response.read_text())
                    if not result.get('ok'): raise ValueError(result.get('error', 'game rejected request'))
                    return result.get('result')
                time.sleep(.02)
            raise TimeoutError('Game did not answer. It may be closed. Inspect state before retrying any edit.')
        finally:
            request.unlink(missing_ok=True)
            response.unlink(missing_ok=True)
            temporary.unlink(missing_ok=True)

    def call(self, name, args):
        spec = next((x for x in TOOLS if x['name'] == name), None)
        if not spec: raise ValueError('unknown tool')
        if not isinstance(args, dict): raise ValueError('arguments must be an object')
        props = spec['inputSchema']['properties']
        if set(args) - set(props) or set(spec['inputSchema']['required']) - set(args):
            raise ValueError('missing or unexpected arguments')
        if name == 'loupe_screenshot':
            result = self.rpc_game('screenshot')
            filename = result['file']
            if Path(filename).name != filename or not filename.endswith('.png'): raise ValueError('invalid screenshot path')
            path = self.bridge / filename
            data = path.read_bytes();path.unlink()
            return {'_image':base64.b64encode(data).decode()}
        if name == 'loupe_status': return self.rpc_game('status')
        if name == 'loupe_inspect': return self.rpc_game('inspect', args['root'], args.get('path'))
        if name == 'loupe_set': return self.rpc_game('set', args['root'], args['path'], args['value'])
        if name == 'loupe_control':
            action = args['action']
            if action not in props['action']['enum']: raise ValueError('unknown action')
            return self.rpc_game(action)
        if name == 'game_capabilities':
            return {
                'templates': ['minimal', 'afterimage'],
                'runtime': {'loupe.sprites': 'Grid atlases: load, frame, draw; looping and one-shot animations.',
                            'loupe.collision': 'sweepCircle: continuous circle collision, not a rigid-body physics engine.',
                            'loupe.window': 'Resizable/fullscreen and high-DPI window helpers.'},
                'afterimage': ['illustrated/vector art', 'modular ship attachments', 'red enemy shots',
                              'music and effects', 'story/endless balance', 'keyboard/menu focus', 'scaled HUD'],
                'workflow': ['game_scaffold', 'project_read/project_write', 'asset_import', 'game_build',
                             'game_launch', 'loupe_inspect/loupe_set', 'loupe_control', 'loupe_screenshot'],
                'limits': ['Live bridge requires native LÖVE; browser builds do not expose MCP.',
                           'Asset generation is external; import files from the configured inbox.',
                           'Source and imported assets require restart; scalar edits are live.',
                           'game_build makes a .love archive. Browser export uses the documented love.js builder.',
                           'Game rules, UI styling and attachment composition live in the editable Afterimage template.']}
        if name == 'project_assets':
            result = []
            for path in sorted(self.project.rglob('*')):
                rel = str(path.relative_to(self.project))
                try: checked = self.source_path(rel, ASSETS)
                except ValueError: continue
                if not checked.is_file(): continue
                item = {'path': rel, 'bytes': checked.stat().st_size}
                if checked.suffix.lower() == '.png':
                    with checked.open('rb') as stream: header = stream.read(24)
                    if header[:8] == b'\x89PNG\r\n\x1a\n' and len(header) == 24:
                        item['width'], item['height'] = struct.unpack('>II', header[16:24])
                result.append(item)
                if len(result) == 1000: break
            return {'assets': result}
        if name == 'asset_import':
            if not self.asset_inbox or not self.asset_inbox.is_dir():
                raise ValueError('Configure --asset-inbox to explicitly allow local asset imports')
            # Reuse identical path checks rooted at the inbox; no arbitrary host reads.
            inbox = Server(self.asset_inbox, None, self.love)
            source = inbox.source_path(args['source'], ASSETS)
            target = self.source_path(args['path'], ASSETS)
            if Path(args['path']).parts[0] != 'assets': raise ValueError('destination must be under assets/')
            if source.suffix.lower() != target.suffix.lower(): raise ValueError('asset extensions must match')
            if not source.is_file() or source.stat().st_size > MAX_ASSET: raise ValueError('asset missing or exceeds 32 MiB')
            if target.exists(): raise ValueError('destination exists; use a new asset filename')
            data = source.read_bytes()
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('xb') as stream: stream.write(data)
            return {'imported': args['path'], 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                    'note': 'Record source/license in ASSETS.md, reference the asset in Lua, then restart.'}
        if name == 'project_files':
            return {'files': [str(p.relative_to(self.project)) for p in sorted(self.project.rglob('*'))
                              if p.is_file() and not p.is_symlink() and p.suffix in EDITABLE
                              and not any(x.startswith('.') or x in BLOCKED for x in p.relative_to(self.project).parts)][:1000]}
        if name == 'project_read':
            path = self.source_path(args['path'])
            if path.stat().st_size > 262144: raise ValueError('file exceeds 256 KiB')
            return {'path': args['path'], 'content': path.read_text()}
        if name == 'project_write':
            path = self.source_path(args['path'])
            content = args['content']
            if not isinstance(content, str) or len(content.encode()) > 262144: raise ValueError('content exceeds 256 KiB')
            backup = None
            if path.exists():
                backup = self.project / '.loupe-backups' / (uuid.uuid4().hex + path.suffix)
                backup.parent.mkdir(exist_ok=True)
                backup.write_bytes(path.read_bytes())
            path.parent.mkdir(parents=True, exist_ok=True)
            temp = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
            temp.write_text(content); os.replace(temp, path)
            return {'written': args['path'], 'backup': str(backup) if backup else None,
                    'note': 'Restart or use game hot reload to apply source changes.'}
        if name == 'game_scaffold':
            if any(self.project.iterdir()): raise ValueError('scaffold requires an empty project directory')
            template = args.get('template', 'minimal')
            if template not in ('minimal', 'afterimage'): raise ValueError('unknown template')
            library = Path(__file__).resolve().parent.parent / 'loupe'
            if not library.is_dir(): raise ValueError('Loupe library missing beside MCP server')
            shutil.copytree(library, self.project / 'loupe')
            shutil.copyfile(library.parent / 'LICENSE', self.project / 'LOUPE-LICENSE')
            if template == 'afterimage':
                example = library.parent / 'examples' / 'afterimage'
                shutil.copytree(example, self.project, dirs_exist_ok=True,
                                ignore=shutil.ignore_patterns('dist', '.*', '__pycache__', '*.pyc', 'loupe_overrides.lua'))
                config = self.project / 'conf.lua'
                config.write_text(config.read_text().replace('afterimage-first-flight', 'loupe-' + uuid.uuid4().hex))
                return {'created': str(self.project), 'template': template,
                        'note': 'Complete source/assets/tests/web exporter copied. Read conf.lua for the unique bridge identity.'}
            (self.project / 'main.lua').write_text(SCAFFOLD)
            (self.project / 'conf.lua').write_text("function love.conf(t) t.identity='loupe-" + uuid.uuid4().hex + "'; t.window.title='Loupe playground'; t.window.width=960; t.window.height=640 end\n")
            return {'created':str(self.project),'note':'Run game_launch, then inspect the game root.'}
        if name == 'game_build':
            if not (self.project / 'main.lua').is_file(): raise ValueError('main.lua is required')
            dest = self.project / 'dist' / 'game.love';dest.parent.mkdir(exist_ok=True)
            temp = dest.with_suffix('.tmp')
            count = 0
            with zipfile.ZipFile(temp, 'w', zipfile.ZIP_DEFLATED) as archive:
                for p in sorted(self.project.rglob('*')):
                    rel = p.relative_to(self.project)
                    if not p.is_file() or p.is_symlink(): continue
                    if any(x.startswith('.') or x in BLOCKED or x in {'tests','mcp','tools'} for x in rel.parts): continue
                    if p.name == 'loupe_overrides.lua' or p.suffix in {'.love','.zip','.log','.pyc'}: continue
                    archive.write(p, str(rel));count += 1
                library = Path(__file__).resolve().parent.parent / 'loupe'
                if self.project.parent == library.parent / 'examples' and not (self.project / 'loupe').exists():
                    for module in sorted(library.rglob('*')):
                        if module.is_file() and not module.is_symlink() and not any(x.startswith('.') for x in module.relative_to(library).parts):
                            archive.write(module, 'loupe/' + str(module.relative_to(library)));count += 1
            os.replace(temp, dest)
            return {'artifact': str(dest), 'files': count}
        if name == 'game_launch':
            if self.process and self.process.poll() is None: raise ValueError('owned game is already running')
            command = [self.love, str(self.project), '--mcp']
            frames = args.get('smoke_frames')
            if frames is not None:
                if type(frames) is not int or not 1 <= frames <= 36000: raise ValueError('invalid frame count')
                command += ['--smoke', str(frames)]
            # Never inherit stdout: game logs would corrupt MCP's JSON-RPC stream.
            self.process = subprocess.Popen(command, cwd=self.project, stdout=subprocess.DEVNULL, stderr=sys.stderr)
            return {'pid': self.process.pid, 'note': 'Process started; use loupe_status to verify the live bridge.'}
        if name == 'game_stop':
            if self.process and self.process.poll() is None:
                self.process.terminate()
                try: self.process.wait(timeout=3)
                except subprocess.TimeoutExpired: self.process.kill();self.process.wait()
            return {'stopped': True}
        raise ValueError('unhandled tool')

    def handle(self, msg):
        if not isinstance(msg, dict) or msg.get('jsonrpc') != '2.0' or not isinstance(msg.get('method'), str):
            return {'jsonrpc':'2.0','id':None,'error':{'code':-32600,'message':'Invalid Request'}}
        ident = msg.get('id'); method = msg['method']; params = msg.get('params', {})
        if 'id' not in msg: return None
        if method == 'initialize':
            self.initialized = True
            version = params.get('protocolVersion') if isinstance(params,dict) else None
            result = {'protocolVersion':version if version in PROTOCOLS else PROTOCOLS[0],
                      'capabilities':{'tools':{}},'serverInfo':{'name':'loupe','version':'1.2.0'}}
        elif method == 'ping': result = {}
        elif not self.initialized:
            return {'jsonrpc':'2.0','id':ident,'error':{'code':-32000,'message':'Initialize first'}}
        elif method == 'tools/list': result = {'tools':TOOLS}
        elif method == 'tools/call':
            try:
                value = self.call(params['name'], params.get('arguments',{}))
                if isinstance(value,dict) and '_image' in value:
                    result = {'content':[{'type':'image','mimeType':'image/png','data':value['_image']}]}
                else:
                    result = {'content':[{'type':'text','text':json.dumps(value,ensure_ascii=False,allow_nan=False)}]}
            except Exception as exc:
                result = {'isError':True,'content':[{'type':'text','text':str(exc)}]}
        else: return {'jsonrpc':'2.0','id':ident,'error':{'code':-32601,'message':'Method not found'}}
        return {'jsonrpc':'2.0','id':ident,'result':result}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',required=True)
    parser.add_argument('--bridge-dir')
    parser.add_argument('--love',default='love')
    parser.add_argument('--asset-inbox', help='Explicit directory of assets allowed for import; disabled by default')
    args=parser.parse_args()
    server=Server(args.project,args.bridge_dir,args.love,args.asset_inbox)
    while True:
        line=sys.stdin.buffer.readline(MAX_MESSAGE+1)
        if not line: break
        if len(line)>MAX_MESSAGE:
            print('MCP input exceeds limit',file=sys.stderr);break
        try: response=server.handle(json.loads(line))
        except (ValueError,UnicodeError): response={'jsonrpc':'2.0','id':None,'error':{'code':-32700,'message':'Parse error'}}
        if response is not None: print(json.dumps(response,ensure_ascii=False,allow_nan=False),flush=True)

if __name__=='__main__': main()
