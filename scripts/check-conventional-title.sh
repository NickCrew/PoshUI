#!/bin/sh
set -eu

title=${PR_TITLE:-}

if [ -z "$title" ]; then
  echo "No pull request title is present; skipping the title check."
  exit 0
fi

pattern='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9][a-z0-9._/-]*\))?!?: .+'

if printf '%s\n' "$title" | grep -Eq "$pattern"; then
  echo "Pull request title follows Conventional Commits."
  exit 0
fi

echo "Pull request title must follow Conventional Commits."
echo "Example: fix(rendering): preserve emoji width"
exit 1
