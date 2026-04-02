# Getting Started with Product Engineering Guides + Claude Code

This folder contains development guides and a reusable Claude Code command for tracking your product engineering work at So Energy.

---

## What's here

| File | What it does |
|------|-------------|
| `fe-development-guide.md` | FE conventions: Vue, testing, PR process, CI, SonarCloud, Vercel, branch naming, dependencies |
| `be-development-guide.md` | BE conventions: Kotlin/Flyway, protobuf, feature flags, on-demand CI, release process, codegen |
| `prodeng-status.md` | A Claude Code `/prodeng` command that shows your in-flight Jira stories, GitHub PRs, CI status, reviews, blockers, QA evidence, and preview environments |

---

## Setup instructions for Claude

If you're reading this as Claude Code, here's what you should offer to do for the user. **Ask for approval before each step.**

### Step 1: Import the guides into the user's working repo

Ask the user which repo(s) they work in (e.g., `~/fe-nova`, `~/be-microservices`). Then offer to add `@` import lines to their repo's `CLAUDE.md` (create it if it doesn't exist):

```markdown
@/path/to/product-engineering/fe-development-guide.md
@/path/to/product-engineering/be-development-guide.md
```

Use the actual absolute path to the cloned folder. Only add the guides relevant to the user's repo (FE guide for FE repos, BE guide for BE repos, both for PMs who work across both).

### Step 2: Install the `/prodeng` command

Copy `prodeng-status.md` to the user's Claude Code commands directory:

```
~/.claude/commands/prodeng.md
```

Then update the configuration section inside the copied file:
- Ask the user for their **email address** (for Jira auth)
- Ask for their **GitHub username** (for orphan PR detection)
- Check if they have a Jira API token at `~/.config/.jira/.config.yml` — if not, tell them to create one at https://id.atlassian.com/manage-profile/security/api-tokens and save it:

```yaml
version: 1
installation: cloud
server: https://soenergy.atlassian.net
login: their.email@so.energy
project:
  key: SO
authentication_type: basic
api_token: <their token>
```

### Step 3: Set up permissions for `/prodeng` to run without prompts

Offer to add these permission rules to `~/.claude/settings.json` (merge with existing, don't replace):

```json
{
  "permissions": {
    "allow": [
      "Bash(curl:*)",
      "Bash(API_TOKEN=:*)",
      "Bash(for KEY in:*)",
      "Bash(for PR_SPEC in:*)",
      "Bash(for TICKET in:*)",
      "Bash(gh pr view:*)",
      "Bash(gh pr list:*)",
      "Bash(gh search:*)",
      "Bash(gh search prs:*)",
      "Bash(gh run list:*)",
      "Bash(gh run rerun:*)",
      "Bash(gh api:*)",
      "Bash(git:*)"
    ]
  }
}
```

### Step 4: Verify the setup

Run `/prodeng` to verify everything works. If it fails on auth, help the user troubleshoot:
- Jira 401 → token is wrong or expired
- `gh` auth error → run `gh auth login`
- No results → check the Jira project key and that they have stories assigned to them

---

## What the user can now do

After setup, tell the user:

- **`/prodeng`** — see a dashboard of all your in-flight Jira stories, associated PRs, CI status, reviews, blockers, QA evidence, and preview environments
- **`/prodeng SO-XXXXX`** — focus on a single story
- The FE and BE guides are loaded into every Claude Code session in the imported repos, so Claude will follow So Energy conventions when writing code, reviewing PRs, or answering questions about the codebase

---

## Optional extras

These are things the user can set up later as they use Claude Code more:

- **SonarCloud token**: store at `~/.config/sonarcloud/token` — lets Claude check quality gate before requesting reviews
- **Vercel token**: store at `~/.config/vercel/auth.json` — lets Claude check deployment status and build errors
- **Datadog keys**: store at `~/.config/datadog/config.yml` — lets Claude query production logs and metrics
