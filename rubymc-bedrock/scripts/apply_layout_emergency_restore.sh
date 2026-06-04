#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/.."

echo "[RubyMC] Restaurando layout quebrado e reaplicando patch seguro..."

mkdir -p web/assets/css web/assets/js docs

# 1) Restaurar o index.html anterior ao patch que quebrou a tela.
latest_backup="$(ls -1t web/index.html.bak.discord-panel-bg-* 2>/dev/null | head -n 1 || true)"

if [ -n "$latest_backup" ]; then
  echo "[OK] Restaurando backup: $latest_backup"
  cp -f web/index.html "web/index.html.bak.broken-layout-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  cp -f "$latest_backup" web/index.html
elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[AVISO] Backup não encontrado. Restaurando web/index.html pelo Git."
  cp -f web/index.html "web/index.html.bak.broken-layout-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  git checkout -- web/index.html || git restore web/index.html || true
else
  echo "[ERRO] Não encontrei backup nem Git para restaurar web/index.html."
  echo "Procure manualmente por: web/index.html.bak.discord-panel-bg-*"
  exit 1
fi

# 2) Copiar CSS/JS seguros.
cp -f rubymc_layout_emergency_restore_patch/web/assets/css/rubymc-layout-emergency-restore.css web/assets/css/rubymc-layout-emergency-restore.css
cp -f rubymc_layout_emergency_restore_patch/web/assets/js/rubymc-layout-emergency-restore.js web/assets/js/rubymc-layout-emergency-restore.js
cp -f rubymc_layout_emergency_restore_patch/docs/RUBYMC_LAYOUT_EMERGENCY_RESTORE.md docs/RUBYMC_LAYOUT_EMERGENCY_RESTORE.md

# 3) Injetar CSS/JS sem sobrescrever a estrutura original.
python3 - <<'PY'
from pathlib import Path
path = Path("web/index.html")
html = path.read_text(encoding="utf-8")

css_line = '<link rel="stylesheet" href="/assets/css/rubymc-layout-emergency-restore.css?v=layout-restore">'
js_line = '<script src="/assets/js/rubymc-layout-emergency-restore.js?v=layout-restore" defer></script>'

if css_line not in html:
    if "</head>" in html:
        html = html.replace("</head>", f"  {css_line}\n</head>")
    else:
        html = css_line + "\n" + html

if js_line not in html:
    if "</body>" in html:
        html = html.replace("</body>", f"  {js_line}\n</body>")
    else:
        html += "\n" + js_line + "\n"

path.write_text(html, encoding="utf-8")
print("[OK] CSS/JS de restauração injetados.")
PY

echo
echo "[OK] Layout restaurado."
echo "Agora rode:"
echo "sudo fuser -k 4567/tcp 2>/dev/null || true"
echo "./rubymc restart"
