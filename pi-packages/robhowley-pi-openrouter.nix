{ pkgs }:
(import ./mk.nix { inherit pkgs; }) {
  pname = "robhowley-pi-openrouter";
  npmName = "@robhowley/pi-openrouter";
  version = "0.14.4";
  hash = "sha256-cJeTcPdep2RX9u/6/gJHtWrmTRxxOBahABsOeZesQZM=";
  lock = ./robhowley-pi-openrouter-lock.json;
  # Per system: covers the lockfile + npm version + platform prebuilds.
  npmDepsHash = {
    aarch64-darwin = "sha256-jpXVJRc6cfKnkSyWWqC6ZK2MHNsaAprtgOp9PEE+1fw=";
  };
  description = "Live OpenRouter spend/account TUI overlays, user-scoped or free-only model sync, api key management, and session tagging for Pi.";
  homepage = "https://pi.dev/packages/@robhowley/pi-openrouter";
}
