# App scope: a human walking with a phone

> Moved verbatim from the root `AGENTS.md` (agent-config#1482 step 4), where the rule stays as one line under the heading **What belongs in the app: a human walking with a phone**. Read this on the trigger named in the root's "Rule detail" table.

The scope test is **can a person walking with a phone meet this thing and
photograph it**. That test governs the *interaction*, not the taxonomy — a
distinction worth stating, because an earlier version of this section got it
wrong and dropped two categories over it.

**All twelve categories are in the app.** Every one of them can carry a
photograph of a physical object at a coordinate: a damaged bin on a private lot
is as photographable from the pavement as a pothole, and a broken meter, a bent
sign or a barrier that will not lift are as physical as a dead street light.

The mistake to avoid is judging a category by the city's description text rather
than by what people actually report through it. Read that way, `heimilissorp`
looks like a service complaint and `bilastaedasjodur` looks like account
administration — but **every category has a non-photographic tail**.
`umferdaroryggi` can be a pure opinion that a junction feels dangerous, and
`almenn-abending` usually is one. Singling out parking for a property all twelve
share was over-fitting.

So the boundary is drawn in the interaction instead:

- **The camera is the entry point.** The app opens on it. There is no path that
  starts with a form.
- **A coordinate is required.** The city does not enforce this; we do. See the
  location section below.
- **No desk mode.** No flow for disputing a charge, chasing an application, or
  filing an idea with nothing attached to it. Someone who wants that has the
  city's own form, and the app should say so rather than pretend to be it.

`almenn-abending` **is** reworded in the interface. The city calls it
suggestions, praise and ideas; here it is the net under a broken bench, a fallen
tree, a collapsed fence — a walker's find with no category of its own. Both
pickers show it as **Annað í almannarými**, with a line underneath saying what
belongs there, from `data/category-labels.json` (#40). Never present it as a
suggestion box.


**`scripts/send-report.mjs` and `payload-map.md` document all twelve** because
that is what the city accepts. They now agree with the app, but keep the
distinction in mind: those files map the endpoint, this section governs the
product.
