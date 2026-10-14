import type { NextConfig } from "next";
import { hostedFiles } from "./lib/hosted";
import { site } from "./lib/site";

/**
 * The site is static marketing. It takes no input, sets no cookies and has no API, so
 * the headers below are simply the safe defaults for something in that position.
 */
const securityHeaders = [
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
];

// Read when the site builds, so a change to the variables takes effect at the next deployment.
const hosted = hostedFiles();

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // Next writes its own AGENTS.md/CLAUDE.md on dev start; this repo doesn't want them.
  agentRules: false,
  // The header's star count refreshes hourly, so the blog's pages are rendered again on the
  // server, where they read the posts.
  outputFileTracingIncludes: { "/blog": ["./content/blog/**/*.md"], "/blog/**": ["./content/blog/**/*.md"] },
  async headers() {
    return [
      { source: "/:path*", headers: securityHeaders },
      // A hosted file is never cached, so deleting it withdraws it at once, and never indexed.
      ...hosted.map(({ source }) => ({
        source,
        headers: [
          { key: "Cache-Control", value: "no-store" },
          { key: "X-Robots-Tag", value: "noindex" },
        ],
      })),
    ];
  },
  // Files kept outside the repository (lib/hosted.ts), proxied rather than redirected, since the
  // release's check fetches them with curl, which doesn't follow redirects there.
  async rewrites() {
    return hosted;
  },
  // The update feed every installed copy checks (FEED in mise/tasks/release): the appcast
  // published with the latest release. Temporary, so clients don't cache it and the feed can
  // move without stranding them.
  async redirects() {
    return [
      {
        source: "/appcast.xml",
        destination: `${site.github}/releases/latest/download/appcast.xml`,
        permanent: false,
      },
    ];
  },
};

export default nextConfig;
