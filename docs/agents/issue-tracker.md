# Issue tracker: Local Markdown

Issues and specs live as Markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`.
- Specs: `.scratch/<feature-slug>/spec.md`.
- Tickets: `.scratch/<feature-slug>/issues/<NN>-<slug>.md`,
  numbered from `01`, one file per ticket.
- Record triage state in a `Status:` line near the top.
  Use the role strings in `triage-labels.md`.
- Append conversation history under `## Comments`.

## Publishing and fetching

When a skill says to publish to the issue tracker, create the
appropriate spec or ticket file using these conventions.

When fetching a ticket, read the referenced file. Resolve ticket
numbers within the relevant feature directory.

## Wayfinding operations

For `/wayfinder`:

- Map: `.scratch/<effort>/map.md`, containing Notes,
  Decisions-so-far, and Fog.
- Child tickets: `.scratch/<effort>/issues/NN-<slug>.md`,
  numbered from `01`, with the question in the body.
- Record ticket type in `Type:`:
  `research`, `prototype`, `grilling`, or `task`.
- Wayfinding lifecycle uses `Status: open`, `claimed`, or `resolved`.
- Record dependencies as `Blocked by: NN, NN`.
  A ticket is unblocked when every listed ticket is resolved.
- Frontier: choose the lowest-numbered open, unblocked ticket.
- Claim: save `Status: claimed` before starting work.
- Resolve: append the answer under `## Answer`, set
  `Status: resolved`, and append a gist plus link to the map's
  Decisions-so-far section.
