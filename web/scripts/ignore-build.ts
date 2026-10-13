#!/usr/bin/env node
// Vercel's Ignored Build Step (ignoreCommand in vercel.json), run in web/ before each build. It exits 0 to
// skip the build and 1 to build. A commit is built only when something the site reads has changed since
// the branch's last deployment: a file in web/ or an image sync-assets.mjs copies, or what the pages show
// from the documents lib/repo.ts reads. Anything it can't settle is built.

import { execFileSync } from "node:child_process";
import { parseCameras } from "../lib/cameras.ts";
import { parseComparison } from "../lib/comparison.ts";
import { parseLastUpdated, parseRoadmap, parseWorksToday } from "../lib/readme.ts";
import type { RepoFile } from "../lib/repo.ts";
import { parseTracker } from "../lib/tracker.ts";

// What the build compiles or copies, as git pathspecs (the images are sync-assets.mjs's sources). Any change
// to one is built.
const sources = [
  "web/",
  ":(glob,icase)docs/images/*.png",
  ":(glob,icase)docs/images/*.jpg",
  ":(glob,icase)docs/images/*.jpeg",
  "docs/images/film/",
  "docs/brand/images/",
  "docs/brand/logo/",
];

// What the pages show from each document. A commit whose documents give the same views isn't built, so
// anything else a page starts to show from one of them belongs in its view.
const views: Record<RepoFile, (text: string) => unknown> = {
  "README.md": (text) => [parseRoadmap(text), parseWorksToday(text), parseLastUpdated(text)],
  "docs/research/research-tracker.md": parseTracker,
  "docs/lightroom-comparison.md": parseComparison,
  "docs/cameras.md": parseCameras,
  "docs/performance/metrics.json": (text) => text,
  "docs/performance/history.jsonl": (text) => text,
  "docs/camera-bench.schema.json": (text) => text,
  "docs/camera-bench.json": (text) => text,
};
const documents = Object.keys(views) as RepoFile[];
const isDocument = (name: string): name is RepoFile => Object.hasOwn(views, name);

const top = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
const git = (...args: string[]) =>
  execFileSync("git", ["-C", top, ...args], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
    maxBuffer: 1 << 28,
    timeout: 60_000,
  });

function present(commit: string): boolean {
  try {
    git("cat-file", "-e", `${commit}^{commit}`);
    return true;
  } catch {
    return false;
  }
}

const list = (names: string[]) => (names.length < 2 ? names.join("") : `${names.slice(0, -1).join(", ")} and ${names.at(-1)}`);

/** A document's view at a commit; one that's missing or doesn't parse differs from every other. */
function view(file: RepoFile, commit: string): string {
  try {
    return JSON.stringify(views[file](git("show", `${commit}:${file}`)));
  } catch {
    return `unreadable at ${commit}`;
  }
}

function decide(): { build: boolean; reason: string } {
  const head = process.env.VERCEL_GIT_COMMIT_SHA || git("rev-parse", "HEAD").trim();
  const base = process.env.VERCEL_GIT_PREVIOUS_SHA;
  if (!base) return { build: true, reason: "this branch has no earlier deployment to compare with" };
  if (base === head) return { build: true, reason: "this is a redeployment of the same commit" };
  const since = `since ${base.slice(0, 7)}, the last deployment`;

  // Vercel clones 10 commits deep. The repository is public, so the last deployment's commit can be
  // fetched without the clone's credentials.
  if (!present(base)) {
    const repo = `https://github.com/${process.env.VERCEL_GIT_REPO_OWNER}/${process.env.VERCEL_GIT_REPO_SLUG}.git`;
    try {
      git("fetch", "--quiet", "--depth=1", "--no-tags", repo, base);
    } catch {}
    if (!present(base)) return { build: true, reason: `${base.slice(0, 7)}, the last deployment, couldn't be fetched` };
  }

  const changed = git("diff", "--name-only", "--no-renames", base, head, "--", ...sources, ...documents)
    .split("\n")
    .filter(Boolean);
  if (changed.length === 0) return { build: false, reason: `nothing the site reads has changed ${since}` };
  const source = changed.find((name) => !isDocument(name));
  if (source) return { build: true, reason: `${source} has changed ${since}` };
  const shown = changed.filter(isDocument).filter((name) => view(name, base) !== view(name, head));
  if (shown.length) return { build: true, reason: `what the site shows from ${list(shown)} has changed ${since}` };
  return { build: false, reason: `${list(changed)} changed ${since}, but not in what the site shows` };
}

const { build, reason } = decide();
console.log(`${build ? "Building" : "Skipping the build"}: ${reason}.`);
process.exit(build ? 1 : 0);
