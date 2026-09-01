# Shared builder for pi packages fetched from the npm registry.
#
# Two modes:
#   - no `lock`  -> plain copy of the tarball (package has no runtime deps
#                   beyond what pi itself bundles)
#   - with `lock` -> buildNpmPackage with the vendored package-lock.json
#
# `npmDepsHash` defaults to lib.fakeHash so a first build *reveals* the real
# hash; paste it back and rebuild.
{
  pkgs,
  lib ? pkgs.lib,
}:

let
  # npm tarball URL, handling scoped packages:
  #   "pi-lens"            -> https://registry.npmjs.org/pi-lens/-/pi-lens-4.1.1.tgz
  #   "@remnic/plugin-pi"  -> https://registry.npmjs.org/@remnic/plugin-pi/-/plugin-pi-9.69.33.tgz
  tarballUrl =
    npmName: version:
    "https://registry.npmjs.org/${npmName}/-/${lib.last (lib.splitString "/" npmName)}-${version}.tgz";

  copyPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r . $out/
    runHook postInstall
  '';

  # Copy the vendored lock and strip peer/dev deps:
  # peer deps are provided by pi at runtime; dev deps are only for the TS build.
  stripPeers = lock: ''
    cp ${lock} package-lock.json
    ${pkgs.jq}/bin/jq 'del(.peerDependencies, .devDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
  '';
in
{
  pname,
  npmName ? pname,
  version,
  hash,
  lock ? null,
  npmDepsHash ? pkgs.lib.fakeHash,
  description,
  homepage,
  license ? lib.licenses.mit,
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
      inherit description homepage license;
    };
  };
in
if lock == null then
  pkgs.stdenvNoCC.mkDerivation common
else
  pkgs.buildNpmPackage (
    common
    // {
      nativeBuildInputs = [ pkgs.jq ];
      postPatch = stripPeers lock;
      inherit npmDepsHash;
      npmInstallFlags = [ "--legacy-peer-deps" ];
      dontNpmBuild = true;
    }
  )
