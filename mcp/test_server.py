import json
from pathlib import Path
import tempfile
import unittest
import zipfile
from server import Server

class ServerTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        (self.root/'main.lua').write_text('return 1')
        self.s=Server(self.root,None,'love')
    def tearDown(self): self.tmp.cleanup()
    def test_handshake_and_tools(self):
        reply=self.s.handle({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25'}})
        self.assertEqual(reply['result']['protocolVersion'],'2025-11-25')
        self.assertIsNone(self.s.handle({'jsonrpc':'2.0','method':'notifications/initialized'}))
        reply=self.s.handle({'jsonrpc':'2.0','id':2,'method':'tools/list'})
        self.assertGreaterEqual(len(reply['result']['tools']),10)
    def test_path_boundaries(self):
        for name in ['../escape.lua','/tmp/escape.lua','.git/config','dist/a.lua','.env','foo.py']:
            with self.assertRaises(ValueError): self.s.source_path(name)
        with tempfile.TemporaryDirectory() as outside:
            (self.root/'link').symlink_to(outside,target_is_directory=True)
            with self.assertRaises(ValueError): self.s.source_path('link/evil.lua')
    def test_rejects_internal_symlink(self):
        (self.root/'alias.lua').symlink_to(self.root/'main.lua')
        with self.assertRaises(ValueError): self.s.source_path('alias.lua')
    def test_write_has_recovery(self):
        result=self.s.call('project_write',{'path':'main.lua','content':'return 2'})
        self.assertEqual(Path(result['backup']).read_text(),'return 1')
        self.assertEqual(self.s.call('project_read',{'path':'main.lua'})['content'],'return 2')
    def test_build_excludes_private_state(self):
        (self.root/'.env').write_text('private')
        (self.root/'loupe_overrides.lua').write_text('private')
        (self.root/'analytics.config.lua').write_text('return { ingestKey = "gt_pub_x" }')
        self.s.call('project_write',{'path':'main.lua','content':'return 2'})
        result=self.s.call('game_build',{})
        with zipfile.ZipFile(result['artifact']) as z: self.assertEqual(z.namelist(),['main.lua'])
    def test_errors_are_tool_results(self):
        self.s.initialized=True
        result=self.s.handle({'jsonrpc':'2.0','id':1,'method':'tools/call','params':{'name':'loupe_status'}})
        self.assertTrue(result['result']['isError'])
        self.assertEqual(self.s.handle([])['error']['code'],-32600)
    def test_rejects_unknown_arguments(self):
        with self.assertRaises(ValueError): self.s.call('game_launch',{'shell':'bad'})
        with self.assertRaises(ValueError): self.s.call('project_write',{'path':'a.lua'})


class AuthoringTests(unittest.TestCase):
    def test_afterimage_template_builds_and_uses_shared_helpers(self):
        with tempfile.TemporaryDirectory() as directory:
            server = Server(directory, None, 'love')
            server.call('game_scaffold', {'template':'afterimage'})
            root = Path(directory)
            self.assertTrue((root/'assets/effects/exhaust-atlas.png').exists())
            self.assertIn('loupe.sprites', (root/'src/sprites.lua').read_text())
            self.assertTrue((root/'loupe/collision.lua').exists())
            self.assertNotIn('afterimage-first-flight', (root/'conf.lua').read_text())
            with self.assertRaises(ValueError): server.call('game_scaffold', {})
            result = server.call('game_build', {})
            with zipfile.ZipFile(result['artifact']) as archive:
                self.assertIn('loupe/sprites.lua', archive.namelist())
                self.assertNotIn('tools/build_web.py', archive.namelist())
            assets = server.call('project_assets', {})['assets']
            exhaust = next(a for a in assets if a['path']=='assets/effects/exhaust-atlas.png')
            self.assertGreater(exhaust['width'], 0)

    def test_asset_inbox_boundaries_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as inbox:
            root = Path(directory); source = Path(inbox)
            (source/'sound.ogg').write_bytes(b'OggSfixture')
            server = Server(root, None, 'love')
            args = {'source':'sound.ogg','path':'assets/sound.ogg'}
            with self.assertRaises(ValueError): server.call('asset_import', args)
            server = Server(root, None, 'love', inbox)
            server.call('asset_import', args)
            self.assertEqual((root/'assets/sound.ogg').read_bytes(), b'OggSfixture')
            with self.assertRaises(ValueError): server.call('asset_import', args)
            for source_path, target in [('../sound.ogg','assets/other.ogg'), ('sound.ogg','other.ogg'),
                                        ('sound.ogg','assets/../../other.ogg'), ('sound.ogg','assets/other.lua')]:
                with self.assertRaises(ValueError):
                    server.call('asset_import', {'source':source_path,'path':target})
            (source/'link.ogg').symlink_to(source/'sound.ogg')
            with self.assertRaises(ValueError):
                server.call('asset_import', {'source':'link.ogg','path':'assets/link.ogg'})

    def test_browser_wrapper_is_editable(self):
        with tempfile.TemporaryDirectory() as directory:
            server = Server(directory, None, 'love')
            for path in ('tools/web/index.html', 'tools/web/love.css', 'tools/web/input.js'):
                server.call('project_write', {'path':path, 'content':'fixture'})
                self.assertEqual(server.call('project_read', {'path':path})['content'], 'fixture')

    def test_minimal_identity_is_unique(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            for directory in (a,b): Server(directory, None, 'love').call('game_scaffold', {})
            self.assertNotEqual((Path(a)/'conf.lua').read_text(), (Path(b)/'conf.lua').read_text())

if __name__=='__main__': unittest.main()
