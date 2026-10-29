#!/usr/bin/env bash
# Register GC roots for everything this repo's nix-shell depends on at EVAL
# time (the unflake source trees) and for the shell derivation + its direct
# outputs. Without this, `nix-collect-garbage` deletes the ~670MB of source
# checkouts (forcing multi-minute re-fetches) and the built tools (forcing
# multi-hour darwin rebuilds).
#
# Run after `./update-deps.sh` (new revs = new source trees) or any time you
# want to re-assert the roots. Idempotent.
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

ROOT_DIR="${HOME}/.nix/gcroots/inferencer6000"
rm -rf "$ROOT_DIR"
mkdir -p "$ROOT_DIR"

root_path() {
  local p="$1"
  [ -n "$p" ] || return 0
  # nix 2.24 requires an explicit operation alongside --add-root; --realise is
  # a no-op for paths that already exist, and it registers the symlink as a
  # permanent root (daemon-side, under /nix/var/nix/gcroots/auto). A bare
  # `ln -s` is NOT enough — that registered set is what the collector walks.
  nix-store --realise --add-root "$ROOT_DIR/$(basename "$p")" "$p" >/dev/null
}

# 1) The 13 unflake source trees (fetchTree results — eval-only, otherwise dead).
while read -r p; do
  root_path "$p"
done < <(
  nix-instantiate --eval --strict --expr \
    'let u = import ./unflake.nix; ds = u._unflake.deps;
     in builtins.toString (builtins.concatMap (n: [ds."${n}".outPath]) (builtins.attrNames ds))' |
    tr ' []\",' '\n' | grep -v '^$'
)

# 2) The shell derivation itself.
DRV="$(nix-instantiate shell.nix)"
root_path "$DRV"

# 3) Its direct output paths (the delta packages not covered by ~/dev-env base).
while read -r ref; do
  case "$ref" in
  *.drv) nix-store -q --outputs "$ref" 2>/dev/null | while read -r o; do root_path "$o"; done ;;
  esac
done < <(nix-store -q --references "$DRV")

echo "rooted $(ls "$ROOT_DIR" | wc -l | tr -d ' ') paths under $ROOT_DIR"
# Verify: every rooted path should now report at least one root.
missing=0
for l in "$ROOT_DIR"/*; do
  p="$(readlink "$l")"
  [ -n "$(nix-store --query --roots "$p")" ] || {
    echo "NOT ROOTED: $p" >&2
    missing=$((missing + 1))
  }
done
[ "$missing" -eq 0 ] && echo "all roots verified" || exit 1
