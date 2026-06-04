#!/usr/bin/env bash
set -e

ROOT="$(pwd)"
SOURCE_DIR="rubymc_frontend_restructure_pack"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "[ERRO] Pasta $SOURCE_DIR não encontrada."
  echo "Execute este script a partir da raiz onde o pacote foi extraído."
  exit 1
fi

# Detecta destino:
# 1) rubymc-bedrock/web se existir;
# 2) web na raiz atual;
# 3) rubymc-java/web se existir.
if [ -d "$ROOT/rubymc-bedrock/web" ]; then
  TARGET="$ROOT/rubymc-bedrock"
elif [ -d "$ROOT/web" ]; then
  TARGET="$ROOT"
elif [ -d "$ROOT/rubymc-java/web" ]; then
  TARGET="$ROOT/rubymc-java"
else
  echo "[ERRO] Não encontrei pasta web para aplicar."
  exit 1
fi

echo "[RubyMC] Aplicando reestruturação frontend em: $TARGET"

mkdir -p "$TARGET/web/assets/css" "$TARGET/web/assets/js" "$TARGET/docs"

BACKUP_DIR="$TARGET/.backup_frontend_restructure_$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"

for file in \
  "web/index.html" \
  "web/termos.html" \
  "web/assets/css/launcher.css" \
  "web/assets/css/bedrock-download-fix.css" \
  "web/assets/css/server-java-page.css" \
  "web/assets/js/utils.js" \
  "web/assets/js/launcher.js" \
  "web/assets/js/server-runtime-selector.js" \
  "web/assets/js/rubymc-ai-support.js"
do
  if [ -f "$TARGET/$file" ]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp "$TARGET/$file" "$BACKUP_DIR/$file"
  fi
done

cp -f "$SOURCE_DIR/web/index.html" "$TARGET/web/index.html"
cp -f "$SOURCE_DIR/web/termos.html" "$TARGET/web/termos.html"
cp -f "$SOURCE_DIR/web/assets/css/launcher.css" "$TARGET/web/assets/css/launcher.css"
cp -f "$SOURCE_DIR/web/assets/css/bedrock-download-fix.css" "$TARGET/web/assets/css/bedrock-download-fix.css"
cp -f "$SOURCE_DIR/web/assets/css/server-java-page.css" "$TARGET/web/assets/css/server-java-page.css"
cp -f "$SOURCE_DIR/web/assets/js/utils.js" "$TARGET/web/assets/js/utils.js"
cp -f "$SOURCE_DIR/web/assets/js/launcher.js" "$TARGET/web/assets/js/launcher.js"
cp -f "$SOURCE_DIR/web/assets/js/server-runtime-selector.js" "$TARGET/web/assets/js/server-runtime-selector.js"
cp -f "$SOURCE_DIR/web/assets/js/rubymc-ai-support.js" "$TARGET/web/assets/js/rubymc-ai-support.js"

cp -f "$SOURCE_DIR/docs/FRONTEND_RESTRUCTURE.md" "$TARGET/docs/FRONTEND_RESTRUCTURE.md"

echo "[OK] Frontend reestruturado."
echo "[OK] Backup criado em: $BACKUP_DIR"
echo
echo "Reinicie o painel:"
echo "cd \"$TARGET\""
echo "./rubymc restart"
echo
echo "Se o navegador mantiver cache, abra:"
echo "http://127.0.0.1:4567/?v=rubymc-layout-restructure-1"
