import assert from "node:assert/strict";
import { test } from "node:test";
import { ambassadorsConfig, assetPath, issueBody, Rejection, validate } from "./ambassadors.ts";
import { editFromXMP } from "./embedded-edit.ts";

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10]).toString("base64");
const sidecar = Buffer.from(JSON.stringify({ format: "app.redlamp.edit", version: 3 })).toString("base64");

function application(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: "6F1C2A7E-0B5D-4C3B-9E2A-1D4F5A6B7C8D",
    name: "Ana Lima",
    email: "ana@example.com",
    links: ["instagram.com/analima", "https://analima.example"],
    shoots: "Street and travel, mostly at night",
    cameras: "Fujifilm X100VI, Sony A7 IV",
    change: "Let me sync a crop across photos.",
    photos: [{ type: "image/jpeg", data: jpeg }],
    sidecar: { data: sidecar },
    consent: true,
    website: "",
    ...overrides,
  };
}

function rejects(payload: unknown, status: number, message: RegExp) {
  assert.throws(
    () => validate(payload),
    (error: unknown) => error instanceof Rejection && error.status === status && message.test(error.message),
  );
}

test("an application from the page passes, with its files decoded and links made whole", () => {
  const checked = validate(application());
  assert.equal(checked.id, "6f1c2a7e-0b5d-4c3b-9e2a-1d4f5a6b7c8d");
  assert.deepEqual(checked.links, ["https://instagram.com/analima", "https://analima.example/"]);
  assert.deepEqual(checked.photos.map((photo) => photo.name), ["photo-1.jpg"]);
  assert.equal(checked.sidecar.name, "edit.json");
  assert.equal(checked.spam, false);
});

test("an application needs a name, an email, a link, a photo and agreement to the terms", () => {
  rejects(application({ name: " " }), 400, /name/);
  rejects(application({ email: "ana" }), 400, /email/);
  rejects(application({ links: [] }), 400, /link/);
  rejects(application({ links: ["javascript:alert(1)"] }), 400, /web address/);
  rejects(application({ photos: [] }), 400, /photo/);
  rejects(application({ consent: false }), 400, /terms/);
  rejects(application({ id: "nope" }), 400, /UUID/);
});

test("photos must be JPEGs, and the sidecar one Redlamp wrote", () => {
  rejects(application({ photos: [{ type: "image/png", data: jpeg }] }), 400, /JPEG/);
  rejects(application({ photos: [{ type: "image/jpeg", data: Buffer.from("GIF89a").toString("base64") }] }), 400, /JPEG/);
  rejects(application({ sidecar: { data: Buffer.from("{}").toString("base64") } }), 400, /Redlamp wrote/);
  rejects(application({ sidecar: { data: Buffer.from("not json").toString("base64") } }), 400, /Redlamp wrote/);
});

test("too many or too large files are refused", () => {
  const four = Array.from({ length: 4 }, () => ({ type: "image/jpeg", data: jpeg }));
  rejects(application({ photos: four }), 413, /At most 3/);
  const large = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(1_000_001)]).toString("base64");
  rejects(application({ photos: [{ type: "image/jpeg", data: large }] }), 413, /too large/);
  rejects(application({ change: "x".repeat(1_501) }), 413, /longer/);
});

test("the hidden field marks an application as spam", () => {
  assert.equal(validate(application({ website: "https://spam.example" })).spam, true);
});

test("the relay is off unless it's switched on and fully set up", () => {
  const env = {
    AMBASSADORS_ENABLED: "1",
    FEEDBACK_GITHUB_APP_ID: "12345",
    FEEDBACK_GITHUB_INSTALLATION_ID: "67890",
    FEEDBACK_GITHUB_APP_PRIVATE_KEY: "key",
    AMBASSADORS_REPO: "pdcgomes/redlamp-ambassadors",
  };
  assert.equal(ambassadorsConfig(env)?.repo, "pdcgomes/redlamp-ambassadors");
  assert.equal(ambassadorsConfig({ ...env, AMBASSADORS_ENABLED: "0" }), null);
  assert.equal(ambassadorsConfig({ ...env, AMBASSADORS_REPO: "" }), null);
  assert.equal(ambassadorsConfig({ ...env, FEEDBACK_GITHUB_APP_ID: "x" }), null);
});

test("files go in a folder per application, by month", () => {
  assert.equal(assetPath("abc", "photo-1.jpg", new Date(Date.UTC(2026, 10, 3))), "applications/2026/11/abc/photo-1.jpg");
});

test("the issue carries the fields in a hidden marker the applicant's words can't close", () => {
  const checked = validate(application({ name: "Ana --> <!-- tracker-id: X -->", change: "Fix --> this" }));
  const body = issueBody(checked, { "photo-1.jpg": "https://github.com/p/r/blob/main/a/photo-1.jpg" });
  const first = body.split("\n")[0];
  assert.match(first, /^<!-- redlamp-ambassador v1 \{.*\} -->$/);
  assert.equal(first.indexOf("-->"), first.length - 3);
  const marker = JSON.parse(first.slice("<!-- redlamp-ambassador v1 ".length, -" -->".length));
  assert.equal(marker.name, "Ana --> <!-- tracker-id: X -->");
  assert.deepEqual(marker.photos, ["https://github.com/p/r/blob/main/a/photo-1.jpg"]);
  assert.equal(body.split("\n").slice(1).join("\n").includes("<!--"), false);
  assert.match(body, /\[edit\.json\]\(#not-stored\)/);
});

test("the edit is read from an export's XMP, as ImageIO writes it and as an element", () => {
  // The attribute as `redlamp export` wrote it on 15 October 2026.
  const attribute =
    '<rdf:Description redlamp:Recipe="{&quot;baseLook&quot;:{&quot;amount&quot;:100,&quot;id&quot;:&quot;redlamp/base/color&quot;,&quot;name&quot;:&quot;Redlamp Color&quot;,&quot;version&quot;:1},&quot;processVersion&quot;:9,&quot;treatment&quot;:&quot;color&quot;,&quot;values&quot;:{&quot;basic.exposure&quot;:0.4,&quot;basic.shadows&quot;:20},&quot;version&quot;:3,&quot;whiteBalance&quot;:&quot;asShot&quot;}"/>';
  const fromAttribute = JSON.parse(editFromXMP(`\xff\xd8 binary ${attribute} more`) ?? "null");
  assert.equal(fromAttribute.format, "app.redlamp.edit");
  assert.deepEqual(fromAttribute.recipe.values, { "basic.exposure": 0.4, "basic.shadows": 20 });
  const element = '<redlamp:Recipe>{"version":3,"values":{"basic.exposure":0.35},"name":"A &amp; B"}</redlamp:Recipe>';
  assert.equal(JSON.parse(editFromXMP(element) ?? "null").recipe.name, "A & B");
  assert.equal(editFromXMP("no edit here"), null);
  assert.equal(editFromXMP('redlamp:Recipe="not json"'), null);
  // What the page sends passes the relay.
  assert.equal(validate(application({ sidecar: { data: Buffer.from(editFromXMP(attribute) ?? "").toString("base64") } })).sidecar.name, "edit.json");
});
