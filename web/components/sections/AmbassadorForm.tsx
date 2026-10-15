"use client";

import { type FormEvent, useState } from "react";

// The relay's limits (lib/ambassadors.ts): each photo under 1,000,000 bytes, all of them with the
// sidecar under 3,200,000.
const LONG_EDGE = 2048;
const PHOTO_BYTES = 950_000;

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

const field = "mt-1.5 w-full rounded-[10px] border border-hairline bg-wall px-3.5 py-2.5 text-[15px] text-paper placeholder:text-dim focus:border-hairline-strong focus:outline-none";
const label = "block text-[14px] font-medium text-paper";
const hint = "mt-1 text-[13px] text-dim";

export function AmbassadorForm() {
  const [state, setState] = useState<State>({ kind: "idle" });

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const photos = form.getAll("photos").filter((value): value is File => value instanceof File && value.size > 0);
    const sidecar = form.get("sidecar");
    if (photos.length === 0) return setState({ kind: "error", message: "Add a photo you edited in Redlamp." });
    if (photos.length > 3) return setState({ kind: "error", message: "Add at most three photos." });
    if (!(sidecar instanceof File) || sidecar.size === 0) {
      return setState({ kind: "error", message: "Add the .redlamp file of one of your photos." });
    }
    setState({ kind: "sending" });
    try {
      const sidecarText = await sidecar.text();
      let format: unknown;
      try {
        format = (JSON.parse(sidecarText) as Record<string, unknown>).format;
      } catch {
        format = undefined;
      }
      if (format !== "app.redlamp.edit") {
        throw new Error("That .redlamp file isn't one Redlamp wrote. It's the file beside your raw with the same name.");
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
          sidecar: { data: await base64(new Blob([sidecarText])) },
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
        <label className={label} htmlFor="photos">Photos you edited in Redlamp</label>
        <input id="photos" name="photos" type="file" required multiple accept="image/jpeg,image/png,image/webp" className={`${field} file:mr-3 file:rounded-pill file:border-0 file:bg-wall-raised file:px-3 file:py-1 file:text-paper`} />
        <p className={hint}>One to three, exported from Redlamp. They&apos;re resized before sending.</p>
      </div>
      <div>
        <label className={label} htmlFor="sidecar">The .redlamp file of one of them</label>
        <input id="sidecar" name="sidecar" type="file" required accept=".redlamp" className={`${field} file:mr-3 file:rounded-pill file:border-0 file:bg-wall-raised file:px-3 file:py-1 file:text-paper`} />
        <p className={hint}>It sits beside the raw, with the same name and .redlamp at the end. It holds your settings.</p>
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
