{ pkgs }:
(import ./mk.nix { inherit pkgs; }) {
  pname = "remnic-plugin-pi";
  npmName = "@remnic/plugin-pi";
  version = "9.69.33";
  hash = "sha256-YmZgGbSGakgBAARACReM526nEO80VkyN/sUIAdu+Ajg=";
  lock = ./remnic-plugin-pi-lock.json;
  npmDepsHash = "sha256-9eOKt2j4lujqCiX8i5duZxqB+PjOyvwBf8IshJbsANQ=";
  description = "Remnic's plugin pack for pi";
  homepage = "https://pi.dev/packages/@remnic/plugin-pi";
}
