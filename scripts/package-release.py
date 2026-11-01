"""Package the local build only; no settings or credentials are read."""
from pathlib import Path
import subprocess, shutil, hashlib, platform, zipfile
root=Path(__file__).resolve().parent.parent
out=root/'release';out.mkdir(exist_ok=True)
apps=out/'Koala Controls';apps.mkdir(exist_ok=True)
for name in ['Mini Keyboard.app','Koala TV.app']:
    src=root/'build'/name
    subprocess.run(['codesign','--verify','--deep','--strict',str(src)],check=True)
    shutil.copytree(src,apps/name,dirs_exist_ok=True)
(apps/'READ ME FIRST.txt').write_text('Copy both apps to /Applications and open Mini Keyboard first.\nInstall guide: https://github.com/amit154154/koala-controls/blob/main/docs/INSTALL.md\nThis build is ad-hoc signed, not notarized. No personal settings or game content are included.\n')
archive=out/('Koala-Controls-macOS-'+platform.machine()+'.zip')
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for path in sorted(apps.rglob('*')):
        if path.is_file() and path.name!='.DS_Store' and not path.name.startswith('._'):z.write(path,str(path.relative_to(out)))
vsix=out/'koala-workspace.vsix'
subprocess.run(['python3',str(root/'VSCodeExtension/package-vsix.py'),str(vsix)],check=True)
(out/'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in [archive,vsix]))
print(archive)
