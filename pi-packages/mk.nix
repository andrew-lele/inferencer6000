# Shared builder for pi extensions published to the npm registry.
#
# The npm tarballs are already built, so dependency handling is: take the
# upstream lockfile as the source of truth, fetch it in one fixed-output
# derivation, and let `npm ci` materialise node_modules. No resolver in Nix.
#
#   no `lock`   -> plain copy of the tarball (deps come from pi at runtime)
#   with `lock` -> buildNpmPackage + vendored lock, dontNpmBuild = true
#
# Two hashes: `hash` for the tarball (platform independent) and `npmDepsHash`
# for the dep tree (a function of lockfile + npm version + platform, so it is
# recorded per system). Reveal a stale one with:
#   nix build .#<pname> -L 2>&1 | grep 'got:'
{
  pkgs,
}:
let
  lib = pkgs.lib;
  hostSystem = pkgs.stdenv.hostPlatform.system;

  # Scoped names drop the scope in the tarball filename:
  #   "pi-lens" -> .../pi-lens/-/pi-lens-4.1.1.tgz
  #   "@remnic/plugin-pi" -> .../@remnic/plugin-pi/-/plugin-pi-9.69.33.tgz
  tarballUrl =
    npmName: version:
    "https://registry.npmjs.org/${npmName}/-/${lib.last (lib.splitString "/" npmName)}-${version}.tgz";

  copyPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r . $out/
    runHook postInstall
  '';

  # Peers are supplied by pi at runtime and devDeps only exist to build the
  # tarball we already have, so neither belongs in the closure.
  stripPeers = lock: ''
    cp ${lock} package-lock.json
    ${pkgs.jq}/bin/jq 'del(.peerDependencies, .devDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
  '';

  # A plain string is still accepted for a single-platform package.
  depsHashFor =
    pname: npmDepsHash:
    if builtins.isAttrs npmDepsHash then
      npmDepsHash.${hostSystem} or (throw ''
        ${pname}: no npmDepsHash for ${hostSystem}.
        Add ${hostSystem} to the npmDepsHash attrset in pi-packages/${pname}.nix,
        or leave the package unsupported on this platform.
      '')
    else
      npmDepsHash;
in
{
  pname,
  npmName ? pname,
  version,
  hash,
  lock ? null,
  # String, or an attrset keyed by system.
  npmDepsHash ? { },
  # npm's install layout (and therefore npmDepsHash) changes between node
  # releases, so pin it instead of following nixpkgs' default.
  nodejs ? pkgs.nodejs_22,
  # Only claim platforms we have hashes for; anything else should fail as
  # "unsupported" rather than as a hash mismatch.
  platforms ? (
    if builtins.isAttrs npmDepsHash && npmDepsHash != { } then
      lib.attrNames npmDepsHash
    else
      lib.platforms.all
  ),
  description,
  homepage,
  license ? lib.licenses.mit,
  maintainers ? [ ],
}:

let
  common = {
    inherit pname version;
    src = pkgs.fetchurl {
      url = tarballUrl npmName version;
      inherit hash;
    };
    sourceRoot = "package";
    installPhase = copyPhase;
    meta = {
      inherit
        description
        homepage
        license
        platforms
        maintainers
        ;
    };
  };

  # Runs against the built output: a green build then means "the artifact is
  # right", not just "npm exited 0". It does not import the package, because pi
  # extensions resolve their @earendil-works/pi-* peers from pi at runtime.
  mkSmokeTest =
    self:
    pkgs.runCommandLocal "${pname}-smoke-test" { nativeBuildInputs = [ nodejs ]; } ''
      set -euo pipefail
      export HOME="$TMPDIR"

      pkgRoot=${lib.escapeShellArg (toString self)}

      ${manifestCheck}

      # Catches a .nix copied from another package and entrypoints the published
      # tarball does not actually ship.
      node "$TMPDIR/manifest.cjs" "$pkgRoot" ${lib.escapeShellArg npmName} ${lib.escapeShellArg version}

      # node_modules is skipped: those files are already integrity-checked.
      find "$pkgRoot" -name node_modules -prune -o -type f \
        \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) -exec node --check {} \;

      jsFiles=$(find "$pkgRoot" -name node_modules -prune -o -type f \
        \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) -print | wc -l | tr -d ' ')

      echo "smoke test passed: ${pname}-${version} ($jsFiles JS file(s) parsed)" > "$out"
    '';

  # Inlined to keep the builder self-contained.
  manifestCheck = ''
    cat > "$TMPDIR/manifest.cjs" <<'JS'
    "use strict";
    const fs = require("node:fs");
    const path = require("node:path");

    const [root, expectedName, expectedVersion] = process.argv.slice(2);
    const manifest = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));

    if (manifest.name !== expectedName) {
      console.error("package.json name is " + manifest.name + ", expected " + expectedName);
      process.exit(1);
    }
    if (manifest.version !== expectedVersion) {
      console.error("package.json version is " + manifest.version + ", expected " + expectedVersion);
      process.exit(1);
    }

    // Bare specifiers, absolute paths and wildcard subpath patterns are not files.
    const declared = [];
    const isFileish = (value) =>
      typeof value === "string" &&
      value.indexOf("*") === -1 &&
      !value.startsWith("node:") &&
      !value.startsWith("@") &&
      !value.startsWith("/") &&
      !/^[a-z]+:/i.test(value);
    const add = (value) => {
      if (isFileish(value)) declared.push(value.replace(/^\.\//, ""));
    };

    add(manifest.main);
    add(manifest.module);
    add(manifest.types);
    if (typeof manifest.bin === "string") add(manifest.bin);
    if (manifest.bin && typeof manifest.bin === "object") {
      for (const value of Object.values(manifest.bin)) add(value);
    }
    const walkExports = (node) => {
      if (typeof node === "string") return add(node);
      if (node === null || typeof node !== "object") return;
      for (const value of Object.values(node)) walkExports(value);
    };
    walkExports(manifest.exports);

    const missing = declared.filter((rel) => !fs.existsSync(path.join(root, rel)));
    if (missing.length > 0) {
      console.error("declared entrypoints missing from the output: " + missing.join(", "));
      process.exit(1);
    }
    console.log("manifest ok: " + declared.length + " entrypoint(s) present");
    JS
  '';

  depsArgs =
    if lock == null then
      { }
    else
      {
        nativeBuildInputs = [ pkgs.jq ];
        postPatch = stripPeers lock;
        inherit nodejs;
        npmDepsHash = depsHashFor pname npmDepsHash;
        # The lock still records optional/peer edges that postPatch removed.
        npmInstallFlags = [ "--legacy-peer-deps" ];
        dontNpmBuild = true;
      };

  base = (if lock == null then pkgs.stdenvNoCC.mkDerivation else pkgs.buildNpmPackage) (
    common // depsArgs
  );
in
base
// {
  # Self-reference: the tests run against the final output path.
  passthru = (base.passthru or { }) // {
    inherit nodejs;
    # For `nix-update`; see update-package.sh.
    updateScript = [ ./update-package.sh ];
    tests = {
      smoke = mkSmokeTest (base // { });
    };
  };
}
