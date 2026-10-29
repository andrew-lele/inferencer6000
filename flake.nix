# Thin wrapper: exposes pi-packages as a flake without changing how they are
# built. The non-flake path (shell.nix -> pi-shell.nix -> pi-packages) stays
# primary; both evaluate the same builder against the same nixpkgs rev, so they
# produce identical store paths.
{
  description = "pi extensions packaged from pinned npm tarballs";

  # Must match the rev ./unflake.nix resolves: npmDepsHash depends on the npm
  # version in this nixpkgs, so a different rev invalidates every recorded hash.
  # Bump both together, then re-reveal the hashes (README.md).
  inputs.nixpkgs.url = "github:nixos/nixpkgs/fe13242281a67641c0102cdb1087f0ebe586c7df";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      supportedSystems = [ "aarch64-darwin" ];

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          config.allowInsecurePredicate = p: (p.pname or "") == "radicle-node";
        };

      forSupported = f: lib.genAttrs supportedSystems (system: f (pkgsFor system));

      packagesFor =
        pkgs:
        let
          pp = import ./pi-packages { inherit pkgs; };
        in
        builtins.removeAttrs pp [ "checks" ]
        // {
          default = pp.all;
          # The npm that npmDepsHash is computed against; add-package.sh runs
          # under this so generated lockfiles match the builder.
          nodejs = pkgs.nodejs_22;
        };
    in
    {
      packages = forSupported packagesFor;

      checks = forSupported (
        pkgs:
        let
          pp = import ./pi-packages { inherit pkgs; };
        in
        pp.checks // { all = pp.all; }
      );

      formatter = forSupported (pkgs: pkgs.nixfmt);

      devShells = forSupported (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = [
            pkgs.nodejs_22
            pkgs.jq
            pkgs.nixfmt
          ];
          shellHook = ''
            echo "pi-packages devShell — node $(node --version), npm $(npm --version)"
          '';
        };
      });
    };
}
