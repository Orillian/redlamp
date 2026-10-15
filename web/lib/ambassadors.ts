import { type AppCredentials, github, installationToken } from "./github-app.ts";

/**
 * The relay behind redlamp.app/ambassadors: it files an application to Redlamp's ambassador
 * programme as an issue in a private repository, as the Redlamp Feedback app, with the photos the
 * applicant edited in Redlamp and one photo's sidecar stored beside it in the same repository.
 * Nothing an applicant sends reaches a public repository.
 */
export interface AmbassadorsConfig extends AppCredentials {
  /** The private repository that holds applications and their files. */
  repo: string;
}

export interface Attachment {
  name: string;
  type: string;
  data: Buffer;
}

export interface Application {
  id: string;
  name: string;
  email: string;
  links: string[];
  shoots: string;
  cameras: string;
  change: string;
  photos: Attachment[];
  sidecar: Attachment;
  /** The hidden field people don't see and bots fill in. */
  spam: boolean;
}

export const limits = {
  name: 120,
  email: 254,
  links: 3,
  link: 300,
  shoots: 600,
  cameras: 300,
  change: 1_500,
  photos: 3,
  photoBytes: 1_000_000,
  sidecarBytes: 400_000,
  // Base64 makes the request a third larger, and Vercel's functions take 4.5 MB.
  totalBytes: 3_200_000,
};

const REPO = /^[A-Za-z0-9-]+\/[A-Za-z0-9._-]+$/;
const UUID = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;

/** The relay's settings, or `null` when it's switched off or not set up (the route answers 503). */
export function ambassadorsConfig(env: Record<string, string | undefined>): AmbassadorsConfig | null {
  if (env.AMBASSADORS_ENABLED !== "1") return null;
  const config = {
    appId: env.FEEDBACK_GITHUB_APP_ID ?? "",
    installationId: env.FEEDBACK_GITHUB_INSTALLATION_ID ?? "",
    privateKey: env.FEEDBACK_GITHUB_APP_PRIVATE_KEY ?? "",
    repo: env.AMBASSADORS_REPO ?? "",
  };
  if (!/^\d+$/.test(config.appId) || !/^\d+$/.test(config.installationId) || !config.privateKey) return null;
  if (!REPO.test(config.repo)) return null;
  return config;
}

export class Rejection extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function text(value: unknown, name: string, max: number, required = true): string {
  if (value === undefined || value === null || (typeof value === "string" && !value.trim())) {
    if (required) throw new Rejection(400, `${name} is missing`);
    return "";
  }
  if (typeof value !== "string") throw new Rejection(400, `${name} isn't text`);
  if (value.length > max) throw new Rejection(413, `${name} is longer than ${max} characters`);
  return value.trim();
}

function link(value: unknown): string {
  const raw = text(value, "a link", limits.link);
  let url: URL;
  try {
    url = new URL(raw.includes("://") ? raw : `https://${raw}`);
  } catch {
    throw new Rejection(400, `${raw} isn't a web address`);
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") throw new Rejection(400, `${raw} isn't a web address`);
  return url.toString();
}

function file(value: unknown, name: string): { name: string; type: unknown; data: Buffer } {
  const item = (value ?? {}) as Record<string, unknown>;
  const data = Buffer.from(text(item.data, `${name}'s data`, 8_000_000), "base64");
  return { name, type: item.type, data };
}

/** Checks an application as the page sends it, and decodes its files. */
export function validate(payload: unknown): Application {
  if (typeof payload !== "object" || payload === null) throw new Rejection(400, "The application isn't JSON");
  const input = payload as Record<string, unknown>;
  const id = text(input.id, "id", 64);
  if (!UUID.test(id)) throw new Rejection(400, "id isn't a UUID");
  const name = text(input.name, "Your name", limits.name);
  const email = text(input.email, "Your email", limits.email);
  if (!/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(email)) throw new Rejection(400, "Your email doesn't look like an email address");
  if (!Array.isArray(input.links) || input.links.length === 0) throw new Rejection(400, "A link to your work is missing");
  if (input.links.length > limits.links) throw new Rejection(413, `At most ${limits.links} links`);
  const links = input.links.map(link);
  const shoots = text(input.shoots, "What you shoot", limits.shoots);
  const cameras = text(input.cameras, "Your cameras", limits.cameras);
  const change = text(input.change, "What you'd change first", limits.change);
  if (input.consent !== true) throw new Rejection(400, "Please agree to the terms and the privacy note");

  if (!Array.isArray(input.photos) || input.photos.length === 0) throw new Rejection(400, "A photo you edited in Redlamp is missing");
  if (input.photos.length > limits.photos) throw new Rejection(413, `At most ${limits.photos} photos`);
  const photos = input.photos.map((value, index): Attachment => {
    const photo = file(value, `photo-${index + 1}.jpg`);
    if (photo.type !== "image/jpeg" || photo.data[0] !== 0xff || photo.data[1] !== 0xd8 || photo.data[2] !== 0xff) {
      throw new Rejection(400, `Photo ${index + 1} isn't a JPEG`);
    }
    if (photo.data.length > limits.photoBytes) throw new Rejection(413, `Photo ${index + 1} is too large`);
    return { ...photo, type: "image/jpeg" };
  });

  const sidecar = file(input.sidecar, "edit.redlamp");
  if (sidecar.data.length > limits.sidecarBytes) throw new Rejection(413, "The .redlamp file is too large");
  let format: unknown;
  try {
    format = (JSON.parse(sidecar.data.toString("utf8")) as Record<string, unknown>).format;
  } catch {
    throw new Rejection(400, "The .redlamp file isn't one Redlamp wrote");
  }
  if (format !== "app.redlamp.edit") throw new Rejection(400, "The .redlamp file isn't one Redlamp wrote");

  const total = photos.reduce((sum, photo) => sum + photo.data.length, sidecar.data.length);
  if (total > limits.totalBytes) throw new Rejection(413, "The photos are too large together");

  return {
    id: id.toLowerCase(),
    name,
    email,
    links,
    shoots,
    cameras,
    change,
    photos,
    sidecar: { name: sidecar.name, type: "application/json", data: sidecar.data },
    spam: typeof input.website === "string" && input.website.trim() !== "",
  };
}

/** Where an application's files are stored: one folder per application, by month. */
export function assetPath(id: string, name: string, date = new Date()): string {
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  return `applications/${date.getUTCFullYear()}/${month}/${id}/${name}`;
}

/** Text from the applicant, kept from closing the issue's hidden marker or adding one of its own. */
function plain(value: string): string {
  return value.replace(/<!--/g, "&lt;!--").replace(/-->/g, "--&gt;");
}

/**
 * The issue's body: what the applicant wrote, the files, and a hidden marker with the fields as JSON
 * for the ambassadors room's sync (`.cursor/skills/redlamp-ambassadors/room.py`).
 */
export function issueBody(application: Application, files: Record<string, string>): string {
  const marker = {
    id: application.id,
    name: application.name,
    email: application.email,
    links: application.links,
    shoots: application.shoots,
    cameras: application.cameras,
    photos: application.photos.map((photo) => files[photo.name] ?? photo.name),
    sidecar: files[application.sidecar.name] ?? application.sidecar.name,
  };
  const json = JSON.stringify(marker).replace(/--/g, "\\u002d\\u002d");
  return [
    `<!-- redlamp-ambassador v1 ${json} -->`,
    `**${plain(application.name)}** (${plain(application.email)})`,
    "",
    ...application.links.map((url) => `- ${url}`),
    "",
    `**Shoots:** ${plain(application.shoots)}`,
    "",
    `**Cameras:** ${plain(application.cameras)}`,
    "",
    "**What they'd change first in Redlamp:**",
    "",
    plain(application.change),
    "",
    "**Edited in Redlamp:**",
    "",
    ...application.photos.map((photo, index) => `- [Photo ${index + 1}](${files[photo.name] ?? "#not-stored"})`),
    `- [${application.sidecar.name}](${files[application.sidecar.name] ?? "#not-stored"})`,
  ].join("\n");
}

// MARK: - Filing

export interface Filed {
  number: number;
}

async function upload(token: string, config: AmbassadorsConfig, application: Application, attachment: Attachment) {
  const path = assetPath(application.id, attachment.name);
  const target = `/repos/${config.repo}/contents/${path}`;
  let response = await github(token, target, {
    method: "PUT",
    body: { message: `Application ${application.id}: ${attachment.name}`, content: attachment.data.toString("base64") },
  });
  // A retry of the same application finds its file already there.
  if (response.status === 422) response = await github(token, target);
  if (!response.ok) throw new Error(`GitHub didn't store ${attachment.name} (${response.status})`);
  const stored = (await response.json()) as { content?: { html_url: string }; html_url?: string };
  // The repository is private, so its raw addresses expire; its pages show the file to the owner.
  const url = (stored.content ?? stored).html_url;
  if (!url) throw new Error(`GitHub stored ${attachment.name} without an address`);
  return url;
}

/** Stores the files, then files the issue, labelled `application` when the label exists. */
export async function fileApplication(config: AmbassadorsConfig, application: Application): Promise<Filed> {
  const token = await installationToken(config);
  const files: Record<string, string> = {};
  for (const attachment of [...application.photos, application.sidecar]) {
    files[attachment.name] = await upload(token, config, application, attachment);
  }
  const label = await github(token, `/repos/${config.repo}/labels/application`);
  const response = await github(token, `/repos/${config.repo}/issues`, {
    method: "POST",
    body: {
      title: `Application: ${application.name}`,
      body: issueBody(application, files),
      labels: label.ok ? ["application"] : [],
    },
  });
  if (!response.ok) throw new Error(`GitHub didn't file the application (${response.status})`);
  const issue = (await response.json()) as { number: number };
  return { number: issue.number };
}
