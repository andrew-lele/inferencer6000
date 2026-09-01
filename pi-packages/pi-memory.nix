{ pkgs }:
(import ./mk.nix { inherit pkgs; }) {
  pname = "pi-memory";
  version = "0.4.2";
  hash = "sha256-rEgmpLFrt16BhxqkzKzLdwH9CcvX7Wv3ha2ZvTymDj8=";
  description = "pi-memory";
  homepage = "https://github.com/jayzeng/pi-memory#readme";
}
