import contextlib
import io
from pathlib import Path
import tempfile
import unittest
import zipfile
import audit_release as audit

PUB = b'gt_' + b'pub_' + b'A' * 16
PRIVATE = b'gt_' + b'live_' + b'B' * 16

def archive(entries):
    out = io.BytesIO()
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in entries.items(): z.writestr(name, data)
    return out.getvalue()

class ArtifactTests(unittest.TestCase):
    def scan(self, filename, data):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder)/filename;p.write_bytes(data)
            with contextlib.redirect_stdout(io.StringIO()):return audit.audit_artifacts([p])

    def test_only_injected_public_key_allowed(self):
        self.assertFalse(self.scan('game.love', archive({'analytics.config.lua':b'return { ingestKey="'+PUB+b'" }'})))
        self.assertFalse(self.scan('web.zip', archive({'index.html':b"const RAVENSIGHT_PUBLIC_KEY='"+PUB+b"';"})))
        for data in [b'// '+PUB, b"const RAVENSIGHT_PUBLIC_KEY='"+PRIVATE+b"';", b"const RAVENSIGHT_PUBLIC_KEY='"+PUB+b"'; // "+PUB]:
            self.assertTrue(self.scan('index.html', data))

    def test_other_secrets_and_private_state(self):
        for data in [b'gh' + b'p_' + b'X'*36, b'-----BEGIN '+b'PRIVATE KEY-----', b'/Users/'+b'private_person/file']:
            self.assertTrue(self.scan('web.zip', archive({'secret.txt':data})))
        self.assertTrue(self.scan('game.love', archive({'.env.production':b'password=example'})))

    def test_source_archive_nested_in_distribution(self):
        source=archive({'game.love':archive({'analytics.config.lua':b'return { ingestKey="'+PUB+b'" }'})})
        self.assertTrue(self.scan('release.zip',archive({'afterimage-source.zip':source})))

    def test_nested_archives_are_scanned_or_rejected(self):
        data=archive({'secret.txt':PRIVATE})
        for _ in range(5):data=archive({'nested.zip':data})
        self.assertTrue(self.scan('release.zip',data))
        for _ in range(5):data=archive({'nested.zip':data})
        self.assertTrue(self.scan('release.zip',data))

    def test_bad_archives_and_unsafe_paths(self):
        self.assertTrue(self.scan('broken.zip',b'not a readable zip'))
        self.assertTrue(self.scan('game.zip',archive({'../index.html':PUB})))
        out=io.BytesIO()
        with zipfile.ZipFile(out,'w') as z:
            info=zipfile.ZipInfo('link');info.create_system=3;info.external_attr=0o120777<<16
            z.writestr(info,'outside')
        self.assertTrue(self.scan('web.zip',out.getvalue()))

    def test_filesystem_symlink_is_reported(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder);(path/'file').write_text('safe');(path/'link').symlink_to(path/'file')
            with contextlib.redirect_stdout(io.StringIO()):self.assertTrue(audit.audit_artifacts([path]))

    def test_expansion_limit_fails_closed(self):
        previous=audit.MAX_EXPANDED_BYTES
        try:
            audit.MAX_EXPANDED_BYTES=8
            self.assertTrue(self.scan('release.zip',archive({'a':b'x'*9})))
        finally:audit.MAX_EXPANDED_BYTES=previous

if __name__=='__main__':unittest.main()
