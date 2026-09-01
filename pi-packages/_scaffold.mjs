// Helper for add-package.sh: prefetch the tarball, inspect runtime deps, and
// generate a pruned package-lock.json when needed.
//
// Emits KEY=VALUE lines on stdout:
//   HASH=sha256-...        SRI hash of the npm tarball
//   HOMEPAGE=...           package.json homepage (may be empty)
//   HAS_DEPS=true|false    whether it needs node_modules (buildNpmPackage)
//   RUNTIME=a,b,c          non-pi-provided runtime deps (informational)
//
// Writes ./<pname>-lock.json (into the caller's cwd) when HAS_DEPS=true.
import { execSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [spec, pname] = process.argv.slice(2);
const at = spec.lastIndexOf("@");
const npmName = spec.slice(0, at);
const version = spec.slice(at + 1);
const base = npmName.split("/").pop();
const url = `https://registry.npmjs.org/${npmName}/-/${base}-${version}.tgz`;

const outDir = process.cwd();
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

  let hasDeps = false;
  if (runtime.length > 0) {
    const pkgDir = join(dir, "package");
    execSync(
      `cd ${pkgDir} && npm install --package-lock-only --legacy-peer-deps --omit=dev --ignore-scripts --no-audit --no-fund`,
      { stdio: "pipe" },
    );
    const lock = JSON.parse(readFileSync(join(pkgDir, "package-lock.json"), "utf8"));
    const pkgs = lock.packages || {};
    for (const k of Object.keys(pkgs)) {
      if (k === "") continue;
      if (k.includes("@earendil-works/pi-") || !k.startsWith("node_modules/")) delete pkgs[k];
    }
    const root = pkgs[""] || {};
    for (const f of ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"]) {
      if (root[f]) for (const k of Object.keys(root[f])) if (k.includes("@earendil-works/pi-")) delete root[f][k];
    }
    writeFileSync(join(outDir, `${pname}-lock.json`), JSON.stringify(lock, null, 2));
    hasDeps = true;
  }

  console.log(`HASH=${hash}`);
  console.log(`HOMEPAGE=${pj.homepage || ""}`);
  console.log(`HAS_DEPS=${hasDeps}`);
  if (runtime.length > 0) console.log(`RUNTIME=${runtime.join(",")}`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}
