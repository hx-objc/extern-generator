using StringTools;

// A module's @:hxmc.available as each platform's own SDK says it (Slice):
// a run writes every platform's version, but the SDKs' headers disagree on
// the others' (the macOS SDK's AVSpeechSynthesisMarker is macOS 14.0 and
// iOS 16.0, the iOS SDK's macOS 13.0 and iOS 17.0; the iOS SDK's CIKernel
// methods name no macOS version at all). Where a module's runs differ in
// nothing else, its macOS versions are the macOS run's, its iOS versions the
// iOS run's and its Mac Catalyst versions the Mac Catalyst run's, so that its
// text is the same on each and it is shared; a platform without the module
// takes the latest the others give.
class Unify {
	static final META = "@:hxmc.available(";

	// a module's texts by platform (those that have it), unified where they
	// differ in their @:hxmc.available alone
	public static function texts(platforms:Array<String>, texts:Map<String, String>):Map<String, String> {
		var parsed = new Map<String, Array<Line>>();
		var first:Null<Array<Line>> = null;
		for (p in platforms) {
			var t = texts.get(p);
			if (t == null) continue;
			var ls = lines(t);
			if (first == null) first = ls;
			else if (!same(first, ls)) return texts;
			parsed.set(p, ls);
		}
		if (first == null) return texts;
		var out = new StringBuf();
		for (i in 0...first.length) {
			var entries = [];
			for (p in platforms) {
				var e = parsed.exists(p) ? parsed.get(p)[i].entries.get(p) : latest(platforms, parsed, i, p);
				if (e != null) entries.push(e);
			}
			// (where a run put it: on a line of its own, or in the declaration's)
			var own:Null<String> = null, at = -1, space = true;
			for (p in platforms) {
				var l = parsed.exists(p) ? parsed.get(p)[i] : null;
				if (l == null || own != null || at >= 0) continue;
				if (l.own != null) own = l.own;
				else if (l.at >= 0) {
					at = l.at;
					space = l.space;
				}
			}
			var meta = META + entries.join(", ") + ")";
			var text = first[i].text;
			if (entries.length > 0 && own != null) out.add(own + meta + "\n");
			else if (entries.length > 0 && at >= 0) text = text.substr(0, at) + (space ? " " : "") + meta + text.substr(at);
			out.add(text);
			if (i < first.length - 1) out.add("\n");
		}
		var t = out.toString();
		return [for (p in parsed.keys()) p => t];
	}

	// the latest version of platform p the runs that have the module give
	static function latest(platforms:Array<String>, parsed:Map<String, Array<Line>>, i:Int, p:String):Null<String> {
		var best:Null<String> = null;
		for (q in platforms) {
			if (!parsed.exists(q)) continue;
			var e = parsed.get(q)[i].entries.get(p);
			if (e != null && (best == null || Avail.compare(version(e), version(best)) > 0)) best = e;
		}
		return best;
	}

	// "macos >= 14.0", "macos >= version(\"10.15.4\")": 14.0, 10.15.4
	static function version(entry:String):String {
		var v = entry.substr(entry.indexOf(">=") + 2).trim();
		return v.startsWith("version(") ? v.substring(9, v.length - 2) : v;
	}

	static function same(a:Array<Line>, b:Array<Line>):Bool {
		if (a.length != b.length) return false;
		for (i in 0...a.length)
			if (a[i].text != b[i].text) return false;
		return true;
	}

	// the text's lines without their @:hxmc.available, each with the entries
	// it had (on the line before, or in it)
	static function lines(text:String):Array<Line> {
		var out:Array<Line> = [];
		var pending:Null<{own:String, entries:Map<String, String>}> = null;
		for (l in text.split("\n")) {
			var s = l.indexOf(META);
			if (s < 0) {
				out.push(pending != null ? {text: l, entries: pending.entries, own: pending.own, at: -1, space: false} : {text: l, entries: new Map(), own: null, at: -1, space: false});
				pending = null;
				continue;
			}
			var e = close(l, s + META.length);
			var entries = parse(l.substring(s + META.length, e));
			var start = s > 0 && l.fastCodeAt(s - 1) == " ".code ? s - 1 : s;
			var rest = l.substr(0, start) + l.substr(e + 1);
			if (rest.trim() == "") pending = {own: l.substr(0, s), entries: entries};
			else out.push({text: rest, entries: entries, own: null, at: start, space: start < s});
		}
		return out;
	}

	// the position of the parenthesis closing the one before i
	static function close(s:String, i:Int):Int {
		var depth = 1, quoted = false;
		while (i < s.length) {
			var c = s.fastCodeAt(i);
			if (c == '"'.code) quoted = !quoted;
			else if (!quoted && c == "(".code) depth++;
			else if (!quoted && c == ")".code && --depth == 0) return i;
			i++;
		}
		return s.length;
	}

	// "macos >= 14.0, ios >= 17.0": by platform
	static function parse(args:String):Map<String, String> {
		var m = new Map<String, String>();
		for (a in args.split(","))
			if (a.trim() != "") m.set(a.trim().split(" ")[0], a.trim());
		return m;
	}
}

private typedef Line = {
	text:String, // the line without its @:hxmc.available
	entries:Map<String, String>, // its declaration's: platform -> "macos >= 14.0"
	own:Null<String>, // on a line of its own before it: that line's indentation
	at:Int, // else in it: where (-1: none)
	space:Bool // (after a space)
}
