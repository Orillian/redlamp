import type { Metadata } from "next";
import { AmbassadorForm } from "@/components/sections/AmbassadorForm";
import { LinkButton } from "@/components/ui/Buttons";
import { ambassadors } from "@/content/ambassadors";
import { site } from "@/lib/site";

const title = "Become a Redlamp ambassador";
const description =
  "Help decide what Redlamp builds next, as one of its ten founding ambassadors, and have your edits shown, with your name, wherever Redlamp is seen.";

// Unlisted until the open call: not in the sitemap or the footer, and not indexed.
export const metadata: Metadata = {
  title: "Ambassadors",
  description,
  alternates: { canonical: "/ambassadors" },
  robots: { index: false, follow: false },
  openGraph: { type: "website", siteName: site.name, title, description, url: "/ambassadors", locale: "en_GB" },
  twitter: { card: "summary_large_image", title, description },
};

const link = "text-paper underline decoration-hairline-strong underline-offset-3 hover:decoration-paper";

export default function AmbassadorsPage() {
  const a = ambassadors;
  return (
    <section className="px-6 pt-16 pb-24">
      <div className="mx-auto max-w-6xl">
        <div className="max-w-3xl">
          <p className="eyebrow">Ambassadors</p>
          <h1 className="font-display mt-3 text-[clamp(2.2rem,5vw,3.4rem)] leading-[1.05] text-paper">{title}</h1>
          {a.intro.map((paragraph) => (
            <p key={paragraph} className="mt-5 text-[17px] leading-relaxed text-mute">
              {paragraph}
            </p>
          ))}
          <div className="mt-8">
            <LinkButton href="#apply">Apply with a photo you edited in Redlamp</LinkButton>
          </div>
        </div>

        <div className="mt-14 grid gap-4 md:grid-cols-2">
          {a.offer.map((item) => (
            <div key={item.title} className="surface p-6">
              <h2 className="font-display text-[20px] text-paper">{item.title}</h2>
              <p className="mt-2 text-[15px] leading-relaxed text-mute">{item.body}</p>
            </div>
          ))}
        </div>

        <div className="mt-16 grid gap-10 lg:grid-cols-2">
          <div>
            <h2 className="font-display text-[24px] leading-snug">What I ask</h2>
            <ul className="mt-4 flex flex-col gap-3 text-[15px] leading-relaxed text-mute">
              {a.asks.map((ask) => (
                <li key={ask} className="flex gap-3">
                  <span className="mt-[9px] h-1 w-1 shrink-0 rounded-full bg-mute" />
                  <span>{ask}</span>
                </li>
              ))}
            </ul>
            <p className="mt-5 text-[15px] leading-relaxed text-mute">{a.requirements}</p>
          </div>
          <div>
            <h2 className="font-display text-[24px] leading-snug">How it works</h2>
            <ol className="mt-4 flex flex-col gap-4">
              {a.steps.map((step, index) => (
                <li key={step.title} className="grid grid-cols-[28px_minmax(0,1fr)] gap-2">
                  <span className="font-display text-[15px] text-dim">{index + 1}</span>
                  <span>
                    <span className="block text-[15px] font-medium text-paper">{step.title}</span>
                    <span className="mt-1 block text-[15px] leading-relaxed text-mute">{step.body}</span>
                  </span>
                </li>
              ))}
            </ol>
          </div>
        </div>

        <div className="mt-16 max-w-3xl">
          <h2 className="font-display text-[24px] leading-snug">Questions</h2>
          <dl className="mt-4 flex flex-col gap-5">
            {a.questions.map((item) => (
              <div key={item.q}>
                <dt className="text-[15px] font-medium text-paper">{item.q}</dt>
                <dd className="mt-1 text-[15px] leading-relaxed text-mute">{item.a}</dd>
              </div>
            ))}
          </dl>
        </div>

        <div id="apply" className="scroll-mt-24 pt-16">
          <h2 className="font-display text-[clamp(1.9rem,4vw,2.6rem)] leading-[1.08] text-paper">Apply</h2>
          <p className="mt-4 max-w-3xl text-[17px] leading-relaxed text-mute">
            {`There are ${a.places} founding places. `}
            If you haven&apos;t tried Redlamp yet,{" "}
            <a href={`${site.github}/releases/latest`} className={link}>
              download it
            </a>{" "}
            and edit a photo first: your application is that photo, exported.
          </p>
          <div className="mt-6 grid gap-4 lg:grid-cols-2">
            <details className="surface p-5">
              <summary className="cursor-pointer text-[15px] text-paper">{a.terms.title}</summary>
              <div className="mt-4 flex flex-col gap-3 text-[14px] leading-relaxed text-mute">
                {a.terms.paragraphs.map((paragraph) => (
                  <p key={paragraph}>{paragraph}</p>
                ))}
              </div>
            </details>
            <details className="surface p-5">
              <summary className="cursor-pointer text-[15px] text-paper">Privacy: {a.privacy.title.toLowerCase()}</summary>
              <p className="mt-4 text-[14px] leading-relaxed text-mute">{a.privacy.text}</p>
              <p className="mt-3 text-[14px] leading-relaxed text-mute">
                Write to me at{" "}
                <a href={`mailto:${a.contact}`} className={link}>
                  {a.contact}
                </a>
                .
              </p>
            </details>
          </div>
          <div className="mt-6">
            <AmbassadorForm />
          </div>
        </div>
      </div>
    </section>
  );
}
