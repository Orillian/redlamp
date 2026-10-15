// The privacy policy (app/privacy), written from what the app and the site's routes do. When a flow
// changes, change the policy and its date in the same commit.

export const privacyUpdated = "2026-10-15";

/** Who receives personal data, each under its own privacy policy. */
export const recipients = [
  {
    name: "GitHub",
    policy: "https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement",
    what: "Reports and their attachments, which are public; camera bench results and ambassador applications, which are private; model and update downloads.",
  },
  {
    name: "Vercel",
    policy: "https://vercel.com/legal/privacy-policy",
    what: "Hosting redlamp.app and the services behind reports, the camera bench and applications; request logs; page-view counts; files the app downloads from redlamp.app.",
  },
  {
    name: "Hugging Face",
    policy: "https://huggingface.co/privacy",
    what: "Some of the AI model downloads.",
  },
  {
    name: "Google",
    policy: "https://policies.google.com/privacy",
    what: "The film on the home page, once you play it, from YouTube; email you send me, in Gmail.",
  },
  {
    name: "Cursor",
    policy: "https://cursor.com/privacy",
    what: "The AI agents that help me read and sort reports and applications.",
  },
  {
    name: "Discord",
    policy: "https://discord.com/privacy",
    what: "Redlamp's Discord, if you join it.",
  },
];
