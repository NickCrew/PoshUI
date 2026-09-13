#!/bin/sh

set -eu

PWSH_BIN=${PWSH_BIN:-pwsh}
RELEASE_REMOTE_URL=${RELEASE_REMOTE_URL:-origin}
RELEASE_DIR=${RELEASE_DIR:-.release}
BOT_NAME=${BOT_NAME:-"github-actions[bot]"}
BOT_EMAIL=${BOT_EMAIL:-"41898282+github-actions[bot]@users.noreply.github.com"}

mkdir -p "$RELEASE_DIR"
: >"$RELEASE_DIR/release.env"

require_value() {
  name=$1
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "$name is not set. Refusing to create a PoshUI release." >&2
    exit 3
  fi
}

for name in GITHUB_SHA DEFAULT_BRANCH; do
  require_value "$name"
done

COMMIT_TIMESTAMP=${COMMIT_TIMESTAMP:-$(git show -s --format=%cI "$GITHUB_SHA")}

git fetch --force origin "$DEFAULT_BRANCH" --tags
REMOTE_HEAD=$(git rev-parse "origin/${DEFAULT_BRANCH}")
# PowerShell receives these script blocks verbatim. Shell expansion would
# corrupt its variable syntax.
# shellcheck disable=SC2016
PLAN=$($PWSH_BIN -NoLogo -NoProfile -NonInteractive -Command '
  $plan = ./tools/Get-NextVersion.ps1 -AsObject
  if ($plan) { $plan | ConvertTo-Json -Compress -Depth 8 }
')
NEXT_VERSION=$(printf '%s' "$PLAN" | sed -n 's/.*"Version":"\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)".*/\1/p')

emit_release_tag() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf 'release_tag=%s\n' "$1" >>"$GITHUB_OUTPUT"
  fi
}

if [ -z "$NEXT_VERSION" ]; then
  echo "Nothing to release."
  emit_release_tag ""
  exit 0
fi
TAG="v${NEXT_VERSION}"

write_release_artifacts() {
  printf '%s' "$NEXT_VERSION" >"$RELEASE_DIR/version"
  printf 'POSHUI_RELEASE_TAG=%s\n' "$TAG" >"$RELEASE_DIR/release.env"
  $PWSH_BIN -NoLogo -NoProfile -NonInteractive -File \
    ./tools/Invoke-ReleaseChangelog.ps1 -Action Verify -Tag "$TAG" \
    -ManifestPath ./powershell/PoshUI.psd1 -OutputPath "$RELEASE_DIR/notes.md"
}

resume_existing_release() {
  git show-ref --verify --quiet "refs/tags/${TAG}" || return 1
  RELEASE_COMMIT=$(git rev-parse "refs/tags/${TAG}^{}")
  RELEASE_PARENT=$(git rev-parse "${RELEASE_COMMIT}^")
  RELEASE_TYPE=$(git cat-file -t "refs/tags/${TAG}")
  RELEASE_VERSION=$(git show "${RELEASE_COMMIT}:powershell/PoshUI.psd1" | \
    sed -n "s/^[[:space:]]*ModuleVersion[[:space:]]*=[[:space:]]*'\([^']*\)'.*/\1/p")
  CHANGED_PATHS=$(git diff-tree --no-commit-id --name-only -r "$RELEASE_COMMIT" | LC_ALL=C sort)
  EXPECTED_PATHS=$(printf '%s\n' \
    CHANGELOG.md \
    README.md \
    docs/reference/powershell.md \
    powershell/PoshUI.psd1)

  [ "$RELEASE_TYPE" = "tag" ] && \
    [ "$RELEASE_PARENT" = "$GITHUB_SHA" ] && \
    [ "$RELEASE_VERSION" = "$NEXT_VERSION" ] && \
    [ "$CHANGED_PATHS" = "$EXPECTED_PATHS" ] && \
    git merge-base --is-ancestor "$RELEASE_COMMIT" "$REMOTE_HEAD" || return 1

  git checkout "$RELEASE_COMMIT" -- CHANGELOG.md README.md \
    docs/reference/powershell.md powershell/PoshUI.psd1
  $PWSH_BIN -NoLogo -NoProfile -NonInteractive -File ./tools/Set-Version.ps1 -Check
  write_release_artifacts
  echo "Release commit and tag already exist; resuming publication."
  return 0
}

if [ "$REMOTE_HEAD" != "$GITHUB_SHA" ]; then
  if ! resume_existing_release; then
    echo "Default branch advanced before this release; the newer run owns it."
    emit_release_tag ""
    exit 0
  fi
  emit_release_tag "$TAG"
  exit 0
fi

if git show-ref --verify --quiet "refs/tags/${TAG}"; then
  echo "Release tag ${TAG} already exists. Refusing to overwrite it." >&2
  exit 3
fi

$PWSH_BIN -NoLogo -NoProfile -NonInteractive -File ./tools/Get-NextVersion.ps1 -Apply >/dev/null
write_release_artifacts

git config user.name "$BOT_NAME"
git config user.email "$BOT_EMAIL"
git add CHANGELOG.md README.md docs/reference/powershell.md powershell/PoshUI.psd1
GIT_AUTHOR_DATE="$COMMIT_TIMESTAMP" GIT_COMMITTER_DATE="$COMMIT_TIMESTAMP" \
  git commit -m "chore(release): ${TAG} [skip ci]"
GIT_COMMITTER_DATE="$COMMIT_TIMESTAMP" \
  git tag --annotate "$TAG" --file "$RELEASE_DIR/notes.md"
git push --atomic "$RELEASE_REMOTE_URL" \
  "HEAD:refs/heads/${DEFAULT_BRANCH}" \
  "refs/tags/${TAG}"

emit_release_tag "$TAG"
echo "Prepared PoshUI ${TAG} for publication."
