import type { Metadata } from "next";
import { privacyUpdated, recipients } from "@/content/privacy";
import { formatDate } from "@/lib/blog";
import { contactEmail, site } from "@/lib/site";

const title = "Privacy policy";
const description =
  "What Redlamp's apps and redlamp.app send, who receives it, how long it's kept and what you can ask. Your photos and edits stay on your Mac.";

export const metadata: Metadata = {
  title: "Privacy",
  description,
  alternates: { canonical: "/privacy" },
  openGraph: { type: "website", siteName: site.name, title, description, url: "/privacy", locale: "en_GB" },
  twitter: { card: "summary_large_image", title, description },
};

const sections = [
  ["in-short", "In short"],
  ["who", "Who's responsible"],
  ["on-your-mac", "What stays on your Mac"],
  ["reports", "Report a Bug and Send Feedback"],
  ["camera-bench", "Test Your Camera"],
  ["downloads", "Downloads and update checks"],
  ["website", "This website"],
  ["recipients", "Who receives it"],
  ["transfers", "Transfers outside the UK and the EU"],
  ["retention", "How long it's kept"],
  ["rights", "Your rights"],
  ["children", "Children"],
  ["changes", "Changes to this policy"],
  ["contact", "Contact"],
];

const email = <a href={`mailto:${contactEmail}`}>{contactEmail}</a>;
const policy = (name: string) => recipients.find((recipient) => recipient.name === name)?.policy;

export default function PrivacyPage() {
  return (
    <article className="px-6 pt-14 pb-24">
      <header className="mx-auto max-w-2xl">
        <p className="eyebrow">Privacy</p>
        <h1 className="font-display mt-4 text-[clamp(2.2rem,5vw,3.4rem)] leading-[1.05] text-paper">{title}</h1>
        <p className="mt-5 text-[19px] leading-relaxed text-mute">
          Redlamp develops your photos on your Mac. This page says what Redlamp&apos;s apps and this website send, who
          receives it, how long it&apos;s kept, and what you can ask of me.
        </p>
        <p className="mt-6 text-[14px] text-dim">
          Last updated <time dateTime={privacyUpdated}>{formatDate(privacyUpdated)}</time> · Pedro Gomes
        </p>
        <nav aria-label="On this page" className="mt-8 border-t border-hairline pt-6">
          <ol className="grid gap-x-8 gap-y-1.5 text-[14px] sm:grid-cols-2">
            {sections.map(([id, label]) => (
              <li key={id}>
                <a href={`#${id}`} className="text-mute transition-colors hover:text-paper">
                  {label}
                </a>
              </li>
            ))}
          </ol>
        </nav>
      </header>

      <div className="post mt-12">
        <h2 id="in-short">In short</h2>
        <ul>
          <li>
            <strong>Your photos and edits stay on your Mac.</strong> Redlamp develops, masks and exports them there, its
            AI included, and never uploads them.
          </li>
          <li>
            <strong>The app has no account, analytics, advertising or tracking.</strong> It sends something only when you
            ask it to, such as a report, camera bench results or a model download, and when it checks for updates and
            What&apos;s New, which send nothing about you.
          </li>
          <li>
            <strong>Reports you send from the app are public.</strong> They&apos;re posted as GitHub issues, where anyone
            can read them.
          </li>
          <li>
            <strong>This website sets no cookies.</strong> It counts page views with Vercel Web Analytics, which
            doesn&apos;t identify you.
          </li>
        </ul>

        <h2 id="who">Who&apos;s responsible</h2>
        <p>
          Redlamp is made by Pedro Gomes, who is responsible for the personal data this policy describes (its controller,
          in data protection law). Write to me at {email} about anything on this page.
        </p>
        <p>
          The policy covers Redlamp for Mac, whether downloaded from GitHub, installed with Homebrew or built from source;
          the <code>redlamp</code> command-line tool that comes with it; and redlamp.app.
        </p>

        <h2 id="on-your-mac">What stays on your Mac</h2>
        <p>
          Redlamp opens, develops and exports your photos on your Mac. Edits are saved next to each photo, in a sidecar
          file such as <code>IMG_1234.ARW.redlamp</code>, and your recipes, looks, settings, thumbnails and downloaded
          models are kept in your user Library. AI masks and Generative Remove run on the Mac, with models downloaded to
          it: no photo is sent to a server to be processed. The command-line tool works the same way.
        </p>
        <p>
          Photos leave your Mac only when you send them: screenshots you attach to a report, and photos you send with an
          ambassador application. If you keep your photos in iCloud Drive or another synced folder, that service syncs
          their sidecars too, under its own terms.
        </p>

        <h2 id="reports">Report a Bug and Send Feedback</h2>
        <p>
          <strong>Reports are public.</strong> What you send with Report a Bug or Send Feedback is posted on GitHub, as an
          issue in <a href={`${site.github}/issues`}>Redlamp&apos;s repository</a>, where anyone can read it, with or
          without a GitHub account. Its screenshots and diagnostics file are stored in another public repository,{" "}
          <a href="https://github.com/pdcgomes/redlamp-feedback">pdcgomes/redlamp-feedback</a>. Before you send a report,
          the app shows you everything it holds, as it will appear on GitHub.
        </p>
        <p>A report holds:</p>
        <ul>
          <li>
            what you write: its title, what happened, what you expected, the steps and how often it happens, with the kind
            of report and the part of Redlamp it&apos;s about;
          </li>
          <li>
            the screenshots you include: Redlamp&apos;s window, which shows the photo you&apos;re editing, or images you
            paste, with their metadata removed;
          </li>
          <li>
            the details you leave switched on: the photo&apos;s camera, lens, format, edit and history; what you did in
            the last 15 minutes and the editor&apos;s state; Redlamp&apos;s log; and the Mac and the build (Redlamp&apos;s
            version, macOS, the Mac&apos;s model, chip, memory, graphics and displays, its language and region, and the AI
            models you&apos;ve downloaded);
          </li>
          <li>for a crash or a hang, what happened, with the threads&apos; stacks, and what you did in the 15 minutes before it;</li>
          <li>
            your GitHub username, if you give it, so you&apos;re mentioned and notified of replies. This links the report
            to your GitHub account.
          </li>
        </ul>
        <p>
          File names become Photo A, Photo B unless you choose to include them, and paths, folder names, location and
          serial numbers are never included. The app sends the report to redlamp.app, which passes it to GitHub as the
          Redlamp Feedback GitHub App, so it isn&apos;t posted under your name, and keeps nothing of it. A report that
          can&apos;t be sent waits on your Mac and goes the next time Redlamp opens. If redlamp.app can&apos;t take it, the
          app offers to open GitHub&apos;s new-issue page instead; an issue you file there is posted from your own GitHub
          account, under GitHub&apos;s terms.
        </p>
        <p>
          I use reports to fix bugs, answer questions and decide what to build, and I answer on the issue. The legal basis
          is your consent, which you give by pressing Send after seeing the report, and which you can withdraw by asking me
          to take it down (see <a href="#rights">Your rights</a>). I use AI agents in Cursor to help me read, sort and fix
          reports; I make every decision myself.
        </p>
        <h3>On your Mac</h3>
        <p>
          Redlamp keeps the reports you&apos;ve sent, your drafts, any reports waiting to be sent, and a journal of recent
          activity that describes a crash, in <code>~/Library/Application Support/Redlamp/Feedback</code>. When Redlamp
          notices a crash or a hang, it offers to report it; one you don&apos;t report stays in Help › Your Reports for 30
          days. Nothing about a crash is sent unless you send it.
        </p>
        <p>
          Your Reports checks your reports for replies by sending their issue numbers to redlamp.app, which asks GitHub.
          Turning off Check for replies and changes, in Your Reports, stops it.
        </p>

        <h2 id="camera-bench">Test Your Camera</h2>
        <p>
          The camera bench (Help › Test Your Camera…) checks how your camera&apos;s raw files decode, on your Mac. When you
          press Send Results, it sends the measurements, which What&apos;s Sent shows you first, to redlamp.app. They&apos;re
          kept in a private GitHub repository with the day they arrived and the app&apos;s version, and without your IP
          address.
        </p>
        <p>
          Results hold, for each photo, the camera, its mode, firmware and lens, the exposure settings and the
          camera&apos;s white balance, the decode&apos;s measurements, each check&apos;s result, timings, and a fingerprint
          (SHA-256) of the file, so that a photo sent twice counts once. For the whole report, they hold the versions of
          Redlamp and its decoder, the macOS version, the Mac&apos;s chip, your answers and notes, a name to credit if you
          give one, and a random contributor ID. They never hold pixels, file names, paths, location, serial numbers, owner
          fields or capture times. The contributor ID is made on your Mac, only counts contributors, and is replaced when
          you choose Reset Contributor ID.
        </p>
        <p>
          The <a href="/cameras">cameras page</a> publishes what everyone&apos;s results add up to for each camera mode,
          without contributor IDs, file fingerprints or names. I use the results to learn which cameras Redlamp handles
          well and what to fix; the legal basis is your consent, given when you send them. If I start crediting
          contributors by name, I&apos;ll say so here first.
        </p>

        <h2 id="downloads">Downloads and update checks</h2>
        <p>
          These send nothing about you, your Mac or your photos. Like any request on the internet, each carries your IP
          address and the app&apos;s name and version, which the server receives in order to answer it.
        </p>
        <ul>
          <li>
            <strong>AI models</strong> download only when you choose, after Redlamp tells you their size, from
            Redlamp&apos;s releases on GitHub and from Hugging Face.
          </li>
          <li>
            <strong>What&apos;s New:</strong> on the first launch of each new version, and at most once a day after that,
            Redlamp asks redlamp.app for each release&apos;s highlights. The whole list comes down, and the app picks what
            its version has. Settings › About turns this off.
          </li>
          <li>
            <strong>Updates:</strong> a copy downloaded from GitHub or installed with Homebrew checks for updates with
            Sparkle. On its second launch it asks whether to check automatically, and Settings › About turns automatic
            checks on or off. A check asks redlamp.app for the update feed, which comes from GitHub, as do the updates.
            Sparkle&apos;s system profile is switched off, so no details of your Mac are sent. Builds from source never
            check.
          </li>
          <li>
            <strong>Optional features</strong> that need files from redlamp.app download them when you turn them on.
          </li>
          <li>
            <strong>Links</strong> in the app, such as those to GitHub, raw.pixls.us or a licence, open in your browser.
          </li>
        </ul>
        <p>The legal basis is my legitimate interest in providing the features you use and keeping Redlamp up to date.</p>

        <h2 id="website">This website</h2>
        <p>
          <strong>Hosting.</strong> Vercel hosts redlamp.app and runs the services behind the app&apos;s reports, the
          camera bench and ambassador applications. As with any website, Vercel receives your IP address, your
          browser&apos;s details and the address of each page you ask for. The request logs I can see are kept for at
          most 30 days; Vercel&apos;s own use of them is set out in its privacy policy. The legal basis is my legitimate
          interest in running the site and keeping it secure.
        </p>
        <p>
          <strong>Page views.</strong> <a href="https://vercel.com/docs/analytics/privacy-policy">Vercel Web Analytics</a>{" "}
          counts page views: the page, the page you came from, your country, region and city as worked out from your IP
          address, your browser, operating system and kind of device, and the time. It uses no cookies. Vercel tells
          visits apart with a hash of the request, which it discards after 24 hours, and shows me only totals. The legal
          basis is my legitimate interest in knowing which pages are read.
        </p>
        <p>
          <strong>Cookies.</strong> The site sets no cookies. The animation that invites you to star Redlamp on GitHub
          notes in your browser&apos;s session storage that it has played, so that it doesn&apos;t play again; the note
          never leaves your browser, and is cleared when you close the tab.
        </p>
        <p>
          <strong>The film.</strong> The film on the home page loads from YouTube, in its privacy-enhanced mode, only when
          you press play; until then the page makes no request to YouTube. Once it plays, Google receives your IP address
          and may store data in your browser, under <a href={policy("Google")}>Google&apos;s privacy policy</a>.
        </p>
        <p>
          <strong>Ambassador applications.</strong> If you apply to be an ambassador, what you send (your name, email
          address, links to your work, what you shoot, your cameras, what you&apos;d change first, and up to three photos
          you exported from Redlamp with their edit) is stored in a private GitHub repository that only I can access,
          passing through Vercel on the way. I use it only to consider your application and to reply, with the help of AI
          agents in Cursor to read and sort applications; I make every decision myself. The legal basis is taking the
          steps you ask for before we agree the ambassador terms. If you&apos;re not accepted, I delete your application
          within six months. If you are, I keep your contact details for as long as you&apos;re an ambassador, and delete
          them within six months after.
        </p>
        <p>
          <strong>Email and Discord.</strong> If you write to me, your email is kept in my Gmail account, with Google, for
          as long as I need it to help you and follow up, and I delete it when you ask; the legal basis is my legitimate
          interest in answering you. If you join <a href={site.discord}>Redlamp&apos;s Discord</a>, what you post there is
          visible to its members, under <a href={policy("Discord")}>Discord&apos;s privacy policy</a>.
        </p>

        <h2 id="recipients">Who receives it</h2>
        <p>
          I don&apos;t sell personal data, and none of it is used for advertising. These companies receive it, each under
          its own privacy policy:
        </p>
        <table>
          <thead>
            <tr>
              <th>Company</th>
              <th>What for</th>
            </tr>
          </thead>
          <tbody>
            {recipients.map((recipient) => (
              <tr key={recipient.name}>
                <td className="whitespace-nowrap">
                  <a href={recipient.policy}>{recipient.name}</a>
                </td>
                <td>{recipient.what}</td>
              </tr>
            ))}
          </tbody>
        </table>

        <h2 id="transfers">Transfers outside the UK and the EU</h2>
        <p>
          GitHub, Vercel, Google, Cursor, Hugging Face and Discord are based in the United States, so what they receive
          may be stored and processed there. GitHub and Vercel take part in the EU–US Data Privacy Framework and its UK
          Extension, and also rely on the European Commission&apos;s standard contractual clauses; the others describe the
          safeguards they use in their privacy policies. Reports on GitHub are public, so they can be read from anywhere.
        </p>

        <h2 id="retention">How long it&apos;s kept</h2>
        <ul>
          <li>
            <strong>Reports</strong> stay public on GitHub until they&apos;re taken down, and on your Mac until you remove
            them from Your Reports. A crash or a hang you don&apos;t report is listed for 30 days.
          </li>
          <li>
            <strong>Camera bench results</strong> are kept for as long as they inform the cameras page.
          </li>
          <li>
            <strong>Ambassador applications</strong> are deleted within six months of a decision not to accept them, and an
            ambassador&apos;s contact details within six months of the end of their term.
          </li>
          <li>
            <strong>Request logs</strong> are kept for at most 30 days, and <strong>page-view totals</strong>, which
            identify no one, for at most 24 months.
          </li>
          <li>
            <strong>Email</strong> is kept for as long as it&apos;s needed to help you.
          </li>
        </ul>

        <h2 id="rights">Your rights</h2>
        <p>
          Under the UK GDPR and the EU&apos;s GDPR, you can ask me for a copy of the personal data I hold about you, and
          ask me to correct it, to delete it, to restrict or stop using it, or to give it to you in a form you can take
          elsewhere. Where I rely on your consent, you can withdraw it at any time; that doesn&apos;t undo what was done
          before. Write to me at {email}, and I&apos;ll answer within a month.
        </p>
        <p>
          <strong>Taking a report down.</strong> Send me its issue number or link. I&apos;ll delete the issue and its
          screenshots and diagnostics file, remove those files from the attachments repository&apos;s history, and ask
          GitHub to clear any copies in its caches. While a report was public, others could copy it, such as services that
          archive public GitHub activity; I can&apos;t recall those copies.
        </p>
        <p>
          <strong>Camera bench results.</strong> Send me the contributor ID shown in What&apos;s Sent, and I&apos;ll delete
          every result sent with it.
        </p>
        <p>
          <strong>Complaints.</strong> If you&apos;re unhappy with how I&apos;ve handled your data, please tell me first,
          so that I can put it right. You also have the right to complain to a data protection authority: in the UK, the{" "}
          <a href="https://ico.org.uk/make-a-complaint/">Information Commissioner&apos;s Office</a>; in the EU,{" "}
          <a href="https://www.edpb.europa.eu/about-edpb/about-edpb/members_en">the authority</a> in the country where you
          live or work, or where you think the problem happened.
        </p>

        <h2 id="children">Children</h2>
        <p>
          Redlamp isn&apos;t directed at children, and I don&apos;t knowingly collect personal data from them. If
          you&apos;re under 16, ask a parent or guardian before you send a report or an application. If you think a child
          has sent me personal data, write to me and I&apos;ll delete it.
        </p>

        <h2 id="changes">Changes to this policy</h2>
        <p>
          When this policy changes, I&apos;ll update this page and the date at the top. When a change affects what&apos;s
          collected or who receives it, I&apos;ll also say so on the <a href="/blog">blog</a>. Every earlier version is
          kept in{" "}
          <a href={`${site.github}/commits/main/web/app/privacy/page.tsx`}>the page&apos;s history on GitHub</a>.
        </p>

        <h2 id="contact">Contact</h2>
        <p>
          Pedro Gomes, who makes Redlamp: {email}. For help with the app, see <a href="/help">Help and contact</a>.
        </p>
      </div>
    </article>
  );
}
