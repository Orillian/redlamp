import { ambassadorsConfig, fileApplication, limits, Rejection, validate } from "@/lib/ambassadors";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

function reply(status: number, body: object): Response {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

/** Files an application to the ambassador programme in its private repository (see lib/ambassadors.ts). */
export async function POST(request: Request): Promise<Response> {
  const config = ambassadorsConfig(process.env);
  if (!config) return reply(503, { error: "Applications aren't open right now. Please try again later." });
  if (Number(request.headers.get("content-length") ?? 0) > limits.totalBytes * 1.4 + 20_000) {
    return reply(413, { error: "The photos are too large together" });
  }
  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return reply(400, { error: "The application isn't JSON" });
  }
  try {
    const application = validate(payload);
    // Bots that fill in the hidden field are told it worked, and nothing is filed.
    if (application.spam) return reply(201, { received: true });
    await fileApplication(config, application);
    return reply(201, { received: true });
  } catch (error) {
    if (error instanceof Rejection) return reply(error.status, { error: error.message });
    console.error("[ambassadors]", error instanceof Error ? error.message : error);
    return reply(502, { error: "Your application didn't go through. Please try again in a few minutes." });
  }
}
