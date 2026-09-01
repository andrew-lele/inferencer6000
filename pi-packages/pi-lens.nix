{ pkgs }:
(import ./mk.nix { inherit pkgs; }) {
  pname = "pi-lens";
  version = "4.1.1";
  hash = "sha256-7mjtIuX4g98scAc4NJ0WYEVekGqWSHV98vBia3W7u9A=";
  lock = ./pi-lens-lock.json;
  npmDepsHash = "sha256-miLlxXcMJLP4gPFMQQi8VGG5BZ0JYfGJGq7OiIgdEa4=";
  description = "Real-time code feedback for pi — LSP, linters, formatters, type-checking";
  homepage = "https://github.com/apmantza/pi-lens";
}
