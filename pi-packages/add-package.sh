#!/usr/bin/env bash
# Scaffold or bump a vendored pi package under pi-packages/.
#
# Usage:
#   ./add-package.sh <npm-name>@<version> [--pname X] [--desc "..."] [--homepage URL]
#
# Examples:
#   ./add-package.sh pi-foo@1.2.3
#   ./add-package.sh pi-lens@4.2.0                # bump an existing package
#   ./add-package.sh @someone/bar@0.1.0 --desc "Does a thing"
#
# Re-running this for an existing pname is the supported BUMP path: the recorded
# npmDepsHash attrset is preserved, so the next build fails with a hash mismatch
# that prints the value to paste back (see step 3 below).
#
# What it does:
#   1. prefetches the npm tarball and records its SRI hash
#   2. inspects package.json for runtime deps, license, description, homepage
#   3. for dependency-bearing packages, generates and prunes package-lock.json
#   4. writes pi-packages/<pname>.nix
#   5. prints the snippets to paste into default.nix and pi-shell.nix
#
# Lock generation runs under the flake's pinned node (`.#nodejs`) because
# npmDepsHash is a function of the npm version, not just the lockfile.
set -euo pipefail
export NIX_CONFIG="experimental-features = nix-command flakes"

cd "$(dirname "$0")"
repo_root="$(cd .. && pwd)"

pname=""
desc=""
homepage_flag=""
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --pname)
    pname="${2:?}"
    shift 2
    ;;
  --desc)
    desc="${2:?}"
    shift 2
    ;;
  --homepage)
    homepage_flag="${2:?}"
    shift 2
    ;;
  -h | --help)
    sed -n '2,/^$/p' "$0"
    exit 0
    ;;
  -*) {
    echo "unknown option: $1" >&2
    exit 1
  } ;;
  *)
    positional+=("$1")
    shift
    ;;
  esac
done
spec="${positional[0]:-}"
[[ -n "$spec" && "$spec" == *@* ]] || {
  echo "usage: $0 <npm-name>@<version> [--pname X] [--desc '...'] [--homepage URL]" >&2
  exit 1
}

npmName="${spec%@*}"
version="${spec##*@}"
[[ -z "$pname" ]] && {
  pname="${npmName#@}"
  pname="${pname//\//-}"
}
base="${npmName##*/}"
url="https://registry.npmjs.org/${npmName}/-/${base}-${version}.tgz"

echo "==> adding $npmName@$version (pname: $pname)"

# Prefer the flake's pinned node so the generated lock matches the npm version
# that will consume it; fall back to an ambient node for a flake-less checkout.
if [[ -f "$repo_root/flake.lock" ]]; then
  node_cmd=(nix shell "$repo_root#nodejs" --command node)
else
  echo "  warning: no flake.lock; falling back to nix-shell -p nodejs (npm version unpinned)" >&2
  node_cmd=(nix-shell -p nodejs --run node)
fi

out=$("${node_cmd[@]}" _scaffold.mjs "$spec" "$pname")
hash=$(printf '%s\n' "$out" | sed -n 's/^HASH=//p')
pj_homepage=$(printf '%s\n' "$out" | sed -n 's/^HOMEPAGE=//p')
pj_desc=$(printf '%s\n' "$out" | sed -n 's/^DESC=//p')
pj_license=$(printf '%s\n' "$out" | sed -n 's/^LICENSE=//p')
spdx=$(printf '%s\n' "$out" | sed -n 's/^SPDX=//p')
reused_lock=$(printf '%s\n' "$out" | sed -n 's/^REUSED_LOCK=//p')
has_deps=$(printf '%s\n' "$out" | sed -n 's/^HAS_DEPS=//p')
printf '%s\n' "$out" | sed -n 's/^RUNTIME=/  runtime deps: /p'

[[ -n "$hash" ]] || {
  echo "error: prefetch failed for $url" >&2
  exit 1
}
echo "  tarball hash: $hash"
[[ "$reused_lock" == "1" ]] && echo "  kept existing lockfile (same version; no range floating)"

# Preserve an existing npmDepsHash block so a version bump keeps the workflow
# "bump version -> build -> paste the 'got:' hash". Also keep hand-curated
# description/homepage/license: upstream metadata is often worse than what we
# wrote here, so a bump must not silently regress it.
existing_deps_hash=""
existing_desc=""
existing_homepage=""
existing_license=""
is_bump=0
if [[ -f "$pname.nix" ]]; then
  is_bump=1
  # Keep the hashes but not the surrounding comments: those are regenerated below
  # so their wording stays in sync with this script.
  # `|| true`: grep exits 1 when nothing matches, which pipefail would turn into
  # a fatal error for packages that have no npmDepsHash at all.
  existing_deps_hash=$(sed -n '/^  npmDepsHash = {$/,/^  };$/p' "$pname.nix" | grep -v '^  *#' || true)
  if [[ -z "$existing_deps_hash" ]]; then
    existing_deps_hash=$(sed -n 's/^\(  npmDepsHash = .*\)$/\1/p' "$pname.nix" | grep -v '^  *#' || true)
  fi
  existing_desc=$(sed -n 's/^  description = "\(.*\)";$/\1/p' "$pname.nix")
  existing_homepage=$(sed -n 's/^  homepage = "\(.*\)";$/\1/p' "$pname.nix")
  existing_license=$(sed -n 's/^  license = \(.*\);.*$/\1/p' "$pname.nix")
  [[ -n "$existing_deps_hash" ]] && echo "  preserving existing npmDepsHash (expect a mismatch on next build)"
fi

final_homepage="${homepage_flag:-$existing_homepage}"
final_homepage="${final_homepage:-$pj_homepage}"
final_homepage="${final_homepage:-https://www.npmjs.com/package/$npmName}"
final_desc="${desc:-$existing_desc}"
final_desc="${final_desc:-$pj_desc}"
final_desc="${final_desc:-$pname}"

{
  echo "{ pkgs }:"
  echo "(import ./mk.nix { inherit pkgs; }) {"
  echo "  pname = \"$pname\";"
  [[ "$npmName" != "$pname" ]] && echo "  npmName = \"$npmName\";"
  echo "  version = \"$version\";"
  echo "  hash = \"$hash\";"
  if [[ "$has_deps" == "true" ]]; then
    echo "  lock = ./$pname-lock.json;"
    echo "  # Per system: covers the lockfile + npm version + platform prebuilds."
    echo "  # Reveal with:  nix build .#${pname} -L 2>&1 | grep 'got:'"
    if [[ -n "$existing_deps_hash" ]]; then
      printf '%s\n' "$existing_deps_hash"
    else
      echo "  npmDepsHash = { };"
    fi
  fi
  echo "  description = \"$final_desc\";"
  echo "  homepage = \"$final_homepage\";"
  if [[ -n "$existing_license" ]]; then
    echo "  license = $existing_license; # $spdx"
  elif [[ -n "$pj_license" ]]; then
    echo "  license = pkgs.lib.licenses.$pj_license; # $spdx"
  else
    echo "  # license: upstream declares '$spdx' — set it explicitly (mk.nix defaults to MIT)."
  fi
  echo "}"
} >"$pname.nix"

echo "  wrote pi-packages/$pname.nix"
if [[ "$is_bump" == "1" ]]; then
  if [[ "$has_deps" == "true" ]]; then
    echo "  reveal the new npmDepsHash:  nix build .#$pname -L 2>&1 | grep 'got:'"
  fi
  exit 0
fi

echo
echo "Next steps:"
echo "  1. pi-packages/default.nix:"
echo "       $pname = import ./$pname.nix { inherit pkgs; };"
echo "       (add '$pname' to the packages attrset)"
echo "  2. pi-shell.nix extensions:"
echo "       \"\${pi-packages.$pname}\""
if [[ "$has_deps" == "true" ]]; then
  echo "  3. reveal the npmDepsHash for THIS platform, then paste it into"
  echo "     pi-packages/$pname.nix under the matching system key:"
  echo "       nix build .#$pname -L 2>&1 | grep 'got:'"
  echo "     (no flakes: nix-build ./pi-shell.nix -A pi-packages.$pname 2>&1 | grep 'got:')"
  echo "  4. verify: nix build .#all && nix flake check"
else
  echo "  3. verify: nix build .#all && nix flake check"
fi
