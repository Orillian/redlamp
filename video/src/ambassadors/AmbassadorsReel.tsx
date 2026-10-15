import { AbsoluteFill, type CalculateMetadataFunction, getStaticFiles, Html5Audio, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { type CueSheet, grid } from "../kit/grid";
import { SafeZones } from "../kit/SafeZones";
import cueSheet from "./cues.json";

/**
 * The ambassadors reel (docs/plans/2026-10-15-ambassadors-promo.md): Redlamp's ambassador programme told as an
 * episode of the feature videos, every picture drawn by pixelkit. scripts/ambassadors-frames.py draws its frames
 * into public/ambassadors/frames/ and lists each hook's in frames.json: the 216 × 384 canvas in the reel's
 * margin, shown four times the size with nearest-neighbour scaling. scripts/ambassadors-score.py writes the score
 * beside them. Both are timed by cues.json, and the words are copy.json, beside this file.
 */
const sheet = cueSheet as unknown as CueSheet;
export const AMBASSADORS_FRAMES = grid(sheet).frames;

/** What scripts/ambassadors-frames.py wrote: each hook's file for every frame. */
export type AmbassadorsFrames = { fps: number; frames: Record<string, string[]> };

export type AmbassadorsReelProps = {
  /** A hook in copy.json, such as pick. */
  hook: string;
  /** The score in public/ambassadors/ that plays, without .wav. */
  score: string;
  /** The apps' safe zones over the frame, for review in Studio; never in a cut. */
  guides: boolean;
  /** Read from public/ambassadors/frames.json by withFrames. */
  manifest: AmbassadorsFrames | null;
};

export const withFrames: CalculateMetadataFunction<AmbassadorsReelProps> = async ({ props }) => {
  try {
    const response = await fetch(staticFile("ambassadors/frames.json"));
    return { props: { ...props, manifest: response.ok ? ((await response.json()) as AmbassadorsFrames) : null } };
  } catch {
    return { props: { ...props, manifest: null } };
  }
};

export function AmbassadorsReel({ hook, score, guides, manifest }: AmbassadorsReelProps) {
  const frame = useCurrentFrame();
  const audio = `ambassadors/${score}.wav`;
  const file = manifest?.frames[hook]?.[frame];
  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {file ? (
        <Img src={staticFile(`ambassadors/frames/${file}`)} style={{ width: "100%", height: "100%", imageRendering: "pixelated" }} />
      ) : (
        <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", color: "#7c7c7c", font: "500 30px Inter, sans-serif" }}>
          {`No frames for hook ${hook}: python3 scripts/ambassadors-frames.py`}
        </AbsoluteFill>
      )}
      {getStaticFiles().some((f) => f.name === audio) ? (
        <Html5Audio
          src={staticFile(audio)}
          volume={(f) => interpolate(f, [AMBASSADORS_FRAMES - 3, AMBASSADORS_FRAMES], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })}
        />
      ) : null}
      {guides ? <SafeZones /> : null}
    </AbsoluteFill>
  );
}
