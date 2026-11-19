---
name: herco-review
description: Trace bugs and independently review HERCO changes for workflow regressions, correctness, security, and verification gaps.
---

# herco-review

Read `docs/engineering-checks.md` from the checkout root. Review the requested diff and its callers, including relevant new files. Trace the smallest failing path with fictional examples and current build evidence. Return only actionable findings with impact, location, cause and suggested correction. Keep unverified hypotheses separate from findings.
