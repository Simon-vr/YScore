# YScore 文档静态网站

本目录通过 [MkDocs](https://www.mkdocs.org/) + [Material 主题](https://squidfunk.github.io/mkdocs-material/)
把 `learn/` 下的 Markdown 文档构建成静态网站，并借助 GitHub Actions 实现**推送到 GitHub 即自动发布**到 GitHub Pages。

## 目录结构

```
doc/
├── mkdocs.yml           # MkDocs 配置（站点名 / 导航 / 主题）
├── requirements.txt     # Python 依赖
├── hooks/
│   └── copy_assets.py   # 构建时把 image/ 拷贝进站点
├── learn/               # 文档源文件（Markdown）
└── image/               # 图片 / 视频等静态资源
```

> 说明：`docs_dir` 设为 `learn`，`image/` 通过 hook 在构建时复制到站点根目录，
> 因此站点中图片路径形如 `/image/README_zh/arch.svg`。

## 本地预览 / 构建

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# 本地预览（http://127.0.0.1:8000）
.venv/bin/mkdocs serve -f doc/mkdocs.yml

# 本地构建（输出到 doc/site/）
.venv/bin/mkdocs build -f doc/mkdocs.yml
```

## 一键发布到 GitHub Pages

1. **首次一次性配置**：在仓库 `Settings → Pages` 中，把 **Source** 选为 **GitHub Actions**。
2. 之后只要**推送到 `master`（或 `main`）分支并改动 `doc/` 下内容**，GitHub Actions
   工作流 [`.github/workflows/pages.yml`](../.github/workflows/pages.yml) 会自动构建并部署。
3. 也可以在 GitHub 仓库 **Actions → Deploy docs to GitHub Pages → Run workflow** 手动触发。
4. 部署完成后，站点地址在 `Settings → Pages` 中查看（形如 `https://<user>.github.io/YScore/`）。

> 站点 URL 若不以根路径部署，请在 `mkdocs.yml` 中增加：
> `site_url: https://<user>.github.io/YScore/`
