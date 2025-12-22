\# Architecture Pivot: Participation Mode & Prize Balancing

\#\# Status  
In Progress    
Branch: feature/participation-mode    
Baseline: Stable competitive implementation on main

\---

\#\# Project Context

The Christmas Games application is designed to manage live, hosted  
game events built around the following hierarchy:

\- Event  
  \- Games  
    \- Rounds  
      \- Teams / Participants

Historically, the application has optimized for \*\*competitive outcomes\*\*:  
determining winners at the game and event level through structured  
rounds and placements.

In real-world family and group settings, the primary hosting goal has  
shifted toward \*\*maximizing participation and fairness\*\*, rather than  
crowning a single overall winner.

This document formalizes a pivot toward supporting both approaches.

\---

\#\# Problem Being Solved

When running live events:

\- Some participants naturally win more often  
\- Others can fall behind in prizes despite active participation  
\- Strict competition reduces overall engagement and enjoyment  
\- Hosts need flexibility to balance fun, fairness, and flow

The current architecture captures winners well but does not:  
\- Track prize distribution over time  
\- Adjust future opportunities based on prize imbalance  
\- Support events where \*round wins\* matter more than \*overall placement\*

\---

\#\# Core Architectural Decision

\*\*Competitive vs Participation behavior will be modeled as a mode  
(policy), not as separate applications or data models.\*\*

This allows:  
\- Preservation of all existing competitive functionality  
\- A low-risk extension path  
\- Side-by-side support for different event styles

\---

\#\# Competition Modes

\#\#\# Competitive Mode (Existing Behavior)

Purpose:  
\- Determine winners at the game and event level

Characteristics:  
\- Placements are meaningful across rounds  
\- Games may advance winners or determine final standings  
\- Team selection prioritizes fairness but assumes competition  
\- Statistics emphasize wins and placements

This mode remains unchanged.

\---

\#\#\# Participation Mode (New Behavior)

Purpose:  
\- Maximize play opportunities  
\- Balance prize distribution  
\- Keep events fun and inclusive

Characteristics:  
\- Only \*\*round winners\*\* receive prizes  
\- Overall event winner is optional or irrelevant  
\- Prize history influences future round participation  
\- Team/player selection is biased toward those with fewer prizes  
\- Host always retains manual control

\---

\#\# Key Concept Shift

\*\*Winning a round ≠ winning the event\*\*

In Participation Mode:  
\- Rounds are the primary unit of reward  
\- Prizes are the meaningful outcome  
\- Balance over time is more important than elimination or brackets

\---

\#\# Data Model Additions

\#\#\# PrizeAward

A new record representing a prize given during an event.

Fields:  
\- id  
\- eventId  
\- roundId  
\- participantId  
\- prizeTier (High | Low)  
\- awardedAt  
\- notes (optional)

PrizeAwards are append-only and form the basis for:  
\- prize totals  
\- prize tier balance  
\- future participation biasing

\---

\#\# Settings & Configuration

\#\#\# Application-Level  
\- Default competition mode:  
  \- Competitive  
  \- Participation

\#\#\# Event-Level Override  
\- An event may override the default mode  
\- Allows different event styles without changing app settings

Effective mode resolution:  
\- Event override (if present)  
\- Otherwise application default

\---

\#\# Behavioral Changes (Participation Mode Only)

\#\#\# Round Completion

\- Winner is selected as usual  
\- Host awards a prize to the winner(s)  
\- Prize tier (High / Low) is recorded  
\- Prize history updates immediately

\#\#\# Team / Participant Selection

When creating the next round:  
\- Participants with fewer total prizes are prioritized  
\- High-tier prize imbalance is weighted more heavily  
\- Recent prize wins may apply a soft penalty  
\- Manual override is always available to the host

No participant is excluded; the system biases, not enforces.

\---

\#\# Implementation Strategy

The pivot is intentionally incremental:

1\. Introduce PrizeAward persistence  
2\. Surface prize totals in participant views  
3\. Add prize awarding UI at round completion  
4\. Introduce participation mode configuration  
5\. Apply prize-aware bias during round setup

Each step is independently testable and reversible.

\---

\#\# Non-Goals

This architecture explicitly avoids:  
\- Full tournament or bracket modeling  
\- Complex point or ranking systems  
\- Removing existing winner/placement logic  
\- Fully automated hosting decisions

Simplicity and host control are prioritized.

\---

\#\# Rationale

This approach:  
\- Preserves existing investment  
\- Matches real-world hosting behavior  
\- Avoids over-engineering  
\- Allows future expansion without commitment

The application becomes more flexible without becoming more fragile.

\---

\#\# Future Enhancements (Optional)

\- Automatic prize tier scheduling  
\- Prize distribution dashboards  
\- Team-based prize awards  
\- End-of-event participation summaries  
\- Analytics comparing competitive vs participation events

These are intentionally deferred.

