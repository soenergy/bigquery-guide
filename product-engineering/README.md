# Product Engineering Guides

Institutional knowledge for working across the So Energy engineering stack. Use these as context for Claude Code sessions.

## Files

| File | What It Covers |
|------|---------------|
| `fe-development-guide.md` | Nova, SMBP, IMBP, Nexus — Vue conventions, PR process, CI checks, testing, SonarCloud, Vercel previews, branch naming, GraphQL, dependencies |
| `be-development-guide.md` | be-microservices — Kotlin/Flyway, protobuf, feature flags, on-demand CI, deployment order, codegen, delivery process, release process |
| `prodeng-status.md` | Generic `/prodeng` Claude Code command — tracks in-flight Jira stories, GitHub PRs, CI status, reviews, blockers, QA evidence, preview environments |

## How to set up

**Easiest way**: clone this repo and ask Claude Code to explore the `product-engineering/` folder:

```bash
git clone git@github.com:soenergy/bigquery-guide.git ~/bigquery-guide
```

Then in Claude Code:
> "Explore ~/bigquery-guide/product-engineering/ and tell me what you can do with the files there"

Claude will read `getting-started.md` and offer to:
1. Import the guides into your working repo's CLAUDE.md
2. Install the `/prodeng` command
3. Set up permissions so it runs without prompts
4. Verify everything works

See `getting-started.md` for full details.
