# Product Engineering Guides

Institutional knowledge for working across the So Energy engineering stack. Use these as context for Claude Code sessions.

## Files

| File | What It Covers |
|------|---------------|
| `fe-development-guide.md` | Nova, SMBP, IMBP, Nexus — Vue conventions, PR process, CI checks, testing, SonarCloud, Vercel previews, branch naming, GraphQL, dependencies |
| `be-development-guide.md` | be-microservices — Kotlin/Flyway, protobuf, feature flags, on-demand CI, deployment order, codegen, delivery process, release process |
| `prodeng-status.md` | Generic `/prodeng` Claude Code command — tracks in-flight Jira stories, GitHub PRs, CI status, reviews, blockers, QA evidence, preview environments |

## How to use with Claude Code

Add an import to your repo's `CLAUDE.md` (or your global `~/.claude/CLAUDE.md`):

```markdown
@/path/to/bigquery-guide/product-engineering/fe-development-guide.md
@/path/to/bigquery-guide/product-engineering/be-development-guide.md
```

Or pull just the guide relevant to your current work. Claude Code will load the file into context at the start of every session.

### Quick setup

```bash
# Clone the guide repo (if not already)
git clone git@github.com:soenergy/bigquery-guide.git ~/bigquery-guide

# Add to your working repo's CLAUDE.md
echo "\n@/Users/$USER/bigquery-guide/product-engineering/fe-development-guide.md" >> ~/fe-nova/CLAUDE.md
echo "\n@/Users/$USER/bigquery-guide/product-engineering/be-development-guide.md" >> ~/be-microservices/CLAUDE.md
```
