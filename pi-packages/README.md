# pi-packages

Nix derivations for the pi extensions this repo installs. Sources are pinned npm
tarballs, dependency trees are fetched as fixed-output derivations, and nothing
runs `npm install` at runtime.

```text
default.nix        package set, `all` aggregate, flattened `checks`
mk.nix             the builder
<name>.nix         one spec per package: version, hashes, meta
<name>-lock.json   vendored package-lock.json, dev deps pruned
add-package.sh     scaffold a package, or bump an existing one
_scaffold.mjs      prefetch tarball, prune lock, read metadata
```

## Modes

A spec with a `lock` gets npm mode. Without one, copy mode.

| | copy | npm |
| --- | --- | --- |
| build | `stdenvNoCC`, `cp -r src $out` | `buildNpmPackage`, `npm ci --ignore-scripts` against a vendored dep tree |
| hashes | `hash` | `hash` + `npmDepsHash` per system |

Copy mode is for extensions with no runtime deps of their own: the published
tarball already is the artifact, so dragging npm in would cost a second hash and
a dep-tree fetch and change nothing.

## Dependencies

Read [the stdenv dependency reference](https://nixos.org/manual/nixpkgs/stable/#ssec-stdenv-dependencies-reference)
before this section. Those attributes exist so that build tools reach `PATH` and
fire their setup hooks, propagated inputs let a compiler or interpreter find what
it needs at run time, and the closure is recorded as an edge in the derivation
graph.

For a JavaScript tree only the first applies, and only for the tools we shell out
to. There is no linker, no `pkg-config`, no RPATH and no setup hooks that mean
anything here: node resolves `node_modules` by walking up from the importing file.
Nothing to wire, nothing to propagate.

What the builder declares:

| attribute | value | why |
| --- | --- | --- |
| `nativeBuildInputs` | `jq` (npm mode, for `stripPeers`), plus what `buildNpmPackage` adds: `nodejs`, the three npm hooks, `nodejs.python`, `cctools` on darwin | the only build-time tools |
| `buildInputs` | `nodejs`, added by `buildNpmPackage` | closure membership only; no wrapper is generated |
| `propagatedBuildInputs` | never | see below |

The dep tree is output content, not a dependency edge. `$out` holds the unpacked
tarball with `node_modules` next to the JS, `pi-shell.nix` passes the store path
as `--extension`, and node resolves from there at run time.

Consequences:

1. **The extension list in `pi-shell.nix` is the propagation mechanism.** Adding a
   package is two edits — the attrset in `default.nix`, the list in `pi-shell.nix`.
   Miss the second and it builds, passes its checks, and does nothing.
   `propagatedBuildInputs` would normally be what catches that; it cannot, because
   no consumer reads Nix metadata here.
2. **No peers, no second pi.** `stripPeers` deletes `peerDependencies` and
   `devDependencies` from the shipped manifest and the build installs with
   `--legacy-peer-deps` (the vendored lock still records those edges). Otherwise
   the closure carries a second copy of `@earendil-works/pi-*` beside the running
   pi, with two sets of state. So `$out/package.json` is not the published
   manifest in npm mode (copy mode ships it verbatim), the peer contract survives
   only in the lockfile, and a peer that pi stops providing fails at run time
   instead of at build time.
3. **No cross compilation.** `npmDepsHash` is per-platform because lockfiles carry
   platform-specific optional deps (`@ast-grep/napi`, `tree-sitter` prebuilds).
   Every recorded system builds natively, so the build/host/target split is never
   exercised, and a system without a hash is refused as unsupported rather than
   attempted.
4. **One blob per package.** No dedup between packages, and no way to patch a
   single transitive dep without regenerating the blob.

### Install layout

`mk.nix` sets `installPhase`, which `npmInstallHook` respects only while it is
unset, so the tarball's own layout survives. `dontNpmBuild = true` for the same
reason: there is nothing to build. That skips `npm pack` filtering — which would
re-derive the file list from the unpacked tree, i.e. from metadata that does not
describe the published artifact — along with `npm prune` and
`nodejsInstallExecutables`. Bin shims in `node_modules/.bin` keep their
`#!/usr/bin/env node` shebang and need `node` on `PATH`. These are libraries
loaded by pi; this is not a general npm packager.

### Why not `node2nix` or `importNpmLock`

`node2nix` re-derives npm's resolution in Nix: one derivation per transitive
dependency, a generated file of some thousands of lines, per-dep patching. That
pays off when you need to patch a transitive dep or share one tree between
packages. Here upstream already resolved the graph, the tarball is already built,
and no dep gets patched — so the only thing being recomputed is a tree we could
have copied.

[`importNpmLock`](https://nixos.org/manual/nixpkgs/stable/#javascript-buildNpmPackage-importNpmLock)
is the closer call and the one worth revisiting: it takes hashes from the
lockfile's `integrity` fields, so there is no `npmDepsHash` to reveal and no
coupling to the npm version in nixpkgs (see below). It pays with one fetch per
dependency — 154 for pi-lens — instead of one FOD, and a real `npm install` on
every build. Switching means changing `mk.nix` and deleting the `npmDepsHash`
blocks; no package spec logic moves.

## Where the network is

Two fetches, both fixed-output derivations:

1. `fetchurl` for the npm tarball, SRI-pinned.
2. `fetchNpmDeps` (inside `buildNpmPackage`) for the dependency tree, pinned by
   `npmDepsHash`.

The build runs `npm ci --ignore-scripts` against that tree, offline, in the
sandbox. Nothing else touches the network and no lifecycle script ever executes.
Everything downstream is a normal substitutable derivation.

## Hashes

`hash` is the SRI of the npm tarball and is platform independent. `npmDepsHash` is
the SRI of the dependency tree and is a function of **(lockfile, npm version,
platform)**, so it is recorded per system:

```nix
npmDepsHash = {
  aarch64-darwin = "sha256-…";
};
```

In npm mode `meta.platforms` is derived from those keys, which is why an
unrecorded system fails as *unsupported platform* instead of as a hash mismatch;
copy-mode packages claim `lib.platforms.all`. `mk.nix` pins
`nodejs = pkgs.nodejs_22` for the same reason: letting nixpkgs' default move would
rotate every hash with nothing changing upstream.

`flake.nix` pins the nixpkgs rev that `unflake.nix` resolves. Bump both together
or every hash goes stale:

```sh
./update-deps.sh          # unflake: new revs
nix flake update          # no-op unless flake.nix's rev literal changed too
# then re-reveal npmDepsHash for every package (below)
```

To add a platform: build there, paste the `got:` hash under the new system key,
add the system to `supportedSystems` in `flake.nix`.

## Adding a package

```sh
cd pi-packages
./add-package.sh pi-foo@1.2.3 --desc "What it does"
# wire the printed lines into default.nix and pi-shell.nix
nix build .#pi-foo -L 2>&1 | grep 'got:'    # paste into npmDepsHash
nix flake check
```

## Bumping a package

`update-package.sh` is the `passthru.updateScript`, so `nix-update` drives it. It
refreshes the tarball hash, regenerates the lock, and re-reveals `npmDepsHash` for
the current system in one pass, leaving the change uncommitted:

```sh
nix run nixpkgs#nix-update -- --flake pi-lens --version 4.4.7
```

`--version` is mandatory; the npm registry has no release feed to discover.

By hand it is the same sequence — re-run `add-package.sh` with the new version (it
preserves the existing `npmDepsHash` block so the next build prints the
replacement), then paste the `got:` value into the matching system key.

Locks are generated with the flake's pinned node (`nix shell .#nodejs`), not
whatever npm is on `PATH`; two people regenerating the same lock otherwise get
different JSON. Re-running for the **same** version keeps the lock byte-identical —
regenerating would float every `^` range to today's latest, which is how
`@ast-grep/cli` 0.45.2 quietly became 0.45.3 under an unchanged `^0.45.0`. A real
version bump does regenerate the lock on purpose; read that diff, because
transitive `^` ranges may have moved.

## Testing

`passthru.tests.smoke` runs against the built output, not the source:

1. `package.json` name/version match the spec (catches a `.nix` copied from another
   package) and every declared entrypoint (`main`, `module`, `types`, `bin`,
   `exports`) exists on disk;
2. every shipped `.js`/`.mjs`/`.cjs` parses under the pinned node, `node_modules`
   excluded — those are integrity-checked already.

It does not import the package: extensions resolve `@earendil-works/pi-*` peers
from pi at run time, so an import would test the environment, not the artifact.

```sh
nix flake check                                    # every smoke test + `all`
nix build .#all                                    # build everything
nix-build ./pi-shell.nix -A pi-packages.pi-lens    # flake-less path
```

## Not supported

Building an extension from source. `devDependencies` are pruned out of the lock
because the tarball is already built and this repo has no build step for it.

## Flake and non-flake

`shell.nix → pi-shell.nix → pi-packages/default.nix` is the primary path;
`flake.nix` only exposes `packages` / `checks` / `formatter` / `devShells` and
instantiates `pkgs` with the same rev and config, so both produce identical store
paths.

`nix` only sees git-tracked files, and this repo is jj-managed, so a new
`flake.nix` / `flake.lock` is invisible until committed. Until then use the path
form, which includes untracked files:

```sh
nix flake check "path:$PWD"
nix build "path:$PWD#pi-lens"
```
