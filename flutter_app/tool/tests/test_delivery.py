import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile
spec = importlib.util.spec_from_file_location('delivery', Path(__file__).resolve().parents[1] / 'package_ble_delivery.py')
delivery = importlib.util.module_from_spec(spec); spec.loader.exec_module(delivery)
class Tests(unittest.TestCase):
    def test_whitelist_excludes_sensitive_inputs(self):
        files = delivery.public_files(Path('/synthetic'), Path('/apk'), ['ble_primary'])
        self.assertTrue(all(not any(word in name for word in ('sdkconfig','nvs','password','log','key')) for name in files))
        self.assertEqual(len(files), 12)
    def test_archive_hashes_and_exclusive_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); item=root/'input'; item.write_bytes(b'public synthetic')
            output=root/'out.zip'; delivery.create({'public.txt':item}, output, '0.2.9+11', ['ble_primary'])
            with zipfile.ZipFile(output) as archive:
                meta=json.loads(archive.read('manifest.json'))
                self.assertFalse(meta['hardware_verified'])
                self.assertEqual(meta['files']['public.txt']['sha256'], delivery.digest(item.read_bytes()))
            with self.assertRaises(FileExistsError): delivery.create({'public.txt':item}, output, 'v', [])
    def test_version_reads_actual_apk(self):
        import subprocess
        result=subprocess.CompletedProcess([],0,"package: name='example' versionCode='11' versionName='0.2.9'")
        with patch.object(delivery.subprocess,'run',return_value=result):
            self.assertEqual(delivery.apk_version(Path('/synthetic'),'aapt'),'0.2.9+11')
    def test_default_plan_never_runs_aapt_or_creates_output(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(delivery.subprocess,'run',side_effect=AssertionError):
            output=Path(directory)/'out.zip'
            self.assertEqual(delivery.main(['--firmware-root',directory,'--output',str(output)]),0)
            self.assertFalse(output.exists())
    def test_symlink_inputs_and_parent_links_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);private=root/'private';private.mkdir();secret=private/'secret';secret.write_bytes(b'synthetic private marker')
            link=root/'link';link.symlink_to(secret)
            parent=root/'public';parent.symlink_to(private,target_is_directory=True)
            for path in (link,parent/'secret'):
                with self.assertRaises(ValueError):delivery.snapshots({'public':path})
    def test_frozen_bytes_used_for_manifest_and_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'file';source.write_bytes(b'first')
            frozen=delivery.snapshots({'public':source});source.write_bytes(b'second')
            delivery.create(frozen,root/'out.zip','v',[])
            with zipfile.ZipFile(root/'out.zip') as archive:
                self.assertEqual(archive.read('public'),b'first')
                self.assertEqual(json.loads(archive.read('manifest.json'))['files']['public']['sha256'],delivery.digest(b'first'))
    def test_cli_does_not_resolve_away_root_link(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);private=root/'private';private.mkdir();(private/'file').write_bytes(b'synthetic-secret')
            link=root/'firmware';link.symlink_to(private,target_is_directory=True)
            with patch.object(delivery,'public_files',side_effect=lambda firmware,*a:{'android/app-arm64-v8a-release.apk':firmware/'file'}),patch.object(delivery,'apk_version',side_effect=AssertionError):
                self.assertEqual(delivery.main(['--firmware-root',str(link),'--output',str(root/'out.zip'),'--aapt','synthetic','--execute']),2)
            self.assertFalse((root/'out.zip').exists())
