{ pkgs }:
(import ./mk.nix { inherit pkgs; }) {
  pname = "pi-subagents";
  version = "0.56.0";
  hash = "sha256-e2T5KfSeO2l2V9QRFtZXDRHwFZF7HfGGnP7xDSyeE9o=";
  lock = ./pi-subagents-lock.json;
  # Per system: covers the lockfile + npm version + platform prebuilds.
  npmDepsHash = {
    aarch64-darwin = "sha256-WMZjI0Jp7v4VrrH5D0GWKFWdLMZuQleJRP136WMtpd4=";
  };
  description = "Delegate tasks to subagents with chains, parallel execution, and TUI clarification";
  homepage = "https://github.com/nicobailon/pi-subagents";
}
