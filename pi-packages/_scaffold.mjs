// Helper for add-package.sh: prefetch the tarball, inspect its manifest, and
// generate a pruned package-lock.json when the package has runtime deps.
// Writes ./<pname>-lock.json into the caller's cwd.
//
// Emits KEY=VALUE lines on stdout: HASH, HOMEPAGE, DESC, LICENSE, SPDX,
// HAS_DEPS, REUSED_LOCK, RUNTIME.
//
// Must run under the same node/npm mk.nix pins (pkgs.nodejs_22):
//   nix shell .#nodejs --command node _scaffold.mjs <name>@<version> <pname>
import { execSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, writeFileSync, readFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [spec, pname] = process.argv.slice(2);
const at = spec.lastIndexOf("@");
const npmName = spec.slice(0, at);
const version = spec.slice(at + 1);
const base = npmName.split("/").pop();
const url = `https://registry.npmjs.org/${npmName}/-/${base}-${version}.tgz`;

// SPDX id -> nixpkgs `lib.licenses` attribute. Unmapped ids are left out of the
// generated .nix so they fail in review instead of defaulting to MIT.
const LICENSE_MAP = {
  MIT: "mit",
  ISC: "isc",
  "Apache-2.0": "asl20",
  "BSD-2-Clause": "bsd2",
  "BSD-3-Clause": "bsd3",
  "0BSD": "bsd0",
  "MPL-2.0": "mpl20",
  "GPL-2.0-only": "gpl2Only",
  "GPL-3.0-only": "gpl3Only",
  "GPL-3.0-or-later": "gpl3Plus",
  "LGPL-3.0-only": "lgpl3Only",
  Unlicense: "unlicense",
};

const outDir = process.cwd();

// Re-running for the SAME version must not re-resolve the tree: `npm install
// --package-lock-only` floats every `^` range to today's latest (@ast-grep/cli
// 0.45.2 once became 0.45.3 while its range stayed "^0.45.0"). A new version
// regenerates on purpose — review the diff for range drift.
const keepLock = () => {
  const existing = join(outDir, `${pname}-lock.json`);
  if (!existsSync(existing)) return false;
  try {
    return JSON.parse(readFileSync(existing, "utf8"))?.packages?.[""]?.version === version;
  } catch {
    return false; // unreadable/invalid: regenerate
  }
};

const dir = mkdtempSync(join(tmpdir(), "pi-add-"));
const tgz = join(dir, "pkg.tgz");

try {
  execSync(`curl -fsSL '${url}' -o ${tgz}`, { stdio: "pipe" });
  const buf = readFileSync(tgz);
  const hash = "sha256-" + createHash("sha256").update(buf).digest("base64");

  execSync(`tar xzf ${tgz} -C ${dir}`);
  const pj = JSON.parse(readFileSync(join(dir, "package", "package.json"), "utf8"));
  const deps = { ...(pj.dependencies || {}), ...(pj.optionalDependencies || {}) };
  const piProvided = (n) => n.startsWith("@earendil-works/pi-") || n === "typebox";
  const runtime = Object.keys(deps).filter((n) => !piProvided(n));
  const spdx = typeof pj.license === "string" ? pj.license : (pj.license && pj.license.type) || "";

  const hasDeps = runtime.length > 0;
  let reusedLock = false;

  if (hasDeps && keepLock()) {
    reusedLock = true;
  } else if (hasDeps) {
    const pkgDir = join(dir, "package");
    // --omit=dev: devDeps are not shipped in the published tarball.
    // --ignore-scripts: the lock only records what to fetch.
    execSync(
      `cd ${pkgDir} && npm install --package-lock-only --legacy-peer-deps --omit=dev --ignore-scripts --no-audit --no-fund`,
      { stdio: "pipe" },
    );
    const lock = JSON.parse(readFileSync(join(pkgDir, "package-lock.json"), "utf8"));
    const pkgs = lock.packages || {};
    for (const k of Object.keys(pkgs)) {
      if (k === "") continue;
      // Supplied by pi at runtime; vendoring would shadow the agent's copies.
      if (k.includes("@earendil-works/pi-") || !k.startsWith("node_modules/")) delete pkgs[k];
    }
    const root = pkgs[""] || {};
    for (const f of ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"]) {
      if (root[f]) for (const k of Object.keys(root[f])) if (k.includes("@earendil-works/pi-")) delete root[f][k];
    }
    writeFileSync(join(outDir, `${pname}-lock.json`), JSON.stringify(lock, null, 2));
  }

  console.log(`HASH=${hash}`);
  console.log(`HOMEPAGE=${pj.homepage || ""}`);
  console.log(`DESC=${pj.description || ""}`);
  console.log(`LICENSE=${LICENSE_MAP[spdx] || ""}`);
  console.log(`SPDX=${spdx}`);
  console.log(`HAS_DEPS=${hasDeps}`);
  if (reusedLock) console.log("REUSED_LOCK=1");
  if (runtime.length > 0) console.log(`RUNTIME=${runtime.join(",")}`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}
