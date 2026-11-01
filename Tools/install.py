"""Install generated app Contents with rollback, preserving existing app-root icons.
Does not alter settings, permissions, certificates, pairing or launch apps.
"""
from pathlib import Path
import datetime, os, shutil, subprocess
ROOT=Path(__file__).resolve().parent.parent
if subprocess.run(['pgrep','-x','MiniKeyboard'],capture_output=True).returncode==0:
    raise SystemExit('Quit Mini Keyboard normally, then run: python3 Tools/install.py')
apps=['Mini Keyboard.app','Koala TV.app']
for name in apps:
    built=ROOT/'build'/name
    if not (built/'Contents/MacOS').is_dir():raise SystemExit('Build first with ./build.sh --build-only')
    subprocess.run(['codesign','--verify','--deep','--strict',str(built)],check=True)
backup=ROOT/'build/backups'/datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f');backup.mkdir(parents=True)
installed=[]
try:
    for name in apps:
        dest=Path('/Applications')/name;dest.mkdir(exist_ok=True)
        old=backup/name
        if (dest/'Contents').exists():os.rename(dest/'Contents',old)
        installed.append((dest,old))
        shutil.copytree(ROOT/'build'/name/'Contents',dest/'Contents')
        subprocess.run(['codesign','--verify','--deep',str(dest)],check=True)
except Exception:
    for dest,old in reversed(installed):
        shutil.rmtree(dest/'Contents',ignore_errors=True)
        if old.exists():os.rename(old,dest/'Contents')
    raise
print('Installed both apps. Backups:',backup)
print('Open /Applications/Mini Keyboard.app. Existing settings and pairing are unchanged.')
