#!/usr/bin/env bash
# Regression test for the reply-style rule in pr-to-ready. This is a document
# contract: an implementation agent must be told to derive a thread reply's
# language and tone from the comment it answers.
set -euo pipefail

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILL="${REPO_ROOT}/skills/pr-to-ready/SKILL.md"
RULE='write each thread reply in the language and tone of the comment it replies to'
REMOVED_PR_COMMENT_RULE='write every one of those — the thread replies and that comment alike — in standard Japanese only, never Kansai dialect'

if ! grep -Fq -- "$RULE" "$SKILL"; then
  printf 'pr-to-ready skill must require thread replies to match the replied-to comment language and tone\n' >&2
  exit 1
fi

if grep -Fq -- "$REMOVED_PR_COMMENT_RULE" "$SKILL"; then
  printf 'pr-to-ready skill must not prescribe a language or tone for aggregate PR comments\n' >&2
  exit 1
fi
