#!/bin/sh
set -eu

title=${CI_MERGE_REQUEST_TITLE:-}

if [ -z "$title" ]; then
  echo "No merge request title is present; skipping the title check."
  exit 0
fi

pattern='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9][a-z0-9._/-]*\))?!?: .+'

if printf '%s\n' "$title" | grep -Eq "$pattern"; then
  echo "Merge request title follows Conventional Commits."
  exit 0
fi

echo "Merge request title must follow Conventional Commits."
echo "Example: fix(rendering): preserve emoji width"
exit 1
