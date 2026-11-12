// extern-generator: Haxe extern declarations of the Apple SDKs' Objective-C
// and C APIs for hxmc (its docs/interop.md, "Objective-C"), from clang's AST.
//
//   objc-extern-gen <out-dir> [--frameworks all|Foundation,AppKit,...] [--platform macos|ios|maccatalyst] [--sdk path] [--json ast.json --text ast.txt [--macros macros.txt]] [--keep-dumps] [--check]
//   objc-extern-gen slice <out-dir> <macos-dir> <ios-dir> <maccatalyst-dir> --version <x.y.z> [--sdk-versions text]
//
// Without --json/--text it runs clang (twice: the JSON dump for the
// declarations, the text dump for their availability, which the JSON dump
// does not spell out; and the preprocessor, for the constant macros), into <out-dir>/.clang, deleted after unless
// --keep-dumps. A framework inside another (HIServices) is read from its
// outer framework's header. --frameworks all: every framework of the SDK
// that imports and that the platform links (Sdk.allFrameworks). --check also
// writes <out-dir>/ObjcExternsCheck.hx, a program naming every generated type.
// raw.txt lists the parameters left raw memory (Ptr, CString) and why.
// `slice` splits the three platforms' outputs into libraries (Slice).
class Main {
	static function stamp(what:String, t0:Float):Float {
		var t = haxe.Timer.stamp();
		Sys.println('$what: ${Math.round((t - t0) * 100) / 100} s');
		return t;
	}

	static function shell(cmd:String) {
		if (Sys.command("/bin/sh", ["-c", cmd]) != 0) throw 'failed: $cmd';
	}

	// the umbrella header that declares framework `f`: its own, or its outer
	// framework's for a sub-framework (HIServices: ApplicationServices)
	static function umbrella(sdk:Sdk, f:String):String {
		// libSystem's libraries in scope (Model's Origin): their headers
		switch f {
			case "dispatch": return "<dispatch/dispatch.h>";
			case "xpc": return "<xpc/xpc.h>";
			case "os": return "<os/log.h>\n#import <os/lock.h>\n#import <os/signpost.h>\n#import <os/workgroup.h>";
			case _:
		}
		for (dir in sdk.frameworkDirs())
			if (sys.FileSystem.exists('$dir/$f.framework')) return '<$f/$f.h>';
		for (dir in sdk.frameworkDirs())
			for (u in sys.FileSystem.readDirectory(dir))
				if (sys.FileSystem.exists('$dir/$u/Frameworks/$f.framework') || sys.FileSystem.exists('$dir/$u/Versions/A/Frameworks/$f.framework')) {
					var name = haxe.io.Path.withoutExtension(u);
					return '<$name/$name.h>';
				}
		return '<$f/$f.h>';
	}

	static final USAGE = "usage: objc-extern-gen <out-dir> [--frameworks all|Foundation,AppKit,...] [--platform macos|ios|maccatalyst] [--sdk path] [--json ast.json --text ast.txt [--macros macros.txt]] [--keep-dumps] [--check]\n"
		+ "       objc-extern-gen slice <out-dir> <macos-dir> <ios-dir> <maccatalyst-dir> --version <x.y.z> [--sdk-versions text]";

	static function main() {
		var args = Sys.args();
		if (args[0] == "slice") {
			Slice.run(args.slice(1));
			return;
		}
		var platform = "macos";
		var out:Null<String> = null, json:Null<String> = null, text:Null<String> = null, macrosFile:Null<String> = null, check = false, keep = false;
		var sdkPath:Null<String> = null;
		var scope = ["Foundation", "AppKit", "CoreGraphics", "CoreText", "QuartzCore", "UniformTypeIdentifiers"];
		var all = false;
		var i = 0;
		while (i < args.length) {
			switch args[i] {
				case "--json": json = args[++i];
				case "--text": text = args[++i];
				case "--macros": macrosFile = args[++i];
				case "--frameworks":
					var f = args[++i];
					if (f == "all") all = true else scope = f.split(",");
				case "--check": check = true;
				case "--keep-dumps": keep = true;
				case "--platform": platform = args[++i];
				case "--sdk": sdkPath = args[++i];
				case a: out = a;
			}
			i++;
		}
		if (out == null || !["macos", "ios", "maccatalyst"].contains(platform)) {
			Sys.println(USAGE);
			Sys.exit(1);
		}
		sys.FileSystem.createDirectory(out);
		var t = haxe.Timer.stamp();
		var sdk = new Sdk(sdkPath != null ? sdkPath : Sdk.locate(platform), platform);
		Model.Origin.umbrellas = sdk.reexports();
		var tmp = out + "/.clang", ran = json == null || text == null;
		if (all) {
			sys.FileSystem.createDirectory(tmp);
			scope = sdk.allFrameworks(tmp);
			t = stamp('scope: ${scope.length} frameworks', t);
		}
		if (ran) {
			sys.FileSystem.createDirectory(tmp);
			var seen = new Map<String, Bool>(), imports = [];
			for (f in scope) {
				var u = umbrella(sdk, f);
				if (!seen.exists(u)) imports.push('#import $u\n');
				seen.set(u, true);
			}
			sys.io.File.saveContent(tmp + "/sdk.m", imports.join(""));
			json = tmp + "/ast.json";
			text = tmp + "/ast.txt";
			// (the bounds attributes spelled in the types: `__counted_by(n)`, Safe)
			var cc = "clang -fsyntax-only -x objective-c -Xclang -fexperimental-bounds-safety-attributes" + sdk.clangFlags();
			shell('$cc -Xclang -ast-dump=json $tmp/sdk.m > $json');
			shell('$cc -Xclang -ast-dump -fno-color-diagnostics $tmp/sdk.m > $text');
			macrosFile = tmp + "/macros.txt";
			shell('clang -E -dD -x objective-c' + sdk.clangFlags() + ' $tmp/sdk.m > $macrosFile');
			t = stamp("clang (json and text dumps)", t);
		}
		Avail.platform = platform;
		var avail = new Avail();
		avail.read(text);
		t = stamp("availability (text dump)", t);
		var reader = new Reader(avail);
		reader.readFile(json);
		t = stamp("read", t);
		var gen = new Gen(reader, scope);
		if (macrosFile != null) {
			var ms = new Macros();
			ms.read(macrosFile);
			ms.addConstants(reader.constants);
			ms.addEnums(reader.enums);
			gen.macros = ms;
			t = stamp("macros", t);
		}
		if (ran && !keep) removeTree(tmp);
		gen.prepare();
		gen.closure();
		var modules = gen.write(out);
		t = stamp("generate", t);

		function report(title:String, m:Map<String, Int>) {
			Sys.println(title + ":");
			var ks = [for (k in m.keys()) k];
			ks.sort((a, b) -> m.get(b) - m.get(a));
			for (k in ks)
				Sys.println('  ${m.get(k)}\t$k');
		}
		var fws = new Map<String, Int>();
		for (m in modules) {
			var p = m.split(".")[0];
			fws.set(p, (fws.exists(p) ? fws.get(p) : 0) + 1);
		}
		report("modules by package", fws);
		report("generated", gen.count);
		report("skipped", gen.skipped);

		var b = new StringBuf();
		for (k => v in gen.details) {
			b.add(k + ":\n");
			for (x in v)
				b.add("  " + x + "\n");
		}
		sys.io.File.saveContent(out + "/skipped.txt", b.toString());

		// what stays raw memory (Ptr, CString: callers need @:hxmc.unsafe), by why
		report("converted to safe forms", gen.safe.converted);
		report("raw", gen.safe.raw);
		var b = new StringBuf();
		var ks = [for (k in gen.safe.raw.keys()) k];
		ks.sort((a, b) -> gen.safe.raw.get(b) - gen.safe.raw.get(a));
		for (k in ks) {
			b.add('$k: ${gen.safe.raw.get(k)}\n');
			for (x in gen.safe.rawDetails.get(k))
				b.add("  " + x + "\n");
		}
		sys.io.File.saveContent(out + "/raw.txt", b.toString());

		if (check) {
			var b = new StringBuf();
			b.add("// Generated: names every module of the externs, for the type checker.\n");
			b.add("class ObjcExternsCheck {\n\tstatic function main() {\n\t\tif (Sys.args().length > 1000) {\n");
			var k = 0;
			for (m in modules)
				b.add('\t\t\tvar v${k++}:$m = cast null;\n');
			b.add("\t\t}\n\t}\n}\n");
			sys.io.File.saveContent(out + "/ObjcExternsCheck.hx", b.toString());
		}
	}

	public static function removeTree(p:String) {
		if (!sys.FileSystem.exists(p)) return;
		if (sys.FileSystem.isDirectory(p)) {
			for (f in sys.FileSystem.readDirectory(p))
				removeTree('$p/$f');
			sys.FileSystem.deleteDirectory(p);
		} else sys.FileSystem.deleteFile(p);
	}
}
