# Machine Prompts Man: the handshake model (2.1 addendum)

Oct 14, 2026 · @nigh

## Purpose

This addendum adds the seams that spec 2.0 did not model: every phase change is now a handshake, and only two things ever change a clock. It also fixes what each actor may do, who edits the plan and when, and what B sees first. Real use of the landing-page demo uncovered all of it.

Nothing in the sealed sections changes (verbs, formulas, invariants). The transition table gains guards, not rows. Section 15 lists exactly what moves.

## Actors

Four actors, each with one job. A and B are roles in one window; either may be a person or a machine.

| Actor | Job | May | May not |
| --- | --- | --- | --- |
| System | Owns every clock and the policy table | Start the cost phases on its own; end any phase when its time is up; present options; decide requests by policy | Judge content; consult the model about timing |
| B (the worker) | Does the work | Edit the graph in doing, snooze, strategy, idle; request the next phase; accept a verdict | Stop a clock directly; edit the grid; edit during check-up, break or a freeze |
| A (the gate) | Answers requests when a person holds the role | Approve or refuse a request, with a reason; read the grid and the model's brief; overrule policy | Start or stop a clock; edit the graph or grid |
| Model | Advises at the boundary | say, ask, patch, next (spec §4) | Anything else |

When no person holds A, the System answers requests from its policy table and the verdict is instant. The event still flows through the same path and is logged the same way, so the log of a machine-A session and a human-A session have the same shape.

## The clock rule

A phase clock changes state in exactly two ways, and in no other:

1. The System reaches the end of the phase.
2. B accepts an approved request (presses Go). This is the agreement: B asked, policy or A approved, B confirmed.

Everything else is a message and leaves the clock alone: reminders, B's request, the Waiting state, A's approval, a refusal, B acknowledging a refusal. B never stops a clock; B only asks to start the next phase, and the current clock stops at the moment the next one starts.

After a System-ended phase, nothing runs until B presses Go on the next phase. The session is frozen. B cannot edit the graph during a freeze, so B cannot work either. B may be asleep; the System will not know and does not need to.

## Phases and the chain

Continuation is earned through A; cost is imposed by the System. Work and snooze are the only phases B must ask for. Check-up, plan and the movement break start on their own when the previous phase ends.

&#91;embedded content: phase chain · 5 phases, 2 earned\]

Every arrow still ends at a Go from B: a System-raised phase waits, frozen, until B presses it. Snooze is offered only when the work clock ends, never in another phase.

| Phase | Started by | Length | Ends early | Ends by clock |
| --- | --- | --- | --- | --- |
| Work | B asks, decided, B presses Go | R (10 min) | B asks to move on; approved by default | yes, then Go or Snooze offered |
| Snooze | B asks (Snooze button), decided, Go | q (1:15) | B asks to move on | yes, same offer, one fewer snooze |
| Check-up | System raises it; B presses Go | q · 2^(z+1) ÷ (x+1) | B may ask; policy refuses | yes |
| Plan | System raises it; B presses Go | q (1:15) | B asks (commit); approved with a valid pair | yes, auto-commit fills the pair |
| Break | System raises it; B presses Go | Lb (3 min) | B may ask; policy refuses | yes |

The session itself follows the same rule: B asks to open it and asks to end it. Ending is a request on whatever is running, and policy refuses it during check-up and break.

## The request: one screen, four states

B has one button in every phase, *Next phase*, and sees one screen that changes state. From B's side it feels like any app: press, get "are you sure?" or "sorry, not yet", confirm.

&#91;embedded content: request screen · 5 states, 1 button\]

A request is a record with three timestamps and a verdict:

```
Request { id, session_id, round, from_phase, to_phase,
          raised_by: "man" | "system",
          sent_at, decided_at, decided_by: "policy" | "a", verdict: "approved" | "refused", reason,
          accepted_at, outcome: "accepted" | "overtaken" | "acknowledged" }
```

1. **Phase running.** B works. Pressing *Next phase* raises a request. The clock keeps running.
2. **Waiting.** "Sent to A." Instant when policy decides; as long as A takes when a person does. B keeps working.
3. **Approved.** "Move to Check-up? Go." The clock still runs. Go stops this clock and starts the next phase at the same instant. Elapsed time for the round counts to Go, not to the request.
4. **Refused.** "Not yet: check-up has 1:02 left. OK." B's only option is OK. Nothing changes.
5. **Clock ended.** The System raised the request itself and approved it by policy; B sees the same Approved screen, with *Snooze* beside *Go* when the work clock ended and z < Zmax. The session is frozen until B presses one of them.

If the clock ends while a request is Waiting or Approved, the System's end wins: the request closes as *overtaken* and the screen becomes Clock ended. An approval B never accepts closes the same way.

Snooze is itself a request to start the snooze phase. With policy A it is approved at once and the screen shows "Snooze 1 of 3, 1:15. Go"; with a human A it waits. The snooze clock starts at B's Go, so a snooze is always its full length.

## Policy: the autopilot A, and the human A who may overrule it

Policy is a table in the System, and it is the arithmetic made into verdicts. When no person holds A, policy answers every request at once. When a person holds A, the same table still runs, its default verdict is shown to A beside the request, and A may overrule it with a reason.

| Request | Policy verdict | Reason shown |
| --- | --- | --- |
| Open the session | approve |  |
| Start round n (from plan or idle) | approve if the pair is valid; else refuse | the commit reason (§6.5.1) |
| Move on from work early (finish) | approve |  |
| Snooze | approve if z < Zmax; else refuse | "No snoozes left" |
| Move on from check-up early | refuse | "Check-up has T left" |
| Move on from break early | refuse | "Break has T left" |
| Commit early in plan | approve if the pair is valid; else refuse | the commit reason |
| End the session | approve in work, snooze, plan, idle; refuse in check-up and break | "Finish the check-up first" |

The log records the policy's default and A's verdict on every request. Where they differ is A's judgement, measured. A machine A makes no judgement calls until a trajectory rule is written for it; such a rule would be deterministic script, like the initiative rules in §8.2, never the model.

A refusal from a human A must carry a reason; the System's refusals carry the ones in the table.

## Who edits what, when

The graph is the only thing anyone edits, and only B edits it. The grid is a rendering of the store that the System keeps up to date; nobody types into it. A and B may both look at the grid.

| State | B edits the graph | B presses Next phase | Grid |
| --- | --- | --- | --- |
| Idle (no round yet) | yes | yes: open the session, start round 1 | read |
| Work | yes | yes | read |
| Snooze | yes | yes | read |
| Check-up | no | yes; policy refuses | read |
| Plan | yes | yes: commit | read |
| Break | no | yes; policy refuses | read |
| Frozen (after a clock ended, before Go) | no | Go or Snooze only | read |

The quick-add field moves out of the grid and into the graph. The grid keeps its *This round* column and gains a time axis: a round picker or one column per round, built from the patch log's round stamps. That is what a human A reads to judge an early-move request, and it is the human analogue of the projection the model gets (§7): the same store, filtered by the same pure function.

x is computed from the log as before (§6.6.1). B never reports it and never could, since B cannot edit during check-up.

## Check-up: pure away time

Check-up is the phase after work, length q · 2^(z+1) ÷ (x+1), and B has nothing to do in it. No status report, no grid, no graph. In practice it is stand up, walk, drink water; nothing of that is built in yet.

The name says who is checking: the System computes the round diff and x from the log, the model takes its one turn with a deadline of check-up end (§8.6), and a human A reads the grid. B is the subject, not the actor.

The spec's STATUS phase was "report plus away time" and allowed patches. That is withdrawn. Patches are blocked in check-up as they are in break, and the diff shown at plan start is the System's, not B's.

A check-up of 3 min or more still resets the sitting clock (§6.6.2). A shorter one does not, and a freeze after it does not either.

## Freezes and what they measure

A freeze is the time between a System-ended phase and B's next Go. Nothing runs, B cannot edit, and the System does not care how long it lasts. Freezes are where B sleeps, and that is a win (section 10).

Every boundary now carries three timestamps, so each one measures something specific:

| Gap | Measures |
| --- | --- |
| sent\_at to decided\_at | A's latency; zero on policy |
| decided\_at to accepted\_at, request raised by B | how long B took to confirm what B asked for |
| decided\_at to accepted\_at, request raised by the System | the freeze: how long B took to come back |
| policy default vs A's verdict | A's judgement, as a count of overrides with reasons |

These gaps are stitched out of round time. Elapsed for a round runs from Go to Go, so a slow human A lengthens a round that B asked to finish early; that is accurate, and it is visible in the first gap.

The sitting clock is not a phase clock and never freezes. It runs in every state except idle and break, including every freeze, and resets only on a check-up of 3 min or more or on a break. The System has no evidence B left the chair during a freeze, and erring toward more breaks is the safe side.

## Incentives: B resting is a win

This system is upside down from the usual productivity tool, on purpose. B, left alone, would work without stopping. So the only thing B wants from the System is continuation, and continuation is the one thing B cannot take: it must be asked for, approved, and accepted. Check-up is the cost of a round, not a reward, and B is not allowed to shorten it.

The consequences follow from that:

- B who sleeps through a freeze costs nothing. The clock is stopped, no formula moves, and B rested. That is the outcome the system exists to produce.
- B who marks nothing done and snoozes three times gets a 20 min check-up. The arithmetic is the only enforcement needed.
- The only gaming that matters is B trying to keep working past the clock. The ceiling on that is the clock itself: at time's up B cannot edit the plan until Go.

That ceiling is only real where the System can cover the screen. A Mac app can; the time's-up and check-up covers are B's whole screen. A browser extension cannot, and B would simply work in another tab. So the handshake model is a Mac-app model; in a browser it degrades to advice.

One small leak, left alone: a done marked during plan counts toward no round (§16 default 7), so a B who knows the formula would hold the mark until the next round starts. Spec §14 already rules gaming out of scope, and a human A would see it in the grid.

## B's first screen: the intake

The test for B's screen: someone who has never heard of the system opens it and knows what to do. The current pane fails: "No session", a ring with a dash, Doing and Next rows that do nothing. Nothing of the session is shown until a round exists.

B's first screen is one question and one input box.

1. "What would you like to do now?" B types a line. It becomes a node, and it will be Doing.
2. The same question again. The second line becomes Next.
3. "Ready to start?" with *OK* and *Add more*. Each further line becomes an open step.
4. OK raises the request to open the session and start round 1, in one. B sees Waiting ("Hang tight, waiting for A"), then Approved ("Ready when you are. Go"), then the ring.

Under it, one link: "or continue where you left off", shown only when the graph already has nodes. It opens the Strategy board.

The intake is the graph builder in plain clothes. Every line is a node under the goal; the goal node is implicit and can be named later on the board. The intake and the board are two views of one store, so there is nothing to sync.

During a round, B's default screen is the ring, the two slots, and the *Next phase* button. The board is one click away and optional. Reminders show as a strip that fades on its own; the last reminder and time's up cover the screen.

## Roles in one window

One app, three roles, one window. The role switcher moves from the page footer into the window as a panel that slides in from the right, with A, B and Admin as menu items, plus the autopilot toggle and the demo's speed and timer controls.

| Role | Sees | Does |
| --- | --- | --- |
| B | Intake, ring and slots, the request screen, the Strategy board, the grid (read) | Edits the graph; raises requests; presses Go and OK |
| A | The request queue with the policy default beside each, the grid with its time axis, the model's brief, the log | Approves or refuses with a reason; nothing else |
| Admin | The Monitor and the full event log | Watches |

All three are built now and switchable, because one person is all three today. A `locked_role` setting, added later, hides the switcher when the roles are held by different people or machines. A machine A is the policy table with the autopilot toggle on; B still sees the same screens and the log has the same shape.

A's old controls, pause, stop the round and run the next step, are removed: each one is A starting or stopping a clock.

## Walkthrough of two rounds

Defaults: R 10 min, r 3, so q = 1:15 and reminders at 5:00, 2:30 and 1:15 left. Policy A unless noted. Times are from the start of the round.

**Round 2.** Doing *Fix login bug*, Next *Onboarding copy*, seated 38 min at the start.

| Time | Who | What happens | Clock |
| --- | --- | --- | --- |
| 0:00 | B | Go on "Start round 2?" | work starts |
| 5:00, 7:30 | System | reminder strips; nothing to click | running |
| 6:40 | B | marks *Repro on Safari* done on the board | running; x will be 1 |
| 7:20 | B | presses Next phase: a request to start check-up | running |
| 7:20 | policy | approve. Screen: "Move to Check-up? Go" (a human A might take a minute here) | running |
| 7:50 | B | marks *Fix login bug* done; Next is promoted to Doing | running; x = 2 |
| 8:05 | B | Go | work stops at 8:05; check-up starts: 1:15 × 2 ÷ 3 = 0:50 |
| 8:05 | System | model turn starts, deadline 8:55 |  |
| 8:30 | B | presses Next phase | running |
| 8:30 | policy | refuse: "Not yet, 0:25 left. OK" | running |
| 8:55 | System | check-up ends. Raises "Start Planning? Go" | frozen |
| 11:40 | B | back at the desk, Go. Freeze of 2:45 logged | plan starts, 1:15. Held model output shown now |
| 12:10 | B | accepts a proposal, picks the pair, presses Next phase (commit) | running |
| 12:10 | policy | pair valid. Sit check: 38 + 10 > 45, so the offer is "Movement break, 3:00. Go" | running |
| 12:40 | B | Go | plan stops; break runs; plan locked |
| 15:40 | System | break ends; seated reset. Raises "Start round 3? Go" | frozen until B returns |

**Round 3, the time's-up path.**

| Time | Who | What happens | Clock |
| --- | --- | --- | --- |
| 10:00 | System | work ends. Screen: "Move to Check-up? Go · Snooze 1:15, 3 left" | frozen; B cannot edit |
| — | B | presses Snooze: a request to start snooze 1 | frozen |
| — | policy | approve: "Snooze 1 of 3, 1:15. Go" | frozen |
| — | B | Go | snooze runs 1:15 |
| 11:15 | System | snooze ends. Same screen, 2 left | frozen |
| — | B | Go | check-up: 1:15 × 4 ÷ (x+1) |

With a human A, every *policy* row becomes a Waiting state of whatever length A takes, and the clock in the last column does not change.

## Defaults chosen in this addendum

Each continues the numbering of spec §16. Each is a decision the implementation honours unless a setting says otherwise.

| # | Gap | Default |
| --- | --- | --- |
| 19 | No answer at time's up | Hold, frozen, until B presses Go or Snooze. Replaces default 3 (stop after G). G is no longer used. |
| 20 | Who may stop a clock | Nobody. A clock ends by the System or at B's Go on an approved request. |
| 21 | Who starts check-up, plan, break | The System raises the request; B presses Go. |
| 22 | Early move out of check-up or break | Policy refuses; a human A may approve. |
| 23 | Patches during check-up | Blocked, as in break. Replaces the "status report" patches of §6.8. |
| 24 | Grid | Read-only for everyone; written by the System from the store. |
| 25 | Round elapsed time | Go to Go. Waiting and Approved time counts; freezes do not. |
| 26 | Sitting clock during a freeze | Runs. |
| 27 | Snooze clock start | At B's Go, so a snooze is always q long. |
| 28 | Overtaken requests | The System's phase end wins; the request closes as overtaken. |
| 29 | Plan ends with no valid pair | Auto-commit fills the pair (§6.7); B's next request starts with it. |
| 30 | End session | A request on the running phase; refused during check-up and break. |
| 31 | A's reason on refusal | Required from a human A; the policy table supplies the System's. |
| 32 | Reminders | First r−1 fade on their own; the last one and time's up cover the screen. |
| 33 | Roles | All three built and switchable; `locked_role` setting hides the switcher. |

## What this touches in spec 2.0, and what stays sealed

Sealed and untouched: §4 (the four verbs), §6.2 (phase lengths), §13 (invariants). The model gains nothing and loses nothing; its one turn per round still starts at check-up entry with check-up end as its deadline.

§6.5 (the transition table) keeps every row and gains guards. Each transition that was an event from Man now fires on *accepted request*, and each phase start that followed a tick now waits for one. The table's rows, in the spec's terms, read as:

| Spec row | Now |
| --- | --- |
| IDLE, commit(D, N) → WORK | accepted request to start round 1 |
| WORK, finish → STATUS | accepted request to move on |
| WORK, tick (R elapsed) → TIME\_UP | unchanged; TIME\_UP is the frozen screen |
| TIME\_UP, snooze → SNOOZE | accepted request to start snooze |
| TIME\_UP, stop → STATUS | B presses Go on the System's request |
| TIME\_UP, tick (G elapsed) → STATUS | removed; no grace timeout |
| STATUS, tick → STRATEGY | tick raises the request; STRATEGY starts at Go |
| STRATEGY, commit → SIT\_CHECK | accepted request to start the next round |
| STRATEGY, tick → SIT\_CHECK | auto-commit, then the System raises the request |
| BREAK, tick → WORK | tick raises the request; WORK starts at Go |
| any, end\_session → END | accepted request |

A new small system object, `Request` (section 5), joins §3.4. `store.requests` is append-only and part of the log. The patch log, turn log and system log are unchanged; the system log gains one row per request state change.

§6.8 (permissions by state) loses the `patch` tick in STATUS. §6.9 (announcements) gains the request screens' wording; `announce.js` carries them as variant 0 of new triggers. §10 (modality) gains the screen cover as a first-class output for the last reminder, time's up and every frozen screen. §11 (views) makes Grid read-only and moves quick-log to Graph.

§14 (non-goals) keeps "no pause event". A freeze is not a pause: the System never freezes on its own, and nothing a person does freezes a running clock.

If you want this as 2.1, the one sentence for change control is: no verb, no engine input and no model timer were added; one guard, *accepted request*, was placed on every human-initiated transition.
