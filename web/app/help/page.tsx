import type { Metadata } from "next";
import { contactEmail, site } from "@/lib/site";

const title = "Help and contact";
const description =
  "How to get help with Redlamp: Report a Bug and Send Feedback in the app, GitHub issues, Discord and email, what to put in a report, and answers to the questions people ask first.";

export const metadata: Metadata = {
  title: "Help",
  description,
  alternates: { canonical: "/help" },
  openGraph: { type: "website", siteName: site.name, title, description, url: "/help", locale: "en_GB" },
  twitter: { card: "summary_large_image", title, description },
};

const link = "text-paper underline decoration-hairline-strong underline-offset-3 hover:decoration-paper";
const code = "rounded-[4px] bg-paper/8 px-1 py-px font-mono text-[0.88em] text-ring";

function Code({ children }: { children: React.ReactNode }) {
  return <code className={code}>{children}</code>;
}

const ways = [
  {
    title: "Report a Bug or Send Feedback",
    body: (
      <>
        In Redlamp, choose Help › Report a Bug or Send Feedback…, with no GitHub account needed. Reports are public on
        GitHub, and you see everything a report holds before you send it. Help › Your Reports follows the replies.
      </>
    ),
  },
  {
    title: "GitHub issues",
    body: (
      <>
        With a GitHub account, search the issues, follow one or open your own on{" "}
        <a href={`${site.github}/issues`} className={link}>
          Redlamp&apos;s repository
        </a>
        .
      </>
    ),
  },
  {
    title: "Discord",
    body: (
      <>
        Ask a question, share an edit or talk to other photographers using Redlamp on{" "}
        <a href={site.discord} className={link}>
          Redlamp&apos;s Discord
        </a>
        .
      </>
    ),
  },
  {
    title: "Email",
    body: (
      <>
        For anything you&apos;d rather not post in public, such as a privacy request, write to me at{" "}
        <a href={`mailto:${contactEmail}`} className={link}>
          {contactEmail}
        </a>
        .
      </>
    ),
  },
];

const include = [
  "What you did, what you expected, and what happened instead.",
  "The steps that make it happen, and whether it happens every time.",
  "A screenshot, if it shows the problem. Redlamp offers one of its window.",
  "The photo's details and the Mac and the Redlamp build, which a report includes unless you switch them off: they tell me the camera, the version of Redlamp, macOS and the Mac.",
  "For a photo that looks wrong, what you compared it with, such as the camera's own JPEG or another app.",
  "For a crash or a hang, the report Redlamp offers at its next launch, or the one in Help › Your Reports: it includes what happened.",
];

const questions = [
  {
    q: "What do I need to run Redlamp?",
    a: <>A Mac with Apple Silicon, running macOS 26 or later.</>,
  },
  {
    q: "Does Redlamp support my camera?",
    a: (
      <>
        Redlamp reads raw files with LibRaw, which reads the formats of more than a thousand cameras, and it opens JPEG,
        HEIC, TIFF and PNG files too. The{" "}
        <a href="/cameras" className={link}>
          cameras page
        </a>{" "}
        lists the cameras Redlamp&apos;s tests verify and those photographers have tested. To test yours, choose Help ›{" "}
        <a href="/cameras/test" className={link}>
          Test Your Camera…
        </a>
      </>
    ),
  },
  {
    q: "Where are my edits kept?",
    a: (
      <>
        Next to each photo, in a sidecar file with the photo&apos;s name, such as <Code>IMG_1234.ARW.redlamp</Code>.
        Edits are saved as you make them, and Redlamp never changes the original: not when you edit it, and not when you
        export it. Keep each sidecar with its photo when you move or back up your photos. Your recipes are in{" "}
        <Code>~/Library/Application Support/Redlamp/Recipes</Code>.
      </>
    ),
  },
  {
    q: "Does Redlamp upload my photos?",
    a: (
      <>
        No. Redlamp develops your photos on your Mac, AI masks and Generative Remove included. The{" "}
        <a href="/privacy" className={link}>
          privacy policy
        </a>{" "}
        says what the app does send, and when.
      </>
    ),
  },
  {
    q: "How do I update Redlamp?",
    a: (
      <>
        Redlamp keeps itself up to date, however you installed it: choose Redlamp › Check for Updates… at any time, and
        turn automatic checks on or off in Settings › About. Move Redlamp to Applications before you open it, since a copy
        opened from Downloads or the disk image can&apos;t update itself. With Homebrew,{" "}
        <Code>brew upgrade --cask redlamp</Code> updates it too. A build from source never checks: pull the latest source
        and build it again.
      </>
    ),
  },
];

const kept = [
  {
    path: "~/Library/Application Support/Redlamp",
    what: "your recipes and looks, the AI models you've downloaded (which can take several gigabytes; Settings › Models removes them), the reports you've sent and lens profiles",
  },
  { path: "~/Library/Caches/app.redlamp", what: "thumbnails and other files Redlamp can make again" },
  { path: "~/Library/Caches/Redlamp", what: "What's New, kept for when you're offline" },
  { path: "~/Library/Preferences/app.redlamp.mac.plist", what: "your settings" },
];

export default function HelpPage() {
  return (
    <section className="px-6 pt-16 pb-24">
      <div className="mx-auto max-w-6xl">
        <div className="max-w-3xl">
          <p className="eyebrow">Help</p>
          <h1 className="font-display mt-3 text-[clamp(2.2rem,5vw,3.4rem)] leading-[1.05] text-paper">{title}</h1>
          <p className="mt-5 text-[17px] leading-relaxed text-mute">
            Redlamp is made by one person, and I read every report. Here&apos;s how to reach me, what makes a report easy
            to act on, and answers to the questions people ask first.
          </p>
        </div>

        <div className="mt-14 grid gap-4 md:grid-cols-2">
          {ways.map((way) => (
            <div key={way.title} className="surface p-6">
              <h2 className="font-display text-[20px] text-paper">{way.title}</h2>
              <p className="mt-2 text-[15px] leading-relaxed text-mute">{way.body}</p>
            </div>
          ))}
        </div>

        <div className="mt-16 grid gap-10 lg:grid-cols-2">
          <div>
            <h2 className="font-display text-[24px] leading-snug">What to put in a report</h2>
            <ul className="mt-4 flex flex-col gap-3 text-[15px] leading-relaxed text-mute">
              {include.map((item) => (
                <li key={item} className="flex gap-3">
                  <span className="mt-[9px] h-1 w-1 shrink-0 rounded-full bg-mute" />
                  <span>{item}</span>
                </li>
              ))}
            </ul>
          </div>
          <div>
            <h2 className="font-display text-[24px] leading-snug">Before you send it</h2>
            <p className="mt-4 text-[15px] leading-relaxed text-mute">
              Reports are posted in Redlamp&apos;s public issues on GitHub, where anyone can read them. File names become
              Photo A, Photo B unless you include them, and paths, folder names, location and serial numbers are never
              included. Add your GitHub username if you&apos;d like to be mentioned and notified of replies; without one,
              Help › Your Reports lists what you&apos;ve sent, with a link to each report.
            </p>
            <p className="mt-4 text-[15px] leading-relaxed text-mute">
              A photo Redlamp can&apos;t open shows a button to report it, which fills in what it knows. Reports can&apos;t
              carry raw files: if a problem needs one, I&apos;ll ask on the issue.
            </p>
          </div>
        </div>

        <div className="mt-16 max-w-3xl">
          <h2 className="font-display text-[24px] leading-snug">Questions</h2>
          <dl className="mt-4 flex flex-col gap-5">
            {questions.map((item) => (
              <div key={item.q}>
                <dt className="text-[15px] font-medium text-paper">{item.q}</dt>
                <dd className="mt-1 text-[15px] leading-relaxed text-mute">{item.a}</dd>
              </div>
            ))}
            <div>
              <dt className="text-[15px] font-medium text-paper">How do I uninstall Redlamp?</dt>
              <dd className="mt-1 text-[15px] leading-relaxed text-mute">
                <p>
                  Quit Redlamp and move it from Applications to the Bin, or, if you installed it with Homebrew, run{" "}
                  <Code>brew uninstall --cask redlamp</Code>. Redlamp keeps these on your Mac, which you can delete
                  afterwards; in Finder, choose Go › Go to Folder… and paste a path:
                </p>
                <ul className="mt-3 flex flex-col gap-2">
                  {kept.map((item) => (
                    <li key={item.path} className="flex gap-3">
                      <span className="mt-[9px] h-1 w-1 shrink-0 rounded-full bg-mute" />
                      <span>
                        <Code>{item.path}</Code>: {item.what}.
                      </span>
                    </li>
                  ))}
                </ul>
                <p className="mt-3">
                  <Code>brew uninstall --zap --cask redlamp</Code> also removes the Application Support folder and your
                  settings. Your edits are in the sidecars next to your photos, and uninstalling leaves them alone: delete
                  them only if you no longer want the edits.
                </p>
              </dd>
            </div>
          </dl>
        </div>

        <div className="mt-16 max-w-3xl border-t border-hairline pt-8">
          <h2 className="font-display text-[24px] leading-snug">Privacy</h2>
          <p className="mt-4 text-[15px] leading-relaxed text-mute">
            What Redlamp and this site send, who receives it, and how to ask for a copy or for it to be deleted, a report
            included, are in the{" "}
            <a href="/privacy" className={link}>
              privacy policy
            </a>
            .
          </p>
        </div>
      </div>
    </section>
  );
}
