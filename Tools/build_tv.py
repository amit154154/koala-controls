"""Build the permission-free Koala TV launcher alongside the signed host."""
from pathlib import Path
import plistlib,subprocess,sys,shutil,os,platform
root=Path(__file__).resolve().parent.parent
out=Path(sys.argv[1]);identity=sys.argv[2]
(out/'Contents/MacOS').mkdir(parents=True,exist_ok=True);(out/'Contents/Resources').mkdir(parents=True,exist_ok=True)
subprocess.run(['swiftc','-O','-target',os.environ.get('KOALA_ARCH',platform.machine())+'-apple-macosx13.0','-parse-as-library',str(root/'Tools/TVLauncher.swift'),'-o',str(out/'Contents/MacOS/KoalaTV')],check=True)
shutil.copy2(root/'Resources/TVIcon.icns',out/'Contents/Resources/AppIcon.icns')
info=dict(CFBundleName='Koala TV',CFBundleDisplayName='Koala TV',CFBundleIdentifier='local.koalatv.launcher',CFBundleExecutable='KoalaTV',CFBundlePackageType='APPL',CFBundleShortVersionString='1.1.0',CFBundleVersion='2',CFBundleIconFile='AppIcon',LSMinimumSystemVersion='13.0',LSUIElement=True)
(out/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['codesign','--force','--sign',identity,str(out)],check=True);subprocess.run(['codesign','--verify','--deep','--strict',str(out)],check=True)
