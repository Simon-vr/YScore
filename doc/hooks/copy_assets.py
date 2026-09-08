import shutil
from pathlib import Path

def on_post_build(config, **kwargs):
    src = Path(config["config_file_path"]).parent / "image"
    dst = Path(config["site_dir"]) / "image"
    if src.exists():
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
