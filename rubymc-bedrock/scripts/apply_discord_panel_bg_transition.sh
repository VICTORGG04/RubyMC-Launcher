#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/.."

echo "[RubyMC] Aplicando painel Discord + transição de fundos..."

mkdir -p web/assets/css web/assets/js docs

if [ -f web/index.html ]; then
  cp web/index.html "web/index.html.bak.discord-panel-bg-$(date +%Y%m%d%H%M%S)"
fi

cp -f rubymc_discord_panel_bg_transition_patch/web/index.html web/index.html
cp -f rubymc_discord_panel_bg_transition_patch/web/assets/css/rubymc-discord-panel.css web/assets/css/rubymc-discord-panel.css
cp -f rubymc_discord_panel_bg_transition_patch/web/assets/js/rubymc-ui-polish.js web/assets/js/rubymc-ui-polish.js
cp -f rubymc_discord_panel_bg_transition_patch/docs/RUBYMC_DISCORD_PANEL_BG_TRANSITION.md docs/RUBYMC_DISCORD_PANEL_BG_TRANSITION.md

echo "[OK] Aplicado."
echo "Reinicie: ./rubymc restart"
