{ pkgs }:
(import ./mk.nix { inherit pkgs; }) {
  pname = "pi-web-access";
  version = "0.24.2";
  hash = "sha256-427QvHi2MxaDsqyiy/N0ixw+j7FcLgHDaUrcnpEiBRg=";
  lock = ./pi-web-access-lock.json;
  # Per system: covers the lockfile + npm version + platform prebuilds.
  npmDepsHash = {
    aarch64-darwin = "sha256-qttRbOF7mLwiNDr8kbP/TF7D3LxfjhrkMIJgKnLQWZg=";
  };
  description = "Web access tools for pi — search, browse, extract content";
  homepage = "https://github.com/nicobailon/pi-web-access";
}
