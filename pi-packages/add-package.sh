#!/usr/bin/env bash
# Scaffold a new pi package under pi-packages/.
#
# Usage:
#   ./add-package.sh <npm-name>@<version> [--pname X] [--desc "..."] [--homepage URL]
#
# Examples:
#   ./add-package.sh pi-foo@1.2.3
#   ./add-package.sh @someone/bar@0.1.0 --desc "Does a thing" --homepage https://pi.dev/packages/@someone/bar
#
# What it does:
#   1. prefetches the npm tarball and records its SRI hash
#   2. inspects package.json to pick simple-copy vs buildNpmPackage
#   3. for dependency-bearing packages, generates and prunes a package-lock.json
#   4. writes pi-packages/<pname>.nix
#   5. prints the snippets to paste into default.nix and pi-shell.nix
#
# For dependency-bearing packages npmDepsHash is left as a placeholder; run the
# printed build command once and paste the "got:" hash back into the .nix file.
set -euo pipefail
export NIX_CONFIG="experimental-features = nix-command flakes"

cd "$(dirname "$0")"

pname=""; desc=""; homepage_flag=""; positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pname)    pname="${2:?}"; shift 2 ;;
    --desc)     desc="${2:?}"; shift 2 ;;
    --homepage) homepage_flag="${2:?}"; shift 2 ;;
    -h|--help)  sed -n '2,/^$/p' "$0"; exit 0 ;;
    -*)         { echo "unknown option: $1" >&2; exit 1; } ;;
    *)          positional+=("$1"); shift ;;
  esac
done
spec="${positional[0]:-}"
[[ -n "$spec" && "$spec" == *@* ]] || { echo "usage: $0 <npm-name>@<version> [--pname X] [--desc '...'] [--homepage URL]" >&2; exit 1; }

npmName="${spec%@*}"
version="${spec##*@}"
[[ -z "$pname" ]] && { pname="${npmName#@}"; pname="${pname//\//-}"; }
base="${npmName##*/}"
url="https://registry.npmjs.org/${npmName}/-/${base}-${version}.tgz"

echo "==> adding $npmName@$version (pname: $pname)"

out=$(nix-shell -p nodejs --run "node _scaffold.mjs '$spec' '$pname'")
hash=$(printf '%s\n' "$out" | sed -n 's/^HASH=//p')
pj_homepage=$(printf '%s\n' "$out" | sed -n 's/^HOMEPAGE=//p')
has_deps=$(printf '%s\n' "$out" | sed -n 's/^HAS_DEPS=//p')
printf '%s\n' "$out" | sed -n 's/^RUNTIME=/  runtime deps: /p'

[[ -n "$hash" ]] || { echo "error: prefetch failed for $url" >&2; exit 1; }
echo "  tarball hash: $hash"

final_homepage="${homepage_flag:-$pj_homepage}"
final_homepage="${final_homepage:-https://www.npmjs.com/package/$npmName}"
final_desc="${desc:-$pname}"

{
  echo "{ pkgs }:"
  echo "(import ./mk.nix { inherit pkgs; }) {"
  echo "  pname = \"$pname\";"
  [[ "$npmName" != "$pname" ]] && echo "  npmName = \"$npmName\";"
  echo "  version = \"$version\";"
  echo "  hash = \"$hash\";"
  if [[ "$has_deps" == "true" ]]; then
    echo "  lock = ./$pname-lock.json;"
    echo "  # npmDepsHash = \"sha256-...\"; # fill in after first build (see below)"
  fi
  echo "  description = \"$final_desc\";"
  echo "  homepage = \"$final_homepage\";"
  echo "}"
} > "$pname.nix"

echo "  wrote pi-packages/$pname.nix"
echo
echo "Next steps:"
echo "  1. pi-packages/default.nix:"
echo "       $pname = import ./$pname.nix { inherit pkgs; };"
echo "       (add '$pname' to the inherit list)"
echo "  2. pi-shell.nix extensions:"
echo "       \"\${pi-packages.$pname}\""
if [[ "$has_deps" == "true" ]]; then
  echo "  3. discover npmDepsHash, then paste it into pi-packages/$pname.nix:"
  echo "       nix-build ../pi-shell.nix -A pi --no-out-link 2>&1 | grep got:"
fi
