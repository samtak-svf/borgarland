# iOS app context

> Path-scoped context, loaded when you read or edit a file under this directory.
> Read this directly before iOS work that opens no file here. Root rules in [AGENTS.md](../AGENTS.md) still apply (agent-config#1482 step 4).

**iOS — nobody's skills decide, because Apple publishes none.** Checked
2026-08-24: `apple/skills` and every obvious variant is a 404, and no repository
under `org:apple` matches. Their move was to put the Claude Agent SDK inside
Xcode 26.3, which is no help here. What is installed is community work —
`swiftui-pro` and `swift-testing-pro`, Paul Hudson, MIT — and it is **evidence,
not law**. Two specific cautions: Hudson's own index says listing is not
endorsement, and `swiftui-pro` assumes iOS 26 and Swift 6.2 while
`ios/project.yml` targets **iOS 17.0 and Swift 5.9**, so its "use the modern
API" advice is regularly unbuildable here. There is no Mac on this machine, so
CI is the only compiler and a wrong suggestion costs a whole build to discover.
