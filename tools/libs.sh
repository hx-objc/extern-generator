#!/bin/sh
# tools/libs.sh <out-dir> [patch]: the externs of the whole SDKs, for macOS, iOS
# and Mac Catalyst (<out-dir>/<platform>), and the libraries they make
# (<out-dir>/libs), versioned by the Xcode they come from and the patch (0 by
# default; above 0 for the generator's own changes): Xcode 27.2's are 27.2.0,
# the tag they pin each other at (tools/publish.sh makes it).
# With HXMC set (an hxmc that has the Objective-C interop), each platform's
# output is type-checked too.
set -e
out=${1:-out/sdk}
patch=${2:-0}
xcode=$(xcodebuild -version | head -1 | awk '{print $2}')
version="$(echo "$xcode" | awk -F. '{print $1 "." ($2 == "" ? 0 : $2)}').$patch"
here=$(cd "$(dirname "$0")/.." && pwd)
gen="$here/bin/objc-extern-gen"
ulimit -s unlimited 2>/dev/null || true
mkdir -p "$out"
pids=""
for p in macos ios maccatalyst; do
	rm -rf "$out/$p"
	"$gen" "$out/$p" --platform $p --frameworks all --check > "$out/$p.log" 2>&1 &
	pids="$pids $!"
done
for pid in $pids; do wait $pid || { echo "failed: see $out/*.log"; exit 1; }; done
if [ -n "$HXMC" ]; then
	for p in macos ios maccatalyst; do
		case $p in macos) t=macos-arm64;; ios) t=ios-arm64;; *) t=macos-catalyst-arm64;; esac
		"$HXMC" -D hxmc.target=$t -cp "$out/$p" -main ObjcExternsCheck --no-output > "$out/$p.check" 2>&1 \
			|| { echo "$p: type errors, see $out/$p.check"; exit 1; }
		echo "$p: type-checked"
	done
fi
versions="Xcode $xcode, macOS SDK $(xcrun --sdk macosx --show-sdk-version), iOS SDK $(xcrun --sdk iphoneos --show-sdk-version)"
"$gen" slice "$out/libs" "$out/macos" "$out/ios" "$out/maccatalyst" --version "$version" --sdk-versions "$versions"
echo "libraries $version: $out/libs"
