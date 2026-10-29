#!/usr/bin/env bash
# nix-update entrypoint: bump one pi package to a new npm version.
#
#   nix run nixpkgs#nix-update -- --flake pi-lens --version 4.4.7
#
# nix-update supplies UPDATE_NIX_ATTR_PATH and UPDATE_NIX_NEW_VERSION in the
# environment; --version is required because npm has no release feed to
# discover. Regenerates <pname>.nix + lock, then refreshes npmDepsHash for this
# system. Leaves the change uncommitted.
set -euo pipefail
export NIX_CONFIG="experimental-features = nix-command flakes"

attr="${UPDATE_NIX_ATTR_PATH:-}"
version="${UPDATE_NIX_NEW_VERSION:-}"
[[ -n "$attr" && -n "$version" ]] || {
  echo "error: run this through nix-update (UPDATE_NIX_ATTR_PATH / UPDATE_NIX_NEW_VERSION are unset)" >&2
  exit 1
}
pname="${attr##*/}"

repo_root="$(git -C "${PWD:-.}" rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$repo_root" ]] || repo_root="${PWD:-.}"
[[ -f "$repo_root/pi-packages/$pname.nix" ]] || {
  echo "error: pi-packages/$pname.nix not found under $repo_root" >&2
  exit 1
}
cd "$repo_root/pi-packages"

npmName="$(sed -n 's/^  npmName = "\(.*\)";$/\1/p' "$pname.nix")"
npmName="${npmName:-$pname}"

./add-package.sh "$npmName@$version" --pname "$pname"

# Back to the flake root: pi-packages/ itself is not a flake.
cd "$repo_root"
system="$(nix eval --impure --raw --expr builtins.currentSystem)"

# The preserved npmDepsHash is stale for a changed lock, so this build either
# succeeds (hash still valid) or fails and prints the replacement.
set +e
log="$(nix build ".#$pname" --no-link -L 2>&1)"
status=$?
set -e

if [[ $status -eq 0 ]]; then
  echo "==> npmDepsHash unchanged; $pname-$version builds"
  exit 0
fi

new_hash="$(printf '%s\n' "$log" | sed -n 's/.*got: *\(sha256-[A-Za-z0-9+/=]*\).*/\1/p' | head -n1)"
if [[ -z "$new_hash" ]]; then
  printf '%s\n' "$log" | tail -n 20 >&2
  echo "error: build failed without a hash mismatch; see above" >&2
  exit 1
fi
echo "  new npmDepsHash for $system: $new_hash"

# awk rather than sed -i so this works on both GNU and BSD sed.
awk -v sys="$system" -v sri="$new_hash" '
  /^  npmDepsHash = \{$/ { inblock = 1 }
  inblock && index($0, "    " sys " = ") == 1 {
    print "    " sys " = \"" sri "\";"
    inblock = 0; done = 1; next
  }
  inblock && $0 == "  };" {
    if (!done) print "    " sys " = \"" sri "\";"
    inblock = 0; done = 1
  }
  /^  npmDepsHash = \{ \};$/ {
    printf "  npmDepsHash = {\n    %s = \"%s\";\n  };\n", sys, sri
    done = 1; next
  }
  /^  npmDepsHash = "sha256-/ {
    printf "  npmDepsHash = {\n    %s = \"%s\";\n  };\n", sys, sri
    done = 1; next
  }
  { print }
' "pi-packages/$pname.nix" >"pi-packages/$pname.nix.tmp"
mv "pi-packages/$pname.nix.tmp" "pi-packages/$pname.nix"

nix build ".#$pname" --no-link -L
echo "==> $pname bumped to $version; review the diff before committing"
