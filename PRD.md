# PRD: "What Was I Working On" — Session Recovery Board

## One-liner

A single HTML page on the desktop that lists every human work session from the last 90 days, grouped by client, each with a click-to-copy resume command, rebuilt automatically several times a day. It exists so the owner never loses work to a crash, a closed terminal, or a flood of automated sessions.

## The problem

People who run many AI CLI sessions lose track of them. The built-in resume picker shows only the most recent few, sorts by file-modified time, and mixes human work with scheduled automation. File-modified times get re-stamped by tooling, so "recent" lies. After a crash, the session that mattered is buried under dozens of fragments, and the owner experiences that as lost work even though every session is still on disk. The board's job is to make that loss impossible to feel again.

## Who it serves

One person: the operator of the machine. Not a team dashboard. It must be readable at 7 a.m. after a crash, by someone who is stressed and wants one answer: where was I, and how do I get back in.

## What it is, and is not

It is a static, self-contained HTML file regenerated from the session transcripts on disk. No server, no database, no dependencies. Delete the file and the next rebuild recreates it, because the transcripts are the source of truth.

It is not an archive browser (a separate deep-search tool covers all history) and not a status page for running agents.

## Functional requirements

1. **Read truth, not metadata.** Parse timestamps from inside each session transcript (JSONL). Never sort or filter by file-modified time.
2. **Show only human work.** Exclude: sessions whose first message marks them as automation (headless runs, scheduled tasks, context injections); sub-agent transcripts; sessions under a minimum size.
3. **Collapse duplicates.** Sessions sharing the same opening message are retry fragments of one piece of work. Keep the largest, count the rest, and say so on the row ("+3 retry fragments folded").
4. **Filter queue stubs.** A file with a queued-message entry, at most one captured user message, and at most ~20 total lines is a phantom: the message was delivered into a parent session that has its own row. Drop it. The line-count guard is mandatory; large legitimate sessions also contain queue entries because the owner types while the agent works.
5. **Each row shows:** date range of activity, size, message count, the first ask, the last message ("LEFT OFF AT"), and a one-click-copy command that resumes the session in the right directory.
6. **Group into named sections** (see Tagging), ordered by freshest activity, each collapsible, fold state remembered between visits.
7. **Tag bar at the top:** one chip per section with its count, anchor-linking down the page; clicking a chip unfolds its section.
8. **Type-to-filter search** across all row text; sections with no matches disappear while searching; filter text persists between visits.
9. **Recency marker:** rows active in the last 48 hours get a visible edge accent.

## Tagging specification

Buckets are personal: one per client plus the owner's own business, media production, and system/tooling work. Classification runs in two phases against everything the session contains, meaning typed messages, assistant prose, file paths, skill names, shell commands, tool results, and generated titles:

- **Phase 1, identity:** count matches of each bucket's identity terms (names, organizations, project codenames). Highest count wins. This keeps a client session full of generic industry vocabulary with the client it names.
- **Phase 2, lane vocabulary:** only when no identity term appears anywhere, classify by subject words. The system/tooling bucket must score on human language only, because its vocabulary (session, memory, hook, agent) appears in the raw JSON of every transcript.
- **No junk drawer.** Zero-signal sessions are conversations with the assistant about the work itself; they belong in the system bucket. There is no "everything else."

## Freshness and durability requirements

1. Rebuild when any session ends (CLI hook), on login, and on a timer a few times per day. The timer and login triggers must live in the OS scheduler (Task Scheduler or cron), outside the AI tooling, so a tooling upgrade cannot silently kill them.
2. On laptops, the scheduled job must be allowed to run on battery. The Windows default blocks it.
3. Pin transcript retention so session files stop aging out; the board can only show what exists on disk.
4. The page states its own rebuild cadence and last-updated time in the header, and that statement must be true.

## Non-functional constraints

- Build must finish in about a minute for a few hundred sessions; it runs unattended in the background.
- On Windows: PowerShell 5.1-compatible script, ASCII-only source (non-ASCII breaks under default 5.1 encoding), no admin rights needed for the build itself. Registering login triggers or battery settings may require one elevated approval.
- The HTML must work offline from disk with no external resources.

## Acceptance tests

1. Open the page: sections render, counts add up, newest activity sits on top.
2. Click a resume command, paste it in a fresh terminal, land in the correct session.
3. Fold a section, reload, still folded. Click its chip: page jumps there and unfolds it.
4. Search a client's name: only their sections remain.
5. Kill the terminal mid-session; after the next rebuild the session appears with the correct "left off at" line.
6. Verify a known old session (60+ days) appears, and a known scheduled automation does not.
7. Drive the page in a real browser before calling it done. Read actual rows; do not trust the build log alone.

## Lessons that will save the builder days

1. Typed user messages often travel with injected system context in the same transcript line; a naive "skip system lines" filter erases the owner's words. Capture display text and classification text separately.
2. Assistant replies name the client far more reliably than the owner's typed text. Classify from both.
3. Match assistant lines on the message role, not the outer record type; fragment files store replies under a different type.
4. Scoring beats first-match rules, but only with identity terms separated from lane vocabulary; otherwise broad buckets steal sessions from specific ones.
5. Expect over half of all session files to be phantoms. Count message depth before believing any row is real work.

## What to personalize

The bucket list and both term lists (identity and lane vocabulary), the recovery window, the rebuild cadence, and the junk-session markers, which depend on what automation the owner runs.

## Platform notes

Built and shipped on Windows. On Mac or Linux everything holds except the scheduler details: launchd or cron replaces Task Scheduler, and the PowerShell constraints disappear.
