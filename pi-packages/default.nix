# Every pi extension this repo vendors, built from pinned npm tarballs.
#
#   nix-build ./pi-packages/pi-lens.nix   # or nix build .#pi-lens
#   nix-build -A pi-lens ./pi-packages    # or nix build .#all
#
# Add a package with ./add-package.sh (see README.md).
{ pkgs }:
let
  lib = pkgs.lib;

  packages = {
    pi-lens = import ./pi-lens.nix { inherit pkgs; };
    pi-memory = import ./pi-memory.nix { inherit pkgs; };
    pi-powerline-footer = import ./pi-powerline-footer.nix { inherit pkgs; };
    pi-subagents = import ./pi-subagents.nix { inherit pkgs; };
    pi-web-access = import ./pi-web-access.nix { inherit pkgs; };
    remnic-plugin-pi = import ./remnic-plugin-pi.nix { inherit pkgs; };
    robhowley-pi-openrouter = import ./robhowley-pi-openrouter.nix { inherit pkgs; };
    rpiv-ask-user-question = import ./rpiv-ask-user-question.nix { inherit pkgs; };
  };

  names = builtins.attrNames packages;
in
packages
// {
  # One store path with a symlink per package, so `nix build .#all` (CI) cannot
  # pass while a single package is broken.
  all = pkgs.linkFarm "pi-packages" (
    map (name: {
      inherit name;
      path = packages.${name};
    }) names
  );

  # Flattened passthru.tests; they run against the built outputs (see mk.nix).
  checks = lib.concatMapAttrs (name: pkg: { "smoke-${name}" = pkg.passthru.tests.smoke; }) packages;
}
