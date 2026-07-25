#!/usr/bin/env bash
# Safe release helper: commits, pushes to main, verifies it landed,
# then re-tags v1.0.10 against the confirmed commit.
# Run from inside your repo. Bail out loudly on any mismatch.

set -euo pipefail

TAG="v1.0.10"
BRANCH="main"

echo "== 1. Checking for uncommitted changes =="
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "You have uncommitted changes. Committing them now."
  git add -A
  read -p "Commit message: " MSG
  git commit -m "$MSG"
else
  echo "Nothing to commit — working tree is clean."
fi

LOCAL_SHA=$(git rev-parse HEAD)
echo "Local HEAD is now: $LOCAL_SHA"

echo ""
echo "== 2. Pushing to origin/$BRANCH =="
git push origin "$BRANCH"

echo ""
echo "== 3. Verifying origin/$BRANCH actually matches local HEAD =="
git fetch origin "$BRANCH"
REMOTE_SHA=$(git rev-parse "origin/$BRANCH")

if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
  echo "MISMATCH: local HEAD ($LOCAL_SHA) does not match origin/$BRANCH ($REMOTE_SHA)"
  echo "Stopping here — do not proceed to tagging until these match."
  exit 1
fi
echo "Confirmed: origin/$BRANCH is at $REMOTE_SHA, matches local HEAD."

echo ""
echo "== 4. Re-creating tag $TAG against this exact commit =="
git tag -d "$TAG" 2>/dev/null || echo "(no local tag to delete)"
git push origin ":refs/tags/$TAG" 2>/dev/null || echo "(no remote tag to delete)"
git tag "$TAG"
git push origin "$TAG"

echo ""
echo "== 5. Verifying the pushed tag points at the same commit =="
REMOTE_TAG_SHA=$(git ls-remote --tags origin "refs/tags/$TAG" | awk '{print $1}')

if [ "$REMOTE_TAG_SHA" != "$LOCAL_SHA" ]; then
  echo "MISMATCH: tag $TAG on origin points to $REMOTE_TAG_SHA, expected $LOCAL_SHA"
  exit 1
fi

echo ""
echo "ALL CHECKS PASSED."
echo "Commit:  $LOCAL_SHA"
echo "Tag:     $TAG -> confirmed on origin, matches commit above"
echo ""
echo "Now go to: https://github.com/wiggly-sheets/Spacemap/actions"
echo "Confirm the newest 'Release' run shows commit ${LOCAL_SHA:0:7} at the top."