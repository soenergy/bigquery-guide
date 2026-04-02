# Product Engineering Dashboard — Claude Code Command

This document describes the `/prodeng` slash command for tracking in-flight product engineering work across Jira and GitHub at So Energy.

To use it, copy the command file into your `.claude/commands/` directory and customise the configuration section.

---

## Configuration

Before using, update these values for your setup:

```
Jira server: https://soenergy.atlassian.net
Jira project: SO
Jira auth: basic auth with your email + API token (store in ~/.config/.jira/.config.yml)
GitHub org: soenergy
Repos to check: fe-nova, fe-monorepo, be-microservices
GitHub username: <your GitHub username>
Approval thresholds: BE PRs need 1 approval, FE PRs need 2 approvals
Jira flag field: customfield_10021 ("Flagged")
```

---

## What it does

The command fetches live data from Jira and GitHub to produce a dashboard of your in-flight work:

1. **Jira stories** assigned to you (not Done/Closed/Archived/Backlog)
2. **Subtasks** with their flag status and blocker reasons
3. **Associated PRs** — CI status, reviews, review requests, unresolved review comments
4. **Preview environments** — Vercel URLs for FE PRs, on-demand slugs for BE PRs
5. **Orphaned PRs** — open PRs where the Jira story is already Done
6. **QA evidence** — whether test plans/evidence have been posted as Jira comments
7. **Workflow stage** — maps each item to Discussion → PR raised → In review → QA → Deployed → Launched
8. **Priority next actions** — what to do next for each story

---

## Step 1: Authenticate and gather sources

### 1a. Jira auth
Read the API token from your config file. Server: `https://soenergy.atlassian.net`.

### 1b. Check memory for known active work
If you have an "Active Work" section in your Claude Code memory, use it as a seed list — but always verify live.

---

## Step 2: Fetch all in-flight Jira stories

### 2a. Find active stories
Search Jira for stories/tasks assigned to the current user that are not Done/Closed:

```
POST /rest/api/3/search/jql
{
  "jql": "project = SO AND assignee = currentUser() AND status NOT IN (Done, Closed, Released, Cancelled) AND issuetype IN (Story, Task, Bug) ORDER BY updated DESC",
  "fields": ["summary","status","issuetype","parent","priority","assignee","labels","fixVersions","customfield_10020","customfield_10021"],
  "maxResults": 50
}
```

### 2b. Fetch subtasks (including flag status)
For each story, fetch subtasks. **Always include `customfield_10021`** — this is the "Flagged" field:

```
GET /rest/api/3/issue/{issueKey}?fields=subtasks,summary,status,issuetype,parent,priority,assignee,labels,fixVersions,description,customfield_10021
```

Also check the flag on each subtask individually — subtasks can be flagged independently of their parent.

### 2c. Build the hierarchy
```
Epic (if exists)
  └── Story
       ├── Subtask 1 (often maps to a PR)
       ├── Subtask 2
       └── ...
```

### 2d. Fetch Epic details
```
GET /rest/api/3/issue/{epicKey}?fields=summary,status
```

### 2e. Check for blockers on flagged items
For any story or subtask where `customfield_10021` is not null (flagged), fetch its comments:

```
GET /rest/api/3/issue/{issueKey}/comment?orderBy=-created&maxResults=5
```

Comments use Atlassian Document Format (ADF). Extract text and links:
- `type: "text"` nodes → plain text
- `type: "inlineCard"` nodes → `attrs.url` is the linked Jira issue or page
- `type: "mention"` nodes → `attrs.text` is the @mentioned person

Look for comments mentioning "flag", "blocked", "blocker", or "waiting". Extract the blocking issue key from inlineCard URLs.

---

## Step 3: Find associated PRs

### 3a. Extract PR info from subtasks
Subtask titles often contain PR numbers (e.g., "FE #1767 fe-nova" or "BE #9223 be-microservices"). Parse to identify PR number and repository name.

### 3b. Check GitHub PR status
```bash
gh pr view {PR_NUMBER} --repo soenergy/{REPO_NAME} --json title,state,statusCheckRollup,reviews,reviewRequests,mergeable,isDraft,url,headRefName,comments
```

Capture:
- **State**: open, merged, closed
- **CI checks**: passing, failing, pending. **Important**: `statusCheckRollup` can contain duplicate check names from multiple runs. When a check name appears more than once, only count the **latest** result (last in the array). Deduplicate by check name before counting pass/fail.
- **Reviews**: approved, changes requested, pending
- **Review requests**: who has been explicitly requested (from `reviewRequests`)
- **Mergeable**: whether it can be merged
- **Draft**: whether it's a draft PR

For reviews, distinguish:
- **Requested reviewers** not yet responded → "⏳ Waiting on @{login}"
- **Approved** → "✅ @{login}"
- **Changes requested** → "🔴 @{login} requested changes"

### 3c. Check for unresolved review comments
Use the GraphQL API to get thread resolution status:

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 20) {
        nodes {
          isResolved
          comments(first: 10) {
            nodes {
              author { login }
              body
              path
              line
            }
          }
        }
      }
    }
  }
}' -f owner=soenergy -f repo=$REPO -F pr=$PR_NUMBER
```

For each thread:
- Skip threads started by bots (`github-actions`, `sonarqubecloud`, `vercel`, `gitstream-cm`, `codecov`)
- Skip threads started by yourself
- Check `isResolved` — resolved threads don't need attention
- Check if you have replied (any comment by your GitHub username after the first)
- **Only surface unresolved threads**

### 3d. Get preview environments
**FE PRs (fe-nova, fe-monorepo):** Extract the Vercel preview URL from PR comments (look for `*.preview.soenergy.co` links). If deployment failed, note "🔴 deploy failed".

**BE PRs (be-microservices):** On-demand environment slug = Jira ticket number. Show as `on-demand: SO-XXXXX`.

FE + BE: note that `?injectOnDemandHeader=SO-XXXXX` connects the FE preview to the BE on-demand.

### 3e. Search for PRs not in subtask titles
```bash
gh search prs "SO-{number}" --repo soenergy/fe-nova --repo soenergy/fe-monorepo --repo soenergy/be-microservices --json number,title,state,repository
```

### 3f. Catch orphaned open PRs
Search for all your open PRs — any not captured from the Jira query is an orphan (Jira story Done but PR still open):

```bash
gh search prs --author={your-github-username} --state=open --repo soenergy/fe-nova --repo soenergy/fe-monorepo --repo soenergy/be-microservices --json number,title,state,repository
```

### 3g. Check for QA evidence on Jira stories
For each story/subtask with an open or merged PR, fetch Jira comments:

```
GET /rest/api/3/issue/{issueKey}/comment?orderBy=-created&maxResults=10
```

Look for keywords: "QA", "test plan", "test evidence", "tested", "test steps", "verified", "smoke test", or screenshots/images in ADF.

Show per story:
- **QA evidence provided** → "✅ QA" with date
- **No QA evidence** → "⚠️ No QA"

---

## Step 4: Determine workflow stage

| Stage | How to detect |
|-------|--------------|
| **Discussion** | Story exists but no subtasks/PRs yet |
| **Story created** | Subtasks exist but no PRs raised |
| **PR raised** | PR is open, in draft or awaiting review |
| **Design check** | PR is open, has Vercel preview, awaiting design review |
| **In review** | PR has review requests or reviews submitted |
| **QA** | PR is approved but not yet merged. Check Jira comments for QA evidence. |
| **Deploying** | PR is merged, story status suggests deployment in progress |
| **Launched** | PR merged and story is Done/Released |

---

## Step 5: Present the dashboard

### Format
Group by Epic (or ungrouped if no Epic):

```
## 🏗️ [Epic Name] (SO-XXXXX)

### SO-YYYYY: Story Title — [STATUS]
Stage: **In Review**

| Subtask | PR | Repo | CI | Reviews | Preview | QA | Next Step |
|---------|-----|------|----|---------|---------|----|-----------| 
| SO-ZZZZZ: FE changes | #1767 | fe-nova | ✅ | ✅ 2/2 | [Preview](url) | ✅ | Ready to merge |
| SO-ZZZZZ: BE changes | #9223 | be-microservices | ✅ | ✅ 1/1 | on-demand: SO-YYYYY | ⚠️ | Write QA |
```

### Status indicators
- ✅ Merged / Approved / Passing / Done
- 🟡 Open / Pending / In Progress / Awaiting
- 🔴 Failing / Changes Requested / Blocked
- 🚩 Flagged (blocked) — always include the reason from comments
- ⚫ Closed / Cancelled

### Flagged/blocked items
Display prominently below the story heading:
```
> 🚩 **BLOCKED**: SO-XXXXX is flagged — blocked by ISSUE-YYYY
```

### Next steps logic
Flagged items take priority.

- **Flagged/blocked** → "Resolve blocker: {issue key}"
- **PR needs reviews** → "Chase reviews on #{number}"
- **CI failing** → "Fix CI failures on #{number}"
- **Approved, CI green, no QA evidence** → "Ready to merge — write QA test plan"
- **Approved, CI green, QA evidence present** → "Ready to merge"
- **Merged, no QA evidence** → "Write QA evidence before marking Done"
- **Merged, QA evidence present** → "Mark story as Done / verify in prod"
- **No PRs yet** → "Create subtasks and raise PRs"

### Summary
```
## Summary
- X stories in flight
- Y PRs open (Z ready to merge)
- Key blockers: ...
- Suggested next actions: ...
```

---

## Step 6: Update memory

After presenting, update any "Active Work" memory if things have changed.

---

## Notes

- **Approval thresholds**: BE PRs need **1 approval**, FE PRs need **2 approvals**
- **CI deduplication**: `statusCheckRollup` can have duplicate check names from re-runs — only count the latest result per check name
- **Always verify live** — memory/cached state is a starting point, not ground truth
- **Only show in-flight work** — skip Done/Closed items unless recently completed (last 7 days)
- **Focused mode**: pass a ticket number (e.g., `/prodeng SO-29475`) to focus on a single story
