{ pkgs }:
(import ./mk.nix { inherit pkgs; }) {
  pname = "robhowley-pi-openrouter";
  npmName = "@robhowley/pi-openrouter";
  version = "0.14.0";
  hash = "sha256-m15ww6iN0RXDEMaL0vV8CoSnWOZuKrPSMmEcqLDCPOY=";
  lock = ./robhowley-pi-openrouter-lock.json;
  # npmDepsHash = "sha256-..."; # fill in after first build (see below)
  description = "OpenRouter usage/account TUI overlays, session tagging, model catalog sync, API key mgmt";
  homepage = "https://pi.dev/packages/@robhowley/pi-openrouter";
}
