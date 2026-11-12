#!/bin/sh
# Publishes the AppImage to a Forgejo release: `make release` (docs/COMPILAR-LINUX.md).
#
#   FORGEJO_URL=https://git.kdb424.xyz FORGEJO_TOKEN=<token> tools/forgejo_release.sh
#
# The release is the tag v<RT_APP_VERSION>; it is created when it does not exist and its asset of the same name is
# replaced (re-running is safe). TAG overrides the tag name, DRY_RUN=1 prints what would be sent.
#
# Not a CI step, deliberately: the AppImage carries lasgame.so, which is compiled from the player's own game files.
# Those never enter the repository, so only a machine that has generated them can build the file (docs/COMPILAR-LINUX.md).
set -eu
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^#define RT_APP_VERSION "\(.*\)".*/\1/p' runtime/paths.h)
TAG=${TAG:-v$VERSION}
ASSET=LetsGoRecomp-$VERSION-x86_64.AppImage

[ -f "build/$ASSET" ] || { echo "no build/$ASSET: make appimage first" >&2; exit 1; }

# owner/repo: REPO_PATH, else the remote that points at the Forgejo instance (its host, from FORGEJO_URL), else origin.
# This tree is cloned from the upstream GitHub repository, so origin is the wrong answer for a release here.
path_of() { printf '%s' "$1" | sed 's#^ssh://git@[^/:]*:[0-9]*/##; s#^git@[^:]*:##; s#^https\?://[^/]*/##; s#\.git$##'; }
REPO_PATH=${REPO_PATH:-}
if [ -z "$REPO_PATH" ]; then
    HOST=$(printf '%s' "$FORGEJO_URL" | sed 's#^[a-z]*://##; s#/.*##; s#:.*##')
    for r in fry $(git remote 2>/dev/null); do  # (`fry` first: this tree's upstream is the GitHub repository)
        url=$(git remote get-url "$r" 2>/dev/null) || continue
        case "$r:$url" in
        fry:*) REPO_PATH=$(path_of "$url") ;;
        *"$HOST"*) REPO_PATH=$(path_of "$url") ;;
        esac
        [ -n "$REPO_PATH" ] && break
    done
fi
[ -n "$REPO_PATH" ] || REPO_PATH=$(path_of "$(git remote get-url origin 2>/dev/null || echo '')")
[ -n "$REPO_PATH" ] || { echo "no repository to publish to: set REPO_PATH=<owner>/<repo>" >&2; exit 1; }

: "${FORGEJO_URL:?set FORGEJO_URL, e.g. https://git.kdb424.xyz}"
: "${FORGEJO_TOKEN:?set FORGEJO_TOKEN (Forgejo > Settings > Applications, write:repository)}"
command -v curl >/dev/null || { echo "curl is needed" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is needed" >&2; exit 1; }

API=$FORGEJO_URL/api/v1/repos/$REPO_PATH
AUTH="Authorization: token $FORGEJO_TOKEN"
BODY="Pokemon: Let's Go, statically recompiled, native on Linux. Unzip/inspect not needed: one AppImage. It holds the
runtime, the game code and the libraries the binary links; the Vulkan loader and driver stay the system's. Saves,
settings, mods and the game files go to \$XDG_DATA_HOME/lasrecomp. Add it to Steam with the launch option --play."

if [ "${DRY_RUN:-}" = "1" ]; then
    echo "tag:   $TAG"
    echo "repo:  $API"
    echo "asset: build/$ASSET"
    echo "GET   $API/releases/tags/$TAG"
    exit 0
fi

sha256sum "build/$ASSET" > "build/$ASSET.sha256"

CODE=$(curl -sS -o build/release.json -w '%{http_code}' -H "$AUTH" "$API/releases/tags/$TAG")
if [ "$CODE" = "200" ]; then
    REL_ID=$(jq -r .id build/release.json)
    echo "release $TAG exists ($REL_ID)"
elif [ "$CODE" = "404" ]; then
    curl -fsS -H "$AUTH" -H 'Content-Type: application/json' \
        -d "$(jq -n --arg t "$TAG" --arg b "$BODY" '{tag_name:$t,name:$t,body:$b,draft:false,prerelease:false}')" \
        "$API/releases" -o build/release.json
    REL_ID=$(jq -r .id build/release.json)
    echo "created release $TAG ($REL_ID)"
else
    echo "could not read the release: HTTP $CODE" >&2
    cat build/release.json >&2
    exit 1
fi

case "$REL_ID" in '' | null)
    echo "no release id in the answer:" >&2
    cat build/release.json >&2
    exit 1
    ;;
esac

# An asset of the same name goes first (the upload adds a second one otherwise), and duplicates too: a listing is
# fetched after each round, so the answer is the server's, not the stale release the name came from.
for name in "$ASSET" "$ASSET.sha256"; do
    for round in 1 2 3 4 5; do
        IDS=$(curl -fsS -H "$AUTH" "$API/releases/$REL_ID/assets?per_page=50" | jq -r --arg n "$name" '.[]? | select(.name==$n) | .id')
        [ -n "$IDS" ] || break
        for AID in $IDS; do
            curl -fsS -X DELETE -H "$AUTH" "$API/releases/$REL_ID/assets/$AID" >/dev/null
            echo "replaced the previous $name"
        done
    done
done

for f in "$ASSET" "$ASSET.sha256"; do
    curl -fsS -H "$AUTH" -F "attachment=@build/$f" "$API/releases/$REL_ID/assets?name=$f" -o build/asset.json
    URL=$(jq -r '.browser_download_url // empty' build/asset.json)
    if [ -z "$URL" ]; then
        echo "the upload of $f produced no download URL:" >&2
        cat build/asset.json >&2
        exit 1
    fi
    echo "$URL"
done
rm -f build/release.json build/asset.json
