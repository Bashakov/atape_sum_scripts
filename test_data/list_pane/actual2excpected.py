from pathlib import Path

for src in Path().glob('*.actual'):
    print(src)
    dst = Path(src.stem)
    if dst.exists():
        dst.unlink()
    src.rename(dst)
