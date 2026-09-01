let
  inputs = import ./unflake.nix (inputs: inputs);
  system = builtins.currentSystem;
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };

  # Pi binary from numtide/llm-agents.nix.
  pi = inputs.llm-agents.packages.${system}.pi;

  # Pi packages built from pinned npm tarballs (no runtime npm installs).
  pi-packages = import ./pi-packages { inherit pkgs; };

  # Configured pi wrapper from lukasl-dev/pi.nix (rules, extensions, skills, themes).
  configured = inputs.pi.lib.mkCodingAgent {
    inherit pkgs;
    modules = [
      {
        pi.coding-agent = {
          package = pi;
          rules = ./AGENTS.md;
          skills = [
            # ./skills/<name>
          ];
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
          ];
          themes = [
            # ./themes/<name>.json
          ];
        };
      }
    ];
  };

  # API keys sourced from the secretspec keyring into the shell (and thus pi).
  # Add a name here and declare it in ./secretspec.toml to wire up a new key.
  apiKeys = [
    "UNSLOTH_API_KEY"
    "DEEPSEEK_API_KEY"
    "KAGI_API_KEY"
  ];

  # Emit shell that loads each key from the keyring (falling back to an
  # already-exported env var) so pi sees it without a manual export.
  keyHook = pkgs.lib.concatMapStringsSep "\n" (name: ''
    _key="$(secretspec get -f "${./secretspec.toml}" ${name} 2>/dev/null || true)"
    if [ -n "$_key" ]; then
      export ${name}="$_key"
    fi
    if [ -n "''${${name}:-}" ]; then
      echo "  ${name}: loaded from keyring"
    else
      echo "  ${name}: not set (run: secretspec set ${name})"
    fi
  '') apiKeys;

  # Shell hook, consumed by ./shell.nix — load keys from the keyring.
  shellHook = ''
    echo "Loading API keys from secretspec keyring:"
  ''
  + keyHook
  + ''
    if [ -n "''${UNSLOTH_API_KEY:-}" ]; then
      echo "Unsloth backend enabled (pi -> http://localhost:8888/v1)"
    fi
  '';
in
{
  inherit pkgs;
  pi = configured.package;
  inherit shellHook;
}
