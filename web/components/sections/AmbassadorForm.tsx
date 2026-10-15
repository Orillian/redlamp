"use client";

import { type DragEvent, type FormEvent, useState } from "react";
import { editFromXMP } from "@/lib/embedded-edit";

// The relay's limits (lib/ambassadors.ts): each photo under 1,000,000 bytes, all of them with the
// edit under 3,200,000.
const LONG_EDGE = 2048;
const PHOTO_BYTES = 950_000;
const EDIT_FORMAT = "app.redlamp.edit";

type State = { kind: "idle" } | { kind: "sending" } | { kind: "sent" } | { kind: "error"; message: string };

function base64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(",")[1] ?? "");
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });
}

/** The photo as a JPEG at most 2,048 pixels on its long edge, compressed until it's under the limit. */
async function downscaled(file: File): Promise<Blob> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, LONG_EDGE / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d")?.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  for (const quality of [0.9, 0.82, 0.74, 0.66, 0.58]) {
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", quality));
    if (blob && blob.size <= PHOTO_BYTES) return blob;
  }
  throw new Error(`${file.name} is too detailed to send at this size. Try exporting it smaller.`);
}

/** The edit an export carries. Resizing in the browser drops the metadata, so it's read first. */
async function embeddedEdit(file: File): Promise<string | null> {
  return editFromXMP(new TextDecoder("utf-8").decode(await file.arrayBuffer()));
}

/** A sidecar's edit: `edit.json` from a dropped .redlamp package, or a single-file sidecar or edit.json. */
async function droppedEdit(event: DragEvent<HTMLElement>): Promise<string | null> {
  const entry = event.dataTransfer.items[0]?.webkitGetAsEntry();
  if (entry?.isDirectory) {
    const directory = entry as FileSystemDirectoryEntry;
    const file = await new Promise<File | null>((resolve) =>
      directory.getFile("edit.json", {}, (found) => (found as FileSystemFileEntry).file(resolve, () => resolve(null)), () => resolve(null)),
    );
    return file ? file.text() : null;
  }
  const file = event.dataTransfer.files[0];
  return file ? file.text() : null;
}

function isEdit(text: string | null): text is string {
  if (!text) return false;
  try {
    return (JSON.parse(text) as Record<string, unknown>).format === EDIT_FORMAT;
  } catch {
    return false;
  }
}

const field = "mt-1.5 w-full rounded-[10px] border border-hairline bg-wall px-3.5 py-2.5 text-[15px] text-paper placeholder:text-dim focus:border-hairline-strong focus:outline-none";
const fileField = `${field} file:mr-3 file:rounded-pill file:border-0 file:bg-wall-raised file:px-3 file:py-1 file:text-paper`;
const label = "block text-[14px] font-medium text-paper";
const hint = "mt-1 text-[13px] text-dim";

export function AmbassadorForm() {
  const [state, setState] = useState<State>({ kind: "idle" });
  const [sidecar, setSidecar] = useState<{ name: string; text: string } | null>(null);
  const [dropping, setDropping] = useState(false);

  async function take(text: string | null, name: string) {
    if (isEdit(text)) {
      setSidecar({ name, text });
      setState({ kind: "idle" });
    } else {
      setSidecar(null);
      setState({ kind: "error", message: `${name} isn't a .redlamp file Redlamp wrote. It's beside your raw, with the same name and .redlamp at the end.` });
    }
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const photos = form.getAll("photos").filter((value): value is File => value instanceof File && value.size > 0);
    if (photos.length === 0) return setState({ kind: "error", message: "Add a photo you exported from Redlamp." });
    if (photos.length > 3) return setState({ kind: "error", message: "Add at most three photos." });
    setState({ kind: "sending" });
    try {
      let edit = sidecar?.text ?? null;
      for (const photo of photos) {
        if (edit) break;
        edit = await embeddedEdit(photo);
      }
      if (!edit) {
        throw new Error(
          "None of these photos carries a Redlamp edit. Export one from Redlamp with Metadata set to All, or drop its .redlamp file in the box above.",
        );
      }
      const encoded = await Promise.all(
        photos.map(async (photo) => ({ type: "image/jpeg", data: await base64(await downscaled(photo)) })),
      );
      const links = String(form.get("links") ?? "")
        .split(/[\s,]+/)
        .map((link) => link.trim())
        .filter(Boolean)
        .slice(0, 3);
      const response = await fetch("/api/ambassadors", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          id: crypto.randomUUID(),
          name: form.get("name"),
          email: form.get("email"),
          links,
          shoots: form.get("shoots"),
          cameras: form.get("cameras"),
          change: form.get("change"),
          photos: encoded,
          sidecar: { data: await base64(new Blob([edit])) },
          consent: form.get("consent") === "on",
          website: form.get("website"),
        }),
      });
      if (!response.ok) {
        const body = (await response.json().catch(() => ({}))) as { error?: string };
        throw new Error(body.error ?? "Your application didn't go through. Please try again in a few minutes.");
      }
      setState({ kind: "sent" });
    } catch (error) {
      setState({ kind: "error", message: error instanceof Error ? error.message : String(error) });
    }
  }

  if (state.kind === "sent") {
    return (
      <div className="surface p-6 sm:p-8">
        <h3 className="font-display text-[22px] text-paper">Thanks. Your application is in.</h3>
        <p className="mt-3 max-w-2xl text-[15px] leading-relaxed text-mute">
          I read every one myself, and I&apos;ll reply by email within two weeks, whatever the answer.
        </p>
      </div>
    );
  }

  return (
    <form onSubmit={submit} className="surface grid gap-6 p-6 sm:p-8 md:grid-cols-2">
      <div>
        <label className={label} htmlFor="name">Your name</label>
        <input id="name" name="name" required maxLength={120} autoComplete="name" className={field} />
      </div>
      <div>
        <label className={label} htmlFor="email">Your email</label>
        <input id="email" name="email" type="email" required maxLength={254} autoComplete="email" className={field} />
      </div>
      <div className="md:col-span-2">
        <label className={label} htmlFor="links">Where you share your work</label>
        <input id="links" name="links" required maxLength={900} placeholder="instagram.com/you, your website" className={field} />
        <p className={hint}>Up to three links, separated by commas.</p>
      </div>
      <div>
        <label className={label} htmlFor="shoots">What you shoot</label>
        <input id="shoots" name="shoots" required maxLength={600} placeholder="Street and travel, mostly at night" className={field} />
      </div>
      <div>
        <label className={label} htmlFor="cameras">Your cameras</label>
        <input id="cameras" name="cameras" required maxLength={300} placeholder="Fujifilm X100VI, iPhone 17 Pro" className={field} />
      </div>
      <div>
        <label className={label} htmlFor="photos">Photos you exported from Redlamp</label>
        <input id="photos" name="photos" type="file" required multiple accept="image/jpeg,image/png,image/webp" className={fileField} />
        <p className={hint}>One to three. An export carries its settings, which is how I see your edit. They&apos;re resized before sending.</p>
      </div>
      <div
        onDragOver={(event) => {
          event.preventDefault();
          setDropping(true);
        }}
        onDragLeave={() => setDropping(false)}
        onDrop={(event) => {
          event.preventDefault();
          setDropping(false);
          const name = event.dataTransfer.items[0]?.webkitGetAsEntry()?.name ?? "That file";
          droppedEdit(event).then((text) => take(text, name));
        }}
        className={`rounded-[10px] border border-dashed p-4 ${dropping ? "border-hairline-strong bg-wall-raised" : "border-hairline"}`}
      >
        <label className={label} htmlFor="sidecar">If your exports have no metadata</label>
        <p className={hint}>
          {sidecar
            ? `Using the edit from ${sidecar.name}.`
            : "Drop one photo's .redlamp file here from Finder. It's beside the raw, with the same name."}
        </p>
        <input
          id="sidecar"
          type="file"
          accept=".redlamp,.json"
          onChange={(event) => {
            const file = event.currentTarget.files?.[0];
            if (file) file.text().then((text) => take(text, file.name));
          }}
          className={`${fileField} mt-2`}
        />
      </div>
      <div className="md:col-span-2">
        <label className={label} htmlFor="change">What would you change first in Redlamp?</label>
        <textarea id="change" name="change" required maxLength={1500} rows={3} className={field} />
      </div>
      <div className="hidden" aria-hidden="true">
        <label htmlFor="website">Leave this empty</label>
        <input id="website" name="website" tabIndex={-1} autoComplete="off" />
      </div>
      <label className="flex items-start gap-3 text-[14px] leading-relaxed text-mute md:col-span-2">
        <input name="consent" type="checkbox" required className="mt-1 accent-ring" />
        <span>I agree to the ambassador terms and the privacy note above.</span>
      </label>
      <div className="flex flex-col gap-3 md:col-span-2 md:flex-row md:items-center">
        <button type="submit" disabled={state.kind === "sending"} className="button-primary inline-flex items-center justify-center rounded-pill px-6 py-3 text-[15px] font-semibold disabled:opacity-60">
          {state.kind === "sending" ? "Sending…" : "Apply"}
        </button>
        {state.kind === "error" ? (
          <p role="alert" className="text-[14px] text-filament">
            {state.message}
          </p>
        ) : null}
      </div>
    </form>
  );
}
