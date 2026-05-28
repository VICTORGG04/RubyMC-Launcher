#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/.."

cp -f rubymc_complete_readme_pack/README.md README.md

mkdir -p docs/assets/bedrock
cp -f rubymc_complete_readme_pack/docs/assets/bedrock/*.png docs/assets/bedrock/

echo "[OK] README principal completo atualizado."
