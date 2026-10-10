import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('publisher', Path(__file__).with_name('publish-download.py'))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)

class UploadGuards(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / 'release').mkdir()
        (self.root / 'release/version.json').write_text(json.dumps({'version':'0.1.0','build':1,'freezeUntilStoresPublished':True}))
        self.artifact = self.root / 'app.zip'
        self.artifact.write_bytes(b'fixture')
        self.args = ['publish-download.py','--profile','test','--expected-account','123456789012','--revision','20261010.1','--artifact',f'macos-zip={self.artifact}','--publish']
    def tearDown(self): self.temp.cleanup()
    def invoke(self, fake, args=None):
        with patch.object(publisher,'ROOT',self.root), patch.object(publisher,'aws',side_effect=fake), patch.object(sys,'argv',args or self.args), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()): publisher.main()
    def test_wrong_account_cannot_upload(self):
        calls=[]
        def fake(*a,**k): calls.append(a); return {'Account':'000000000000'}
        with self.assertRaisesRegex(RuntimeError,'account mismatch'): self.invoke(fake)
        self.assertEqual(len(calls),1)
    def test_disabled_versioning_cannot_upload(self):
        calls=[]
        def fake(*a,**k):
            calls.append(a)
            if 'get-caller-identity' in a:return {'Account':'123456789012'}
            if 'get-bucket-versioning' in a:return {'Status':'Suspended'}
            return {}
        with self.assertRaisesRegex(RuntimeError,'versioning'): self.invoke(fake)
        self.assertFalse(any('put-object' in a for a in calls))
    def test_different_existing_bytes_cannot_upload(self):
        calls=[]
        def fake(*a,**k):
            calls.append(a)
            if 'get-caller-identity' in a:return {'Account':'123456789012'}
            if 'get-bucket-versioning' in a:return {'Status':'Enabled'}
            if 'get-public-access-block' in a:return {'PublicAccessBlockConfiguration':dict.fromkeys(['BlockPublicAcls','IgnorePublicAcls','BlockPublicPolicy','RestrictPublicBuckets'],True)}
            if 'head-object' in a:return {'Metadata':{'sha256':'different'}}
            return {}
        with self.assertRaisesRegex(RuntimeError,'different bytes'): self.invoke(fake)
        self.assertFalse(any('put-object' in a for a in calls))
    def test_path_escape_revision_rejected_before_aws(self):
        args=self.args.copy(); args[args.index('--revision')+1]='../../escape'
        with self.assertRaises(SystemExit): self.invoke(lambda *a,**k:self.fail('AWS called'),args)
    def test_symlink_rejected_before_aws(self):
        link=self.root/'link.zip';link.symlink_to(self.artifact)
        args=self.args.copy();args[args.index('--artifact')+1]=f'macos-zip={link}'
        with self.assertRaises(SystemExit):self.invoke(lambda *a,**k:self.fail('AWS called'),args)

if __name__ == '__main__':unittest.main()
