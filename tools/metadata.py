"""Bind generated evidence to the exact implementation and firmware image."""
import hashlib
from pathlib import Path

def metadata(root):
    root=Path(root)
    paths=[root/'CMakeLists.txt',root/'requirements-tools.txt']
    for directory,extensions in [('rtl',{'.sv'}),('sim',{'.sv','.cpp','.h'}),('tools',{'.py'}),('firmware',{'.py'})]:
        paths.extend(p for p in (root/directory).rglob('*') if p.suffix in extensions)
    digest=hashlib.sha256()
    for path in sorted(paths):
        # Git may normalize working-tree line endings. Hash canonical text so a
        # clean checkout and the original Windows workspace identify the same code.
        digest.update(path.relative_to(root).as_posix().encode()+b'\0'+path.read_bytes().replace(b'\r\n',b'\n'))
    image=root/'build/firmware.hex'
    return {'source_sha256':digest.hexdigest(),
            'firmware_sha256':hashlib.sha256(image.read_bytes()).hexdigest() if image.exists() else None}
