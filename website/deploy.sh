#!/bin/zsh
# Deploys agentbol.com (public/ as an assets-only Worker).
# Usage: website/deploy.sh ["message"]
# First stamps every page's links to styles.css and main.js with a hash of their contents, so a change
# gets a new URL: browsers can cache those files for a year and never pair fresh HTML with stale CSS or JS.
set -euo pipefail
cd "$(dirname "$0")/public"
for FILE in styles.css main.js; do
  HASH="$(shasum -a 256 "$FILE" | cut -c1-10)"
  for PAGE in *.html; do
    sed -i '' -E "s#(href|src)=\"(/?)${FILE//./\\.}(\\?v=[0-9a-f]+)?\"#\\1=\"\\2${FILE}?v=${HASH}\"#g" "$PAGE"
  done
done
cd ..
cf deploy ./public --message "${1:-Deploy}"
