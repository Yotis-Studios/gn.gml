#!/usr/bin/env node
// GML CI check using @bscotch/gml-parser
// Parses the entire GameMaker project and reports diagnostics (parse errors,
// unresolved references, etc.) without requiring a GameMaker license.

import { Project } from "@bscotch/gml-parser";
import { resolve, join } from "path";

const nmBase = join(process.cwd(), "node_modules/@bscotch");

// Patch stitch-launcher to skip all network calls.
// Native.listSpecFiles -> uses bundled fallback GML spec
// GameMakerComponent.listReleases -> returns empty (prevents runtime lookups)
const { Native } = await import(
  "file://" + join(nmBase, "gml-parser/dist/project.native.js")
);
Native.listSpecFiles = async () => [Native.fallbackGmlSpecPath];

const { GameMakerComponent } = await import(
  "file://" + join(nmBase, "stitch-launcher/dist/lib/GameMakerComponent.js")
);
GameMakerComponent.listReleases = async () => [];

const yypPath = resolve("gn.gml.yyp");
let errors = 0;
let warnings = 0;

console.log("Parsing GameMaker project...\n");

const project = await Project.initialize(yypPath, {
  onDiagnostics({ filePath, diagnostics }) {
    for (const d of diagnostics) {
      const loc = d.location;
      const line = loc?.start?.line ?? "?";
      const prefix =
        d.severity === "error"
          ? "ERROR"
          : d.severity === "warning"
            ? "WARN "
            : "INFO ";

      console.log(`${prefix} ${filePath}:${line}: ${d.message}`);

      if (d.severity === "error") errors++;
      else if (d.severity === "warning") warnings++;
    }
  },
  onLoadProgress() {},
  logger: { log() {}, warn() {}, error() {} },
});

// Check that all assets loaded
for (const [name, asset] of project.assets) {
  if (!asset) {
    console.log(`ERROR missing asset: ${name}`);
    errors++;
  }
}

console.log("\n──────────────────────────────────");
console.log(`Results: ${errors} error(s), ${warnings} warning(s)`);
console.log("──────────────────────────────────");

process.exit(errors > 0 ? 1 : 0);
