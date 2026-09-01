# The project dev shell — enter with bare `nix-shell` in this directory.
#
# Generic tools live here; the pi-specific layer (configured agent package +
# shell hook) comes from ./pi-shell.nix.
let
  piShell = import ./pi-shell.nix;
in
piShell.pkgs.mkShellNoCC {
  buildInputs = with piShell.pkgs; [
    git
    ripgrep
    jq
    jujutsu
    radicle-node
    rtk
    secretspec
    gnupg # gpg, for jj commit signing
    piShell.pi
    # pi-lens language tooling — LSP servers + linters. pi-lens prefers PATH
    # binaries over its managed GitHub downloads, so the nix-provided copies win.
    nixd # nix LSP (PATH-only in pi-lens; it has no managed installer)
    marksman # markdown LSP
    rust-analyzer # rust LSP (clippy pedantic comes from [lints] in Cargo.toml)
    terraform-ls # terraform/opentofu LSP (pi-lens built-in candidate for .tf)
    tofu-ls # OpenTofu LSP (opt-in per project via .pi-lens.json custom server)
    tflint # terraform/opentofu linter
    taplo # toml linter/formatter
    shellcheck # shell linter
    markdownlint-cli2 # markdown linter
  ];

  shellHook = piShell.shellHook;
}
