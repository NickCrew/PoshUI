#!/bin/sh

set -eu

PWSH_BIN=${PWSH_BIN:-pwsh}
RELEASE_REMOTE_URL=${RELEASE_REMOTE_URL:-"https://oauth2:${GITLAB_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git"}
RELEASE_DIR=${RELEASE_DIR:-.release}

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

for name in CI_API_V4_URL CI_COMMIT_SHA CI_COMMIT_TIMESTAMP CI_DEFAULT_BRANCH \
  CI_PROJECT_PATH CI_SERVER_HOST GITLAB_TOKEN; do
  require_value "$name"
done

git fetch --force origin "$CI_DEFAULT_BRANCH" --tags
REMOTE_HEAD=$(git rev-parse "origin/${CI_DEFAULT_BRANCH}")
# PowerShell receives these script blocks verbatim. Shell expansion would
# corrupt its variable syntax.
# shellcheck disable=SC2016
PLAN=$($PWSH_BIN -NoLogo -NoProfile -NonInteractive -Command '
  $plan = ./tools/Get-NextVersion.ps1 -AsObject
  if ($plan) { $plan | ConvertTo-Json -Compress -Depth 8 }
')
NEXT_VERSION=$(printf '%s' "$PLAN" | sed -n 's/.*"Version":"\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)".*/\1/p')

if [ -z "$NEXT_VERSION" ]; then
  echo "Nothing to release."
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
    [ "$RELEASE_PARENT" = "$CI_COMMIT_SHA" ] && \
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

if [ "$REMOTE_HEAD" != "$CI_COMMIT_SHA" ]; then
  if ! resume_existing_release; then
    echo "Default branch advanced before this release; the newer pipeline owns it."
    exit 0
  fi
  exit 0
fi

if git show-ref --verify --quiet "refs/tags/${TAG}"; then
  echo "Release tag ${TAG} already exists. Refusing to overwrite it." >&2
  exit 3
fi

$PWSH_BIN -NoLogo -NoProfile -NonInteractive -File ./tools/Get-NextVersion.ps1 -Apply >/dev/null
write_release_artifacts

identity=$(curl --silent --show-error --fail \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${CI_API_V4_URL}/user") || {
  echo "GITLAB_TOKEN was rejected when asking GitLab for its identity." >&2
  exit 3
}
# shellcheck disable=SC2016
bot_fields=$(printf '%s' "$identity" | $PWSH_BIN -NoLogo -NoProfile -NonInteractive -Command '
  $user = $input | Out-String | ConvertFrom-Json
  $name = if ($user.name) { $user.name } else { $user.username }
  $email = if ($user.email) { $user.email } else { "$($user.username)@noreply.$env:CI_SERVER_HOST" }
  if (-not $name -or -not $email) { exit 1 }
  $name
  $email
') || {
  echo "GitLab token identity was incomplete." >&2
  exit 3
}
BOT_NAME=$(printf '%s\n' "$bot_fields" | sed -n '1p')
BOT_EMAIL=$(printf '%s\n' "$bot_fields" | sed -n '2p')
git config user.name "$BOT_NAME"
git config user.email "$BOT_EMAIL"
git add CHANGELOG.md README.md docs/reference/powershell.md powershell/PoshUI.psd1
GIT_AUTHOR_DATE="$CI_COMMIT_TIMESTAMP" GIT_COMMITTER_DATE="$CI_COMMIT_TIMESTAMP" \
  git commit -m "chore(release): ${TAG} [skip ci]"
GIT_COMMITTER_DATE="$CI_COMMIT_TIMESTAMP" \
  git tag --annotate "$TAG" --file "$RELEASE_DIR/notes.md"
git push --atomic "$RELEASE_REMOTE_URL" \
  "HEAD:refs/heads/${CI_DEFAULT_BRANCH}" \
  "refs/tags/${TAG}"

echo "Prepared PoshUI ${TAG} for publication."
