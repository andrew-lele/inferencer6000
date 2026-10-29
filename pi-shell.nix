let
  inputs = import ./unflake.nix (inputs: inputs);
  system = builtins.currentSystem;
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    # radicle-node is flagged insecure upstream: "private repositories are
    # insecure: traffic between nodes is not encrypted and not authenticated".
    # Accepted deliberately — this node replicates only mac <-> ahsan over Tor
    # with private ids and is not federated with the public Radicle network.
    config.allowInsecurePredicate = p: (p.pname or "") == "radicle-node";
  };

  # Pi binary from numtide/llm-agents.nix (raw; wrapped by `pi` below).
  piBase = inputs.llm-agents.packages.${system}.pi;

  # Pi packages built from pinned npm tarballs (no runtime npm installs).
  pi-packages = import ./pi-packages { inherit pkgs; };

  # Configured pi wrapper from lukasl-dev/pi.nix (rules, extensions, skills, themes).
  configured = inputs.pi.lib.mkCodingAgent {
    inherit pkgs;
    modules = [
      {
        pi.coding-agent = {
          package = piBase;
          rules = ./AGENTS.md;
          skills = [
            # ./skills/<name>
          ];
          settings = {
            theme = "gruvbox-dark-soft";
          };
          extensions = [
            ./extensions/unsloth.ts
            ./extensions/hide-providers.ts
            # Vendored from rtk-ai/rtk — rewrites bash tool calls for token savings.
            ./extensions/rtk.ts
            "${pi-packages.pi-lens}"
            "${pi-packages.pi-memory}"
            "${pi-packages.pi-powerline-footer}"
            "${pi-packages.pi-subagents}"
            "${pi-packages.pi-web-access}"
            "${pi-packages.rpiv-ask-user-question}"
            "${pi-packages.robhowley-pi-openrouter}"
          ];
          themes = [
            ./themes/gruvbox-dark-soft.json
          ];
        };
      }
    ];
  };

  # pi wrapped in secretspec run: the profile's keys are injected into pi's
  # environment at launch, so they never touch the nix-shell (or any .drv —
  # a mkShell `env` attrset would stamp them into the store). Key material
  # exists only in pi's process tree (and the children it spawns).
  # NOTE: secretspec run fails hard if a declared secret is unset — pi then
  # names the key; fix with `secretspec set <name>`. The parent env is passed
  # through untouched, so user-set PI_* / provider overrides still apply.
  pi = pkgs.writeShellScriptBin "pi" ''
    exec ${pkgs.secretspec}/bin/secretspec run -f ${./secretspec.toml} -- ${configured.package}/bin/pi "$@"
  '';
in
{
  inherit pkgs;
  inherit pi;
  # Exposed so a single vendored package can be built without flakes:
  #   nix-build ./pi-shell.nix -A pi-packages.pi-lens
  inherit pi-packages;
}
