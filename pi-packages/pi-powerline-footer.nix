{ pkgs }:
(import ./mk.nix { inherit pkgs; }) {
  pname = "pi-powerline-footer";
  version = "0.15.1";
  hash = "sha256-MSUebq+xrRv0d5o+7ST0yil0JbW3hX7EfgiWYerXCks=";
  description = "Powerline footer for pi's TUI";
  homepage = "https://github.com/niceguyisme/pi-powerline-footer";
}
