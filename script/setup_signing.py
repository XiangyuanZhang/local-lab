#!/usr/bin/env python3
"""Create a dedicated local signing identity without changing global trust."""
import subprocess, secrets, os
from pathlib import Path
root = Path(__file__).resolve().parent.parent
p = root / '.local-signing'
p.mkdir(parents=True, exist_ok=True); os.chmod(p, 0o700)
k = p / 'local-lab.keychain-db'; pwfile = p / 'keychain-password'
def run(args):
    completed = subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if completed.returncode: raise RuntimeError('Local signing setup failed: ' + completed.stderr.decode(errors='replace'))
if not k.exists():
    pw = secrets.token_hex(24); pwfile.write_text(pw); os.chmod(pwfile, 0o600)
    cfg = p / 'certificate.conf'
    cfg.write_text('[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=Local Lab Local Signing\n[ext]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=codeSigning\n')
    run(['/usr/bin/openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(p/'key.pem'),'-out',str(p/'cert.pem'),'-days','3650','-config',str(cfg)])
    run(['/usr/bin/openssl','pkcs12','-export','-inkey',str(p/'key.pem'),'-in',str(p/'cert.pem'),'-out',str(p/'identity.p12'),'-passout','pass:'+pw])
    run(['/usr/bin/security','create-keychain','-p',pw,str(k)])
    run(['/usr/bin/security','unlock-keychain','-p',pw,str(k)])
    run(['/usr/bin/security','import',str(p/'identity.p12'),'-k',str(k),'-P',pw,'-T','/usr/bin/codesign'])
    run(['/usr/bin/security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',pw,str(k)])
    for filename in ('key.pem','identity.p12'): (p/filename).unlink()
else:
    run(['/usr/bin/security','unlock-keychain','-p',pwfile.read_text().strip(),str(k)])
