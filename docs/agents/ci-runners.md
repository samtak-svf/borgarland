# Why CI is hosted-only

> Moved verbatim from the root `AGENTS.md` (agent-config#1482 step 4), where the rule stays as one line under the heading **Conventions**. Read this on the trigger named in the root's "Rule detail" table.

- CI runs on GitHub-hosted runners. This repo is public, so `ubuntu-latest` and
  `macos-latest` minutes are free; there is no reason for a self-hosted runner
  here. Kept hosted-only on purpose (recorded 2026-09-10, claude-config#195):
  every job is short CI or a daily schedule and public-repo hosted minutes do
  not run out, so a self-hosted lane would add an always-on box as a failure
  mode without removing one. The same reason is written in each scheduled
  workflow's header; a new scheduled workflow inherits it and need not
  relitigate the lane.
