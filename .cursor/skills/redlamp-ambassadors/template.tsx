import {
  BarChart,
  Button,
  CollapsibleSection,
  Divider,
  Grid,
  H1,
  H2,
  H3,
  Link,
  Pill,
  Row,
  Spacer,
  Stack,
  Stat,
  Table,
  Text,
  useCanvasAction,
  useCanvasState,
  useEffect,
  useHostTheme,
  useState,
} from "cursor/canvas";
import type { ChartSeries, SetCanvasState, StatTone } from "cursor/canvas";

// The ambassadors room (.cursor/skills/redlamp-ambassadors/SKILL.md): a workstream canvas
// (.cursor/skills/workstream-canvas/SKILL.md) grown into a room, as the press room did. Edit only
// `workstream` and `room`; room.py writes the APPLICATIONS block. An empty list hides its tab.

type StepStatus = "done" | "in progress" | "not started" | "blocked" | "dropped";

interface Workstream {
  title: string;
  /** What the workstream is for, in a sentence or two. */
  goal: string;
  /** Where it stands now, in a sentence or two. */
  status: string;
  /** When this canvas was last brought up to date (ISO with the time zone), and the last commit it reflects. */
  updated: string;
  lastCommit?: string;
  /** Headline numbers beyond the two the canvas counts itself (steps done, items waiting on the owner). */
  stats: { value: string; label: string; tone?: StatTone }[];
  /**
   * What only the owner can do: say exactly how, and what it unblocks; `blocking` when work waits on it.
   * Once it's done, keep the item: `done: true`, with `detail` starting "Done:" and what came of it.
   */
  needsYou: { id: string; title: string; detail: string; unblocks: string; blocking: boolean; done: boolean; command?: string }[];
  /** Unblocked work the agent can start next. */
  ready: { title: string; detail: string }[];
  /** Work that waits, each naming what it waits on. */
  blocked: { title: string; detail: string; blockedBy: string }[];
  /**
   * The plan's steps, in order: with a plan, one per todo, with the todo's ID (SKILL.md, "A plan's
   * todos are its steps"). `ref`: a tracker ID, an issue (#n) or a commit.
   */
  plan: { id: string; step: string; detail: string; doneWhen: string; status: StepStatus; ref?: string; note?: string }[];
  /** Newest first. Each entry says what happened, what was found and what's queued next. `at`: ISO with the time zone. */
  log: { at: string; text: string }[];
  /** Appended as they happen; a reversed decision is a new row. `by`: Owner, Measured or Default. */
  decisions: { date: string; decision: string; why: string; by: "Owner" | "Measured" | "Default" }[];
  /** Before and after, or any measured comparison: label units and say what it's measured against. */
  measurements: { title: string; caption: string; categories: string[]; series: ChartSeries[]; suffix?: string; horizontal?: boolean }[];
  /** Plans, notes, tracker rows: repository paths or issue links. */
  links: { label: string; target: string }[];
}

const workstream: Workstream = {
  title: "Redlamp ambassadors",
  goal: "A founding cohort of photographers who help decide what Redlamp builds next and whose edits made in Redlamp are shown, credited, wherever Redlamp is seen.",
  status: "Set up from the template; room.py sync fills in the applications.",
  updated: "2026-10-15T08:00:00+01:00",
  stats: [],
  needsYou: [],
  ready: [],
  blocked: [],
  plan: [],
  log: [{ at: "2026-10-15T08:00:00+01:00", text: "The room was made from its template." }],
  decisions: [],
  measurements: [],
  links: [{ label: "Programme", target: "~/src/redlamp-social/plans/2026-10-15-ambassadors.md" }],
};

// ---------------------------------------------------------------- the room (.cursor/skills/redlamp-ambassadors/SKILL.md)
// Agents edit `room`; room.py writes the APPLICATIONS block. The owner's marks (Needs you, each
// application's triage, each candidate's state) are kept in the canvas's .canvas.data.json.

type Score = 1 | 2 | 3;

interface Scores {
  photography: Score;
  sharing: Score;
  fit: Score;
  spread: Score;
  engagement: Score;
  note?: string;
}

/** An application, as room.py reads it from the private repository. */
interface Application {
  number: number;
  created: string;
  state: "open" | "closed";
  name: string;
  email: string;
  links: string[];
  shoots: string;
  cameras: string;
  change: string;
  url: string;
  /** Small JPEGs of the photos as data URIs, from room.py's cache. */
  thumbs: string[];
}

interface Candidate {
  id: string;
  name: string;
  /** Where they share their work. */
  url: string;
  platform: string;
  wave: "0" | "1";
  niche: string;
  why: string;
  /** Where they were found. */
  source: string;
  scores?: Scores;
  /** The invitation, drafted in the owner's voice, for him to send. */
  invitation: string;
}

interface Ambassador {
  name: string;
  handle: string;
  url: string;
  joined: string;
  termEnds: string;
  founding: boolean;
  termsAgreed: boolean;
  edits: number;
  showcases: number;
}

interface Pick {
  quarter: string;
  shortlist: { id: string; issue: number; title: string }[];
  closes?: string;
  result?: string;
}

/** Words the owner posts or sends himself: announcements, templates, posts. */
interface Draft {
  id: string;
  label: string;
  /** Where it goes, and when. */
  where: string;
  text: string;
}

interface Room {
  /** The agent's reading of each application on the rubric, by issue number. */
  scores: Record<string, Scores>;
  /** Replies drafted for applications, by issue number, while Gmail isn't connected. */
  replies: Record<string, string>;
  candidates: Candidate[];
  cohort: Ambassador[];
  picks: Pick[];
  drafts: Draft[];
}

const room: Room = {
  scores: {},
  replies: {},
  candidates: [],
  cohort: [],
  picks: [],
  drafts: [],
};

const applications: Application[] = /*APPLICATIONS:BEGIN*/ [] /*APPLICATIONS:END*/;

// ---------------------------------------------------------------- rendering (keys sit on wrapper divs)

const TABS = ["Overview", "Applications", "Candidates", "Drafts", "Ambassadors", "Picks", "Plan", "Decisions", "Log", "Measurements"] as const;
type Tab = (typeof TABS)[number];

const STEP_LABEL: Record<StepStatus, string> = {
  done: "Done",
  "in progress": "In progress",
  "not started": "Not started",
  blocked: "Blocked",
  dropped: "Dropped",
};

type DotState = StepStatus | "waiting" | "blocking";

/**
 * The owner's answers to Needs you, by item ID, kept in the canvas's `.canvas.data.json` under
 * `needsYou`; the agent folds them into `workstream` at its next update (SKILL.md).
 */
type Mark = { state: "done" | "skipped" | "asked"; at: string };
type Marks = Record<string, Mark>;
type SetMarks = SetCanvasState<Marks>;

/** Done or skipped, by the agent's record or the owner's mark. */
function settled(item: Workstream["needsYou"][number], marks: Marks): boolean {
  const state = marks[item.id]?.state;
  return item.done || state === "done" || state === "skipped";
}

function useNow(intervalMs = 30000): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), intervalMs);
    return () => clearInterval(timer);
  }, [intervalMs]);
  return now;
}

function ago(iso: string, now: number): string {
  const ms = now - Date.parse(iso);
  if (Number.isNaN(ms)) return iso;
  const minutes = Math.max(0, Math.round(ms / 60000));
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} h ${minutes % 60} min ago`;
  return `${Math.floor(hours / 24)} d ago`;
}

function when(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleString(undefined, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
}

function Dot({ state }: { state: DotState }) {
  const theme = useHostTheme();
  const color =
    state === "done"
      ? theme.category.green
      : state === "in progress"
        ? theme.accent.primary
        : state === "blocked" || state === "blocking"
          ? theme.category.yellow
          : theme.text.quaternary;
  return <span style={{ display: "inline-block", width: 8, height: 8, borderRadius: 4, background: color, flexShrink: 0 }} />;
}

function CommandBlock({ command }: { command: string }) {
  const theme = useHostTheme();
  return (
    <div
      style={{
        fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
        fontSize: 11,
        lineHeight: "16px",
        padding: "8px 10px",
        borderRadius: 6,
        background: theme.fill.tertiary,
        color: theme.text.primary,
        wordBreak: "break-word",
        userSelect: "all",
      }}
    >
      {command}
    </div>
  );
}

function NeedsYouItem({
  item,
  mark,
  onMark,
}: {
  item: Workstream["needsYou"][number];
  mark?: Mark;
  onMark: (state: Mark["state"] | null) => void;
}) {
  const dispatch = useCanvasAction();
  const closed = item.done || mark?.state === "done" || mark?.state === "skipped";
  const ask = () => {
    onMark("asked");
    dispatch({
      type: "newComposerChat",
      userPrompt:
        `From this workstream canvas's Needs you list, please take on "${item.title}" (item ${item.id}): ${item.detail}` +
        `${item.command ? ` The command: ${item.command}` : ""} ` +
        "Then update the canvas as .cursor/skills/workstream-canvas/SKILL.md says, with what came of it.",
    });
  };
  return (
    <div
      style={{
        display: "grid",
        gridTemplateColumns: "14px minmax(0, 1fr)",
        gap: 8,
        alignItems: "start",
        opacity: closed ? 0.6 : 1,
      }}
    >
      <div style={{ paddingTop: 6 }}>
        <Dot state={closed ? "done" : item.blocking ? "blocking" : "waiting"} />
      </div>
      <Stack gap={3}>
        <Row gap={8} align="center">
          <Text size="small" weight="semibold">
            {item.title}
          </Text>
          {item.blocking && !closed ? <Pill size="sm">Blocks work</Pill> : null}
          {mark?.state === "asked" && !closed ? <Pill size="sm">With an agent</Pill> : null}
        </Row>
        <Text size="small" tone="secondary">
          {item.detail}
        </Text>
        <Text size="small" tone="tertiary">
          {`Unblocks: ${item.unblocks}`}
        </Text>
        {item.command && !closed ? <CommandBlock command={item.command} /> : null}
        {!item.done && mark && mark.state !== "asked" ? (
          <Row gap={8} align="center">
            <Text size="small" tone="tertiary">
              {`${mark.state === "done" ? "Marked done by you" : "Skipped"}, ${when(mark.at)}; the agent picks it up at its next update.`}
            </Text>
            <Button variant="ghost" onClick={() => onMark(null)}>
              Undo
            </Button>
          </Row>
        ) : null}
        {!closed ? (
          <Row gap={6} style={{ paddingTop: 4 }}>
            <Button variant="secondary" onClick={() => onMark("done")}>
              Done
            </Button>
            <Button variant="ghost" onClick={() => onMark("skipped")}>
              Skip
            </Button>
            <Button variant="ghost" onClick={ask}>
              Ask the agent
            </Button>
          </Row>
        ) : null}
      </Stack>
    </div>
  );
}

function NeedsYou({ items, marks, setMarks }: { items: Workstream["needsYou"]; marks: Marks; setMarks: SetMarks }) {
  const markItem = (id: string) => (state: Mark["state"] | null) =>
    setMarks((previous) => {
      const next = { ...previous };
      if (state) next[id] = { state, at: new Date().toISOString() };
      else delete next[id];
      return next;
    });
  const open = items.filter((item) => !settled(item, marks)).sort((a, b) => Number(b.blocking) - Number(a.blocking));
  const done = items.filter((item) => settled(item, marks));
  return (
    <Stack gap={12}>
      <Row gap={8} align="center">
        <H3>Needs you</H3>
        <Spacer />
        <Text size="small" tone="tertiary">
          {`${open.length} open`}
        </Text>
      </Row>
      {open.map((item) => (
        <div key={item.id}>
          <NeedsYouItem item={item} mark={marks[item.id]} onMark={markItem(item.id)} />
        </div>
      ))}
      {done.length > 0 && (
        <CollapsibleSection title="Done" count={done.length} defaultOpen={open.length === 0}>
          <Stack gap={10}>
            {done.map((item) => (
              <div key={item.id}>
                <NeedsYouItem item={item} mark={marks[item.id]} onMark={markItem(item.id)} />
              </div>
            ))}
          </Stack>
        </CollapsibleSection>
      )}
    </Stack>
  );
}

function Lane({ title, items }: { title: string; items: { title: string; detail: string }[] }) {
  const theme = useHostTheme();
  return (
    <Stack gap={10} style={{ padding: 14, background: theme.fill.quaternary, borderRadius: 8, minWidth: 0 }}>
      <Row justify="space-between" align="center">
        <Text weight="semibold">{title}</Text>
        <Text size="small" tone="tertiary">
          {`${items.length}`}
        </Text>
      </Row>
      {items.map((item) => (
        <div key={item.title}>
          <Stack gap={2}>
            <Text size="small" weight="medium">
              {item.title}
            </Text>
            <Text size="small" tone="secondary">
              {item.detail}
            </Text>
          </Stack>
        </div>
      ))}
    </Stack>
  );
}

function LogEntries({ entries, now }: { entries: Workstream["log"]; now: number }) {
  return (
    <Stack gap={12}>
      {entries.map((entry) => (
        <div
          key={`${entry.at}-${entry.text.slice(0, 32)}`}
          style={{ display: "grid", gridTemplateColumns: "112px minmax(0, 1fr)", gap: 10 }}
        >
          <Stack gap={0}>
            <Text size="small" tone="secondary">
              {ago(entry.at, now)}
            </Text>
            <Text size="small" tone="tertiary">
              {when(entry.at)}
            </Text>
          </Stack>
          <Text size="small">{entry.text}</Text>
        </div>
      ))}
    </Stack>
  );
}

function Progress({ plan }: { plan: Workstream["plan"] }) {
  return (
    <Stack gap={7}>
      {plan.map((step) => (
        <div
          key={step.id}
          style={{
            display: "grid",
            gridTemplateColumns: "14px minmax(0, 1fr) auto",
            gap: 8,
            alignItems: "center",
            opacity: step.status === "dropped" ? 0.5 : 1,
          }}
        >
          <Dot state={step.status} />
          <Text size="small" weight={step.status === "in progress" ? "semibold" : "normal"}>
            {step.step}
          </Text>
          <Text size="small" tone="tertiary">
            {step.ref ?? STEP_LABEL[step.status]}
          </Text>
        </div>
      ))}
    </Stack>
  );
}

function Links({ links }: { links: Workstream["links"] }) {
  return (
    <Stack gap={6}>
      <Divider />
      <Text size="small" tone="secondary">
        {links.map((link) => `${link.label}: ${link.target}`).join(" · ")}
      </Text>
    </Stack>
  );
}

function OverviewTab({ now, marks, setMarks }: { now: number; marks: Marks; setMarks: SetMarks }) {
  const w = workstream;
  const lanes = [
    { title: "Ready", items: w.ready },
    {
      title: "Blocked",
      items: w.blocked.map((item) => ({ title: item.title, detail: `${item.detail} Waits on: ${item.blockedBy}` })),
    },
  ].filter((lane) => lane.items.length > 0);
  const side = w.needsYou.length > 0 || w.log.length > 0;
  return (
    <Grid columns={side ? "minmax(0, 1.5fr) minmax(0, 1fr)" : 1} gap={28} align="start">
      <Stack gap={22}>
        {w.plan.length > 0 && (
          <Stack gap={10}>
            <H2>Progress</H2>
            <Progress plan={w.plan} />
          </Stack>
        )}
        {lanes.length > 0 && (
          <Grid columns={lanes.length} gap={12} align="stretch">
            {lanes.map((lane) => (
              <div key={lane.title} style={{ display: "flex", minWidth: 0 }}>
                <Lane title={lane.title} items={lane.items} />
              </div>
            ))}
          </Grid>
        )}
        {w.links.length > 0 && <Links links={w.links} />}
      </Stack>
      {side && (
        <Stack gap={20}>
          {w.needsYou.length > 0 && <NeedsYou items={w.needsYou} marks={marks} setMarks={setMarks} />}
          {w.needsYou.length > 0 && w.log.length > 0 && <Divider />}
          {w.log.length > 0 && (
            <Stack gap={10}>
              <H3>Latest</H3>
              <LogEntries entries={w.log.slice(0, 4)} now={now} />
            </Stack>
          )}
        </Stack>
      )}
    </Grid>
  );
}

function PlanTab() {
  const theme = useHostTheme();
  return (
    <Stack gap={0}>
      {workstream.plan.map((step, index) => (
        <div
          key={step.id}
          style={{
            display: "grid",
            gridTemplateColumns: "28px minmax(0, 1fr) 150px 116px",
            gap: 12,
            alignItems: "start",
            padding: "10px 0",
            borderTop: index === 0 ? `1px solid ${theme.stroke.tertiary}` : undefined,
            borderBottom: `1px solid ${theme.stroke.tertiary}`,
            opacity: step.status === "done" || step.status === "dropped" ? 0.65 : 1,
          }}
        >
          <Text size="small" tone="tertiary" weight="semibold">
            {`${index + 1}`}
          </Text>
          <Stack gap={2}>
            <Text weight="semibold">{step.step}</Text>
            <Text size="small" tone="secondary">
              {step.detail}
            </Text>
            <Text size="small" tone="tertiary">
              {`Done when: ${step.doneWhen}`}
            </Text>
            {step.note ? <Text size="small">{step.note}</Text> : null}
          </Stack>
          <Text size="small" tone="secondary">
            {step.ref ?? ""}
          </Text>
          <Row gap={6} align="center">
            <Dot state={step.status} />
            <Text size="small" tone="secondary">
              {STEP_LABEL[step.status]}
            </Text>
          </Row>
        </div>
      ))}
    </Stack>
  );
}

function MeasurementsTab() {
  const measurements = workstream.measurements;
  return (
    <Grid columns={Math.min(measurements.length, 2)} gap={24} align="start">
      {measurements.map((m) => (
        <div key={m.title}>
          <Stack gap={6}>
            <Text weight="semibold">{m.title}</Text>
            <BarChart categories={m.categories} series={m.series} valueSuffix={m.suffix} horizontal={m.horizontal} height={260} />
            <Text size="small" tone="tertiary">
              {m.caption}
            </Text>
          </Stack>
        </div>
      ))}
    </Grid>
  );
}

// ---------------------------------------------------------------- the room's tabs

type Triage = "shortlist" | "accept" | "decline";
type Outreach = "sent" | "replied" | "applied" | "not now";
type Marked<S> = Record<string, { state: S; at: string }>;

const RUBRIC: (keyof Omit<Scores, "note">)[] = ["photography", "sharing", "fit", "spread", "engagement"];

function total(scores?: Scores): number | null {
  return scores ? RUBRIC.reduce((sum, key) => sum + scores[key], 0) : null;
}

function CopyText({ text }: { text: string }) {
  const theme = useHostTheme();
  const [said, setSaid] = useState<string | null>(null);
  const copy = () => {
    const clipboard = typeof navigator === "undefined" ? undefined : navigator.clipboard;
    if (!clipboard) return setSaid("Click the text to select it, then press ⌘C");
    clipboard.writeText(text).then(
      () => setSaid("Copied"),
      () => setSaid("Click the text to select it, then press ⌘C"),
    );
  };
  return (
    <Stack gap={6}>
      <div
        style={{
          whiteSpace: "pre-wrap",
          fontSize: 13,
          lineHeight: "19px",
          padding: "10px 12px",
          borderRadius: 6,
          background: theme.fill.tertiary,
          color: theme.text.primary,
          wordBreak: "break-word",
          userSelect: "all",
        }}
      >
        {text}
      </div>
      <Row gap={8} align="center">
        <Button variant="secondary" onClick={copy}>
          Copy
        </Button>
        {said ? (
          <Text size="small" tone="tertiary">
            {said}
          </Text>
        ) : null}
      </Row>
    </Stack>
  );
}

function ScoreLine({ scores }: { scores: Scores }) {
  return (
    <Text size="small" tone="secondary">
      {`${RUBRIC.map((key) => `${key} ${scores[key]}`).join(" · ")} · total ${total(scores)} of 15${scores.note ? `. ${scores.note}` : ""}`}
    </Text>
  );
}

function ApplicationCard({
  application,
  mark,
  onMark,
}: {
  application: Application;
  mark?: { state: Triage; at: string };
  onMark: (state: Triage | null) => void;
}) {
  const theme = useHostTheme();
  const dispatch = useCanvasAction();
  const scores = room.scores[String(application.number)];
  const reply = room.replies[String(application.number)];
  const ask = () =>
    dispatch({
      type: "newComposerChat",
      userPrompt:
        `In the ambassadors room (ws-ambassadors canvas), please look at application #${application.number} from ${application.name}: ` +
        "score it on the rubric, and draft the reply its triage calls for, as .cursor/skills/redlamp-ambassadors/SKILL.md describes.",
    });
  return (
    <Stack gap={10} style={{ padding: 14, borderRadius: 8, background: theme.fill.quaternary, opacity: application.state === "closed" ? 0.6 : 1 }}>
      {application.thumbs.length > 0 && (
        <Row gap={6}>
          {application.thumbs.map((thumb, index) => (
            <img key={index} src={thumb} alt={`Photo ${index + 1}`} style={{ height: 120, borderRadius: 4, objectFit: "cover" }} />
          ))}
        </Row>
      )}
      <Row gap={8} align="center">
        <Text weight="semibold">{application.name}</Text>
        <Link href={application.url}>{`#${application.number}`}</Link>
        <Spacer />
        {mark ? <Pill size="sm">{mark.state === "shortlist" ? "Shortlisted" : mark.state === "accept" ? "Accepted" : "Declined"}</Pill> : null}
      </Row>
      <Text size="small" tone="secondary">
        {`${application.shoots}. ${application.cameras}.`}
      </Text>
      <Row gap={10} wrap>
        {application.links.map((url) => (
          <span key={url}>
            <Link href={url}>{url.replace(/^https?:\/\//, "").replace(/\/$/, "")}</Link>
          </span>
        ))}
      </Row>
      <Text size="small">{`What they'd change first: ${application.change}`}</Text>
      {scores ? <ScoreLine scores={scores} /> : null}
      {reply ? (
        <CollapsibleSection title="Reply, drafted">
          <CopyText text={reply} />
        </CollapsibleSection>
      ) : null}
      <Row gap={6}>
        {mark ? (
          <Button variant="ghost" onClick={() => onMark(null)}>
            Undo
          </Button>
        ) : (
          <>
            <Button variant="secondary" onClick={() => onMark("shortlist")}>
              Shortlist
            </Button>
            <Button variant="secondary" onClick={() => onMark("accept")}>
              Accept
            </Button>
            <Button variant="ghost" onClick={() => onMark("decline")}>
              Decline
            </Button>
          </>
        )}
        <Button variant="ghost" onClick={ask}>
          Ask the agent
        </Button>
      </Row>
    </Stack>
  );
}

function ApplicationsTab({ marks, setMarks }: { marks: Marked<Triage>; setMarks: SetCanvasState<Marked<Triage>> }) {
  const mark = (number: number) => (state: Triage | null) =>
    setMarks((previous) => {
      const next = { ...previous };
      if (state) next[String(number)] = { state, at: new Date().toISOString() };
      else delete next[String(number)];
      return next;
    });
  const open = applications.filter((application) => !marks[String(application.number)]);
  const triaged = applications.filter((application) => marks[String(application.number)]);
  return (
    <Stack gap={16}>
      <Text size="small" tone="tertiary">
        {`${applications.length} applications from pdcgomes/redlamp-ambassadors, as room.py sync last read them. Shortlist, Accept or Decline: the agent drafts the reply at its next update, and you send it.`}
      </Text>
      <Grid columns={2} gap={14} align="start">
        {open.map((application) => (
          <div key={application.number}>
            <ApplicationCard application={application} onMark={mark(application.number)} />
          </div>
        ))}
      </Grid>
      {triaged.length > 0 && (
        <CollapsibleSection title="Triaged" count={triaged.length} defaultOpen={open.length === 0}>
          <Grid columns={2} gap={14} align="start">
            {triaged.map((application) => (
              <div key={application.number}>
                <ApplicationCard application={application} mark={marks[String(application.number)]} onMark={mark(application.number)} />
              </div>
            ))}
          </Grid>
        </CollapsibleSection>
      )}
    </Stack>
  );
}

const OUTREACH_STATES: Outreach[] = ["sent", "replied", "applied", "not now"];

function CandidatesTab({ marks, setMarks }: { marks: Marked<Outreach>; setMarks: SetCanvasState<Marked<Outreach>> }) {
  const theme = useHostTheme();
  const [wave, setWave] = useCanvasState<"0" | "1">("candidateWave", "0");
  const mark = (id: string, state: Outreach | null) =>
    setMarks((previous) => {
      const next = { ...previous };
      if (state) next[id] = { state, at: new Date().toISOString() };
      else delete next[id];
      return next;
    });
  const waves = (["0", "1"] as const).filter((w) => room.candidates.some((candidate) => candidate.wave === w));
  const shown = room.candidates
    .filter((candidate) => candidate.wave === (waves.includes(wave) ? wave : waves[0]))
    .sort((a, b) => (total(b.scores) ?? 0) - (total(a.scores) ?? 0));
  return (
    <Stack gap={14}>
      <Row gap={6} align="center">
        {waves.map((w) => (
          <span key={w}>
            <Pill active={(waves.includes(wave) ? wave : waves[0]) === w} onClick={() => setWave(w)}>
              {`Wave ${w} · ${room.candidates.filter((candidate) => candidate.wave === w).length}`}
            </Pill>
          </span>
        ))}
        <Spacer />
        <Text size="small" tone="tertiary">
          You send every invitation; one follow-up after a week.
        </Text>
      </Row>
      {shown.map((candidate, index) => {
        const state = marks[candidate.id];
        return (
          <div
            key={candidate.id}
            style={{ padding: "12px 0", borderTop: index === 0 ? `1px solid ${theme.stroke.tertiary}` : undefined, borderBottom: `1px solid ${theme.stroke.tertiary}` }}
          >
            <Stack gap={6}>
              <Row gap={8} align="center">
                <Text weight="semibold">{candidate.name}</Text>
                <Link href={candidate.url}>{candidate.platform}</Link>
                <Text size="small" tone="tertiary">
                  {candidate.niche}
                </Text>
                <Spacer />
                <Pill size="sm">{state ? state.state[0].toUpperCase() + state.state.slice(1) : "To contact"}</Pill>
              </Row>
              <Text size="small" tone="secondary">
                {`${candidate.why} Found: ${candidate.source}.`}
              </Text>
              {candidate.scores ? <ScoreLine scores={candidate.scores} /> : null}
              <CollapsibleSection title="Invitation">
                <CopyText text={candidate.invitation} />
              </CollapsibleSection>
              <Row gap={6}>
                {OUTREACH_STATES.map((s) => (
                  <span key={s}>
                    <Button variant={state?.state === s ? "secondary" : "ghost"} onClick={() => mark(candidate.id, state?.state === s ? null : s)}>
                      {s[0].toUpperCase() + s.slice(1)}
                    </Button>
                  </span>
                ))}
              </Row>
            </Stack>
          </div>
        );
      })}
    </Stack>
  );
}

function DraftsTab() {
  return (
    <Stack gap={22}>
      {room.drafts.map((draft) => (
        <div key={draft.id}>
          <Stack gap={6}>
            <Text weight="semibold">{draft.label}</Text>
            <Text size="small" tone="tertiary">
              {draft.where}
            </Text>
            <CopyText text={draft.text} />
          </Stack>
        </div>
      ))}
    </Stack>
  );
}

function CohortTab() {
  return (
    <Table
      headers={["Ambassador", "Joined", "Term ends", "Terms", "Edits", "Showcases"]}
      rows={room.cohort.map((a) => [
        `${a.name} (${a.handle})${a.founding ? ", founding" : ""}`,
        a.joined,
        a.termEnds,
        a.termsAgreed ? "Agreed" : "Not yet",
        String(a.edits),
        String(a.showcases),
      ])}
      striped
    />
  );
}

function PicksTab() {
  return (
    <Stack gap={18}>
      {room.picks.map((pick) => (
        <div key={pick.quarter}>
          <Stack gap={6}>
            <Text weight="semibold">{`${pick.quarter}${pick.closes ? `, poll closes ${pick.closes}` : ""}`}</Text>
            {pick.shortlist.map((row) => (
              <Text key={row.id} size="small" tone="secondary">
                {`${row.id} (#${row.issue}): ${row.title}`}
              </Text>
            ))}
            {pick.result ? <Text size="small">{`Picked: ${pick.result}`}</Text> : null}
          </Stack>
        </div>
      ))}
    </Stack>
  );
}

export default function WorkstreamCanvas() {
  const w = workstream;
  const now = useNow();
  const shown: Record<Tab, boolean> = {
    Overview: true,
    Applications: applications.length > 0,
    Candidates: room.candidates.length > 0,
    Drafts: room.drafts.length > 0,
    Ambassadors: room.cohort.length > 0,
    Picks: room.picks.length > 0,
    Plan: w.plan.length > 0,
    Decisions: w.decisions.length > 0,
    Log: w.log.length > 0,
    Measurements: w.measurements.length > 0,
  };
  const tabs = TABS.filter((tab) => shown[tab]);
  const [selected, setSelected] = useCanvasState<Tab>("tab", "Overview");
  const [marks, setMarks] = useCanvasState<Marks>("needsYou", {});
  const [triage, setTriage] = useCanvasState<Marked<Triage>>("applications", {});
  const [outreach, setOutreach] = useCanvasState<Marked<Outreach>>("candidates", {});
  const tab: Tab = shown[selected] ? selected : "Overview";
  const live = w.plan.filter((step) => step.status !== "dropped");
  const done = live.filter((step) => step.status === "done").length;
  const open = w.needsYou.filter((item) => !settled(item, marks));
  const blocking = open.filter((item) => item.blocking).length;
  return (
    <Stack gap={18} style={{ padding: 4 }}>
      <Stack gap={6}>
        <H1>{w.title}</H1>
        <Text tone="secondary">{w.goal}</Text>
        <Text>{w.status}</Text>
        <Text size="small" tone="tertiary">
          {`Updated ${ago(w.updated, now)} (${when(w.updated)})${w.lastCommit ? `, up to ${w.lastCommit}` : ""}`}
        </Text>
      </Stack>

      <Row gap={32} wrap>
        {live.length > 0 && (
          <Stat value={`${done} of ${live.length}`} label="Steps done" tone={done === live.length ? "success" : undefined} />
        )}
        {w.needsYou.length > 0 && (
          <Stat
            value={`${open.length}`}
            label={blocking > 0 ? `Waiting on you, ${blocking} blocking` : "Waiting on you"}
            tone={blocking > 0 ? "warning" : undefined}
          />
        )}
        {w.stats.map((stat) => (
          <div key={stat.label}>
            <Stat value={stat.value} label={stat.label} tone={stat.tone} />
          </div>
        ))}
      </Row>

      {tabs.length > 1 && (
        <Row gap={6} wrap>
          {tabs.map((name) => (
            <span key={name}>
              <Pill active={tab === name} onClick={() => setSelected(name)}>
                {name === "Log" ? `Log · ${w.log.length}` : name === "Decisions" ? `Decisions · ${w.decisions.length}` : name}
              </Pill>
            </span>
          ))}
        </Row>
      )}
      <Divider />

      {tab === "Overview" && <OverviewTab now={now} marks={marks} setMarks={setMarks} />}
      {tab === "Applications" && <ApplicationsTab marks={triage} setMarks={setTriage} />}
      {tab === "Candidates" && <CandidatesTab marks={outreach} setMarks={setOutreach} />}
      {tab === "Drafts" && <DraftsTab />}
      {tab === "Ambassadors" && <CohortTab />}
      {tab === "Picks" && <PicksTab />}
      {tab === "Plan" && <PlanTab />}
      {tab === "Decisions" && (
        <Table
          headers={["Date", "Decision", "Why", "By"]}
          rows={w.decisions.map((d) => [d.date, d.decision, d.why, d.by])}
          striped
        />
      )}
      {tab === "Log" && <LogEntries entries={w.log} now={now} />}
      {tab === "Measurements" && <MeasurementsTab />}
    </Stack>
  );
}
