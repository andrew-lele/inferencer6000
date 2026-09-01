{ pkgs }:
let
  pi-lens = import ./pi-lens.nix { inherit pkgs; };
  pi-memory = import ./pi-memory.nix { inherit pkgs; };
  pi-powerline-footer = import ./pi-powerline-footer.nix { inherit pkgs; };
  pi-subagents = import ./pi-subagents.nix { inherit pkgs; };
  pi-web-access = import ./pi-web-access.nix { inherit pkgs; };
  remnic-plugin-pi = import ./remnic-plugin-pi.nix { inherit pkgs; };
  rpiv-ask-user-question = import ./rpiv-ask-user-question.nix { inherit pkgs; };
in
{
  inherit
    pi-lens
    pi-memory
    pi-powerline-footer
    pi-subagents
    pi-web-access
    remnic-plugin-pi
    rpiv-ask-user-question
    ;
}
