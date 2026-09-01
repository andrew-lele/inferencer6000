let
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.unflake = {
    url = "git+https://codeberg.org/goldstein/unflake";
    flake = true;
  };
  inputs.llm-agents.url = "git+https://github.com/numtide/llm-agents.nix";
  inputs.pi.url = "git+https://github.com/lukasl-dev/pi.nix";

  _unflake.dedupRules = [ ];
in
inputs
