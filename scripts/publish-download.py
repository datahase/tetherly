#!/usr/bin/env python3
"""Publish explicitly selected local artifacts. Never builds, signs, or loads secrets."""
import argparse, base64, hashlib, json, os, re, subprocess, tempfile, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def aws(profile, region, *args, allow_missing=False):
    result = subprocess.run(['aws', '--profile', profile, '--region', region, *args, '--output', 'json'], text=True, capture_output=True)
    if result.returncode:
        if allow_missing and ('Not Found' in result.stderr or '(404)' in result.stderr or 'NoSuchKey' in result.stderr): return None
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout) if result.stdout.strip() else {}


def verify_artifact(plan, expected_android_cert):
    source = Path(plan['source'])
    def check(*args): return subprocess.run(list(args), check=True, text=True, capture_output=True)
    if source.suffix == '.apk':
        if not expected_android_cert or not re.fullmatch(r'[0-9a-fA-F]{64}', expected_android_cert): raise RuntimeError('Supply the expected Android signing certificate SHA256.')
        sdk = Path(os.environ.get('ANDROID_HOME', str(Path.home() / 'Library/Android/sdk')))
        tools = list((sdk / 'build-tools').glob('*/apksigner'))
        if not tools: raise RuntimeError('Android SDK apksigner is required.')
        signer = max(tools, key=lambda p: tuple(int(n) for n in re.findall(r'\d+', p.parent.name)))
        output = check(str(signer), 'verify', '--print-certs', str(source)).stdout
        certificates = re.findall(r'certificate SHA-256 digest: ([0-9a-fA-F]+)', output)
        if not certificates or any(c.lower() != expected_android_cert.lower() for c in certificates): raise RuntimeError('Android signing certificate mismatch.')
        check(str(ROOT / 'scripts/check-android-qr-registrars.sh'), str(source))
    elif source.suffix == '.dmg':
        check('hdiutil', 'verify', str(source))
        check('codesign', '--verify', '--strict', str(source))
        check('xcrun', 'stapler', 'validate', str(source))
        check('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', str(source))
    else:
        with tempfile.TemporaryDirectory(prefix='tetherly-verify-') as folder:
            with zipfile.ZipFile(source) as archive:
                for name in archive.namelist():
                    if name.startswith('/') or '..' in Path(name).parts: raise RuntimeError('Unsafe ZIP entry.')
            check('ditto', '-x', '-k', str(source), folder)
            app = Path(folder) / 'Tetherly.app'
            if not app.is_dir() or app.is_symlink(): raise RuntimeError('ZIP must contain Tetherly.app.')
            check('codesign', '--verify', '--deep', '--strict', str(app))
            check('xcrun', 'stapler', 'validate', str(app))
            check('spctl', '--assess', '--type', 'execute', str(app))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True)
    parser.add_argument('--expected-account', required=True)
    parser.add_argument('--region', default='ap-south-1')
    parser.add_argument('--bucket', default='tetherly-release')
    parser.add_argument('--revision', required=True, help='Unique distribution revision, such as 20261010.1; app version stays separate.')
    parser.add_argument('--artifact', action='append', required=True, metavar='PLATFORM=FILE', help='macos-dmg, macos-zip, or android-apk')
    parser.add_argument('--android-cert-sha256', help='Expected public upload certificate fingerprint; required for APK publication.')
    parser.add_argument('--publish', action='store_true', help='Without this option, validate locally and print the upload plan only.')
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9]{12}', args.expected_account): parser.error('Expected account must be a 12-digit account ID.')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,63}', args.revision): parser.error('Invalid revision.')
    state = json.loads((ROOT / 'release/version.json').read_text())
    version = state['version']
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version): parser.error('Invalid app version.')
    if state['freezeUntilStoresPublished'] and version != '0.1.0': parser.error('App version freeze violated.')
    extensions = {'macos-dmg': '.dmg', 'macos-zip': '.zip', 'android-apk': '.apk'}
    plans = []
    for item in args.artifact:
        platform, separator, filename = item.partition('=')
        if not separator or platform not in extensions: parser.error('Invalid artifact platform.')
        source = Path(filename).expanduser()
        if source.is_symlink() or not source.is_file() or source.suffix.lower() != extensions[platform]: parser.error('Artifact must be a regular file of the expected type.')
        size = source.stat().st_size
        if not 0 < size <= 2 * 1024**3: parser.error('Invalid artifact size.')
        digest = hashlib.file_digest(source.open('rb'), 'sha256').hexdigest()
        key = f'releases/{version}/{args.revision}/Tetherly-{version}{extensions[platform]}'
        if any(p['key'] == key for p in plans): parser.error('Duplicate artifact platform.')
        plans.append({'source': str(source.resolve()), 'key': key, 'bytes': size, 'sha256': digest})
    manifest = {'version': version, 'build': state['build'], 'revision': args.revision, 'artifacts': [{k:v for k,v in p.items() if k != 'source'} for p in plans]}
    print(json.dumps(manifest, indent=2))
    if not args.publish: return
    identity = aws(args.profile, args.region, 'sts', 'get-caller-identity')
    if identity['Account'] != args.expected_account: raise RuntimeError('AWS account mismatch. Nothing uploaded.')
    aws(args.profile, args.region, 's3api', 'head-bucket', '--bucket', args.bucket, '--expected-bucket-owner', args.expected_account)
    if aws(args.profile, args.region, 's3api', 'get-bucket-versioning', '--bucket', args.bucket).get('Status') != 'Enabled': raise RuntimeError('S3 versioning must be enabled.')
    block = aws(args.profile, args.region, 's3api', 'get-public-access-block', '--bucket', args.bucket)['PublicAccessBlockConfiguration']
    if not all(block.get(k) for k in ('BlockPublicAcls','IgnorePublicAcls','BlockPublicPolicy','RestrictPublicBuckets')): raise RuntimeError('All public access blocks must be enabled.')
    # Preflight the whole batch before uploading. Existing paths cannot be replaced.
    for plan in plans:
        existing = aws(args.profile, args.region, 's3api', 'head-object', '--bucket', args.bucket, '--key', plan['key'], allow_missing=True)
        if existing and existing.get('Metadata', {}).get('sha256') != plan['sha256']: raise RuntimeError('Revision already contains different bytes. Choose a new revision.')
        plan['exists'] = bool(existing)
    for plan in plans: verify_artifact(plan, args.android_cert_sha256)
    manifest_key = f'releases/{version}/{args.revision}/manifest.json'
    manifest_existing = aws(args.profile, args.region, 's3api', 'head-object', '--bucket', args.bucket, '--key', manifest_key, allow_missing=True)
    if manifest_existing:
        with tempfile.TemporaryDirectory(prefix='tetherly-manifest-') as folder:
            previous = Path(folder) / 'previous.json'
            aws(args.profile, args.region, 's3api', 'get-object', '--bucket', args.bucket, '--key', manifest_key, str(previous))
            if json.loads(previous.read_text()) != manifest: raise RuntimeError('Existing manifest differs; choose a new revision.')
    for plan in plans:
        if plan['exists']: continue
        content = {'.dmg':'application/x-apple-diskimage','.zip':'application/zip','.apk':'application/vnd.android.package-archive'}[Path(plan['source']).suffix.lower()]
        # Conditional write protects against a race after preflight. No sync/delete or public ACL.
        aws(args.profile, args.region, 's3api', 'put-object', '--bucket', args.bucket, '--key', plan['key'], '--body', plan['source'], '--if-none-match', '*', '--content-type', content, '--content-disposition', f'attachment; filename="{Path(plan["key"]).name}"', '--cache-control', 'public,max-age=31536000,immutable', '--metadata', json.dumps({'sha256':plan['sha256']}), '--checksum-sha256', base64.b64encode(bytes.fromhex(plan['sha256'])).decode(), '--expected-bucket-owner', args.expected_account)
    with tempfile.TemporaryDirectory(prefix='tetherly-release-') as folder:
        path = Path(folder) / 'manifest.json'; path.write_text(json.dumps(manifest, indent=2) + '\n')
        if not manifest_existing:
            aws(args.profile, args.region, 's3api', 'put-object', '--bucket', args.bucket, '--key', manifest_key, '--body', str(path), '--if-none-match', '*', '--content-type', 'application/json', '--cache-control', 'public,max-age=31536000,immutable', '--expected-bucket-owner', args.expected_account)
    print('Published versioned artifacts. Verify public HTTPS downloads before changing website links.')

if __name__ == '__main__': main()
