# The project dev shell — enter with bare `nix-shell` in this directory.
#
# Generic tools live here; the pi-specific layer (agent package wrapped in
# secretspec run for key injection) comes from ./pi-shell.nix.
let
  piShell = import ./pi-shell.nix;
in
piShell.pkgs.mkShellNoCC {
  # Base tools (git ripgrep jq gnupg jujutsu fd shellcheck rust-analyzer)
  # come from the machine-wide dev-base profile (~/dev-env/base.nix,
  # installed into ~/.nix-profile — see ~/dev-env/install.sh). They are
  # ambient on PATH; declare one here only if this repo needs a DIFFERENT
  # version than the base.
  buildInputs = with piShell.pkgs; [
    # Radicle 1.x node + CLI (`radicle-node`, `rad`, `git-remote-rad`).
    # Having it on PATH is what makes `jj git push` work against the `rad`
    # remote: jj's built-in git backend hands rad:// URLs to plain git, which
    # then needs the git-remote-rad helper — without it you get
    # "git: 'remote-rad' is not a git command" / "remote helper 'rad' aborted".
    # Marked insecure upstream; see pi-shell.nix for why we deliberately allow it.
    radicle-node
    rtk
    secretspec
    piShell.pi
    # pi-lens language tooling — LSP servers + linters. pi-lens prefers PATH
    # binaries over its managed GitHub downloads, so the nix-provided copies win.
    nixd # nix LSP (PATH-only in pi-lens; it has no managed installer)
    marksman # markdown LSP
    terraform-ls # terraform/opentofu LSP (pi-lens built-in candidate for .tf)
    tofu-ls # OpenTofu LSP (opt-in per project via .pi-lens.json custom server)
    tflint # terraform/opentofu linter
    taplo # toml linter/formatter
    markdownlint-cli2 # markdown linter
  ];
}
