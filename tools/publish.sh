#!/bin/sh
# tools/publish.sh <libs-dir> [message]: commits each library of <libs-dir>
# (tools/libs.sh's) to its repository, github.com/hx-objc/<library>, tags it
# with its version (haxelib.json's: the Xcode it comes from and a patch,
# 27.2.0), at which the libraries depend on each other, and pushes both. A tag
# that exists already is refused: regenerate with the next patch
# (tools/libs.sh <out-dir> 1). DRY_RUN=1 does all but push, and keeps the
# clones to look at.
set -e
libs=${1:?usage: tools/publish.sh <libs-dir> [message]}
libs=$(cd "$libs" && pwd)
work=$(mktemp -d)
for dir in "$libs"/*/; do
	lib=$(basename "$dir")
	version=$(sed -n 's/.*"version": "\(.*\)".*/\1/p' "$dir/haxelib.json")
	from=$(sed -n 's/.*"releasenote": "From \(.*\)\.".*/\1/p' "$dir/haxelib.json")
	msg=${2:-"$version: regenerated from $from"}
	url="https://github.com/hx-objc/$lib.git"
	if git ls-remote --exit-code --tags "$url" "refs/tags/$version" > /dev/null 2>&1; then
		echo "$lib: tag $version exists already: regenerate with the next patch"
		exit 1
	fi
	git clone -q "$url" "$work/$lib"
	(
		cd "$work/$lib"
		git rm -rq --ignore-unmatch . > /dev/null
		cp -R "$dir/." .
		git add -A
		if git diff --cached --quiet; then echo "$lib: unchanged"; else git commit -qm "$msg" && echo "$lib: committed"; fi
		git tag -a "$version" -m "$version: from $from"
		if [ -n "$DRY_RUN" ]; then
			echo "$lib: would push $(git rev-parse --short HEAD) to master and tag $version ($work/$lib)"
		else
			git push -q origin HEAD:master "refs/tags/$version" && echo "$lib: pushed, tagged $version"
		fi
	)
done
if [ -z "$DRY_RUN" ]; then rm -rf "$work"; fi
