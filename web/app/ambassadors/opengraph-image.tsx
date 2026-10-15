import { readFile } from "node:fs/promises";
import path from "node:path";
import { ImageResponse } from "next/og";
import { ambassadors } from "@/content/ambassadors";

export const alt = "Become a Redlamp ambassador. Ten founding places for photographers. Help decide what Redlamp builds next, and have your edits shown with your name.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function OpenGraphImage() {
  const icon = await readFile(path.join(process.cwd(), "public", "synced", "brand/images/app-icon.png"));
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          gap: 36,
          padding: "0 96px",
          background:
            "radial-gradient(70% 80% at 20% 30%, rgba(224,64,46,0.28), rgba(224,64,46,0.05) 55%, rgba(10,7,7,0) 80%), #0a0707",
          color: "#f3eee8",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 28 }}>
          <img src={`data:image/png;base64,${icon.toString("base64")}`} width={120} height={120} alt="" />
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            <div style={{ display: "flex", fontSize: 60, fontWeight: 600, letterSpacing: -1.2 }}>Become a Redlamp ambassador</div>
            <div style={{ display: "flex", fontSize: 30, color: "rgba(243,238,232,0.62)" }}>
              {`${ambassadors.places} founding places for photographers`}
            </div>
          </div>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 14, fontSize: 30 }}>
          {["Help decide what Redlamp builds next", "Your edits shown, with your name"].map((line) => (
            <div key={line} style={{ display: "flex", gap: 16, alignItems: "center" }}>
              <div style={{ display: "flex", width: 8, height: 8, borderRadius: 4, background: "#d9d0cb" }} />
              <span>{line}</span>
            </div>
          ))}
        </div>
        <div style={{ display: "flex", fontSize: 24, color: "rgba(243,238,232,0.45)" }}>redlamp.app/join</div>
      </div>
    ),
    size,
  );
}
