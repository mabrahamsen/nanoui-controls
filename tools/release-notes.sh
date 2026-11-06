#!/bin/sh
# Checks that a release tag (v0.2.0) is the version in build.zig.zon, and
# prints that version's section of CHANGELOG.md as the release notes.
# A prerelease (v0.2.0-rc.1) takes its notes from its own section, or
# else from the version it leads to (0.2.0).
#
#     tools/release-notes.sh v0.2.0 > notes.md
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
tag=${1:?usage: tools/release-notes.sh vX.Y.Z}

version=$(sed -n 's/^ *\.version = "\(.*\)",$/\1/p' "$root/build.zig.zon")
if [ "$tag" != "v$version" ]; then
    echo "error: the tag is $tag, but build.zig.zon says $version (tag v$version)" >&2
    exit 1
fi

# The lines after `## <version>`, up to the next `## `, without the blank
# lines around them.
section() {
    awk -v heading="## $1" '
        $0 == heading { on = 1; next }
        on && /^## / { exit }
        on { print }
    ' "$root/CHANGELOG.md" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}'
}

notes=$(section "$version")
if [ -z "$notes" ]; then notes=$(section "${version%%-*}"); fi
if [ -z "$notes" ]; then
    echo "error: CHANGELOG.md has no section for $version" >&2
    exit 1
fi
printf '%s\n' "$notes"
