#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/.."

echo "[RubyMC] Aplicando correção FORTE de CSS/layout..."

mkdir -p web/assets/css web/assets/js docs

cp -f rubymc_force_css_layout_fix_patch/web/assets/css/rubymc-force-layout-fix.css web/assets/css/rubymc-force-layout-fix.css
cp -f rubymc_force_css_layout_fix_patch/web/assets/js/rubymc-force-layout-fix.js web/assets/js/rubymc-force-layout-fix.js
cp -f rubymc_force_css_layout_fix_patch/docs/RUBYMC_FORCE_CSS_LAYOUT_FIX.md docs/RUBYMC_FORCE_CSS_LAYOUT_FIX.md

python3 - <<'PY'
from pathlib import Path

path = Path("web/index.html")
html = path.read_text(encoding="utf-8")

css = '<link rel="stylesheet" href="/assets/css/rubymc-force-layout-fix.css?v=force-layout-2">'
js = '<script src="/assets/js/rubymc-force-layout-fix.js?v=force-layout-2" defer></script>'

# Remove duplicatas antigas se existirem
for old in [
    '<link rel="stylesheet" href="/assets/css/rubymc-force-layout-fix.css?v=force-layout">',
    '<script src="/assets/js/rubymc-force-layout-fix.js?v=force-layout" defer></script>'
]:
    html = html.replace(old, "")

if css not in html:
    if "</head>" in html:
        html = html.replace("</head>", f"  {css}\n</head>")
    else:
        html = css + "\n" + html

if js not in html:
    if "</body>" in html:
        html = html.replace("</body>", f"  {js}\n</body>")
    else:
        html += "\n" + js + "\n"

path.write_text(html, encoding="utf-8")
print("[OK] CSS/JS de força injetados no index.html.")
PY

echo
echo "[OK] Correção de layout aplicada."
echo "Agora limpe a porta/cache e reinicie:"
echo "sudo fuser -k 4567/tcp 2>/dev/null || true"
echo "./rubymc restart"
