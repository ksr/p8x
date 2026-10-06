---
name: project_cottageworker_site
description: "cottageworker.com repo (~/Developer/cottageworker-site, github ksr/cottageworker-site); snapshot job removed from this Mac 2026-10-05, second Mac NOT yet verified"
metadata:
  node_type: memory
  type: project
  originSessionId: 18685e0a-3775-496c-8a9c-119f56f500d2
  modified: 2026-10-05T13:32:06.948Z
---

Repo `~/Developer/cottageworker-site` (https://github.com/ksr/cottageworker-site) records and manages cottageworker.com (WordPress hub for Ken's projects). It has its own CLAUDE.md with non-negotiable site rules: read it before any work there (sessions started elsewhere do not load it). Sync with `git pull --ff-only`; commit by explicit path; push after each commit.

2026-10-05: both Macs had been running the nightly snapshot job (launchd `com.cottageworker.site-snapshot`), which caused a rejected push. The job was removed from THIS Mac (IT-REA-KSR77-5, the "first Mac") with `./remove-job.sh`; README line 34 and CLAUDE.md line 39 now say it runs on the second Mac.

**Why:** only one Mac may run the job, or the two commit snapshots in conflict.
**How to apply:** it is still UNVERIFIED that the job is installed on the second Mac (Ken will check later). If the subject comes up, remind him: on the second Mac run `launchctl list | grep cottageworker`; if nothing prints, `./install-job.sh`. Otherwise no Mac is taking snapshots. Commands in this app's terminal pane run on this Mac, not the second one.

Related: [[feedback_doc_voice]], [[project_yacc1]], [[project_p8x]].
