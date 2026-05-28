#!/usr/bin/env bash
set -e

cd "$(dirname "$0")/.."

cp -f rubymc_readme_docs_pack/README.md README.md

mkdir -p docs/java docs/bedrock docs/assets/bedrock

cp -f rubymc_readme_docs_pack/docs/java/JAVA_MODEL.md docs/java/
cp -f rubymc_readme_docs_pack/docs/bedrock/BEDROCK_MODEL.md docs/bedrock/
cp -f rubymc_readme_docs_pack/docs/assets/bedrock/*.png docs/assets/bedrock/

echo "[OK] Documentações e screenshots atualizadas."
