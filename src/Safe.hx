import Model;
import Types;

using StringTools;

// how a C function's parameter is passed (hxmc's docs/interop.md, "Typed
// bindings"): as its type, a span (its length another parameter, a
// constant, or the span's own), a String, a typed callback
enum Pass {
	PValue;
	PSpan(elem:HType, readOnly:Bool, len:Null<String>);
	PString;
	PCallback(args:Array<HType>, ret:HType);
}

// a C function's parameters in hxmc's safe forms where the headers (or
// Lengths) tell enough, so calling it needs no raw memory; what stays raw is
// tallied by why (raw.txt)
class Safe {
	var types:Types;

	public var raw = new Map<String, Int>();
	public var rawDetails = new Map<String, Array<String>>();
	public var converted = new Map<String, Int>();

	public function new(types)
		this.types = types;

	public function tally(m:Map<String, Int>, why:String, ?what:String) {
		m.set(why, (m.exists(why) ? m.get(why) : 0) + 1);
		if (m != raw || what == null) return;
		if (!rawDetails.exists(why)) rawDetails.set(why, []);
		rawDetails.get(why).push(what);
	}

	// integer parameters naming a length (`count`, `numGlyphs`, `inDataSize`)
	static var COUNT = ~/(^n$|^len$|count|Count|^num|Num|size|Size|length|Length)/;

	// a parameter named for many (`rects`, `outPacketDescriptions`, `colorTable`)
	static var PLURAL = ~/([^s]s|Table|List|Buffer|Array)$/;

	static function isInteger(h:HType):Bool
		return h.match(HPrim([], "Int") | HPrim(["hxmc"], "I64") | HPrim(["hxmc", "unsafe"], "Int16" | "UInt16" | "Int8" | "UInt8"));

	// a span's element: a C scalar or a struct (an enum: its underlying
	// integer); bytes for void
	function element(h:HType):Null<HType>
		return switch h {
			case HVoid: HPrim(["hxmc", "unsafe"], "UInt8");
			case HPrim([], "Int" | "Float" | "Bool") | HPrim(["hxmc"], "I64") | HPrim(["hxmc", "unsafe"], "Int8" | "UInt8" | "Int16" | "UInt16" | "Float32"): h;
			case HEnum(e):
				var u = enumElement(e);
				u == null || u.match(HEnum(_)) ? null : element(u);
			case HStruct(_): h;
			case _: null;
		}

	public var enumElement:EnumInfo->Null<HType> = _ -> null;

	// one element by default: a struct, or a scalar written (an out-parameter:
	// `CGFloat *ascent`) wider than a byte, in a function taking no length;
	// bytes and characters are buffers (`uint8_t *table`, `UniChar *`)
	static function single(elem:HType, readOnly:Bool):Bool
		return switch elem {
			case HStruct(_): true;
			case HPrim(["hxmc", "unsafe"], "Int8" | "UInt8" | "Int16" | "UInt16"): false;
			case _: !readOnly;
		}

	// the passes of f's parameters (mapped: ps), the raw ones tallied
	public function plan(f:CFunc, ps:Array<{name:String, t:HType}>, ret:HType, where:String):{passes:Array<Pass>, safe:Bool} {
		var passes = [for (_ in ps) PValue];
		var names = [for (p in ps) p.name];
		var given = Lengths.of(f.name);
		var counted = Lambda.exists(ps, p -> isInteger(p.t) && COUNT.match(p.name));
		var why = [for (_ in ps) ""];
		for (i in 0...ps.length) {
			var c = f.params[i];
			if (ps[i].t == Types.CSTRING) {
				passes[i] = PString;
				continue;
			}
			if (ps[i].t != Types.PTR) continue;
			var fp = types.fnPointer(c.type);
			if (fp != null) {
				if (fp.nullable) why[i] = "function pointer, nullable (a typed callback is never NULL)";
				else passes[i] = PCallback(fp.args, fp.ret);
				continue;
			}
			if (c.type.desugared.indexOf("(*") >= 0) {
				why[i] = "function pointer of types a callback cannot take";
				continue;
			}
			var pt = types.pointee(c.type);
			var elem = pt == null || pt.h == null ? null : element(pt.h);
			if (elem == null) {
				why[i] = pointerWhy(c.type, pt);
				continue;
			}
			var b = Types.bounds(c.type), len:Null<String> = null, from = "";
			var o = given.get(c.name);
			if (o == "raw") {
				why[i] = "an array of a length no parameter gives (Lengths)";
				continue;
			}
			if (o != null) {
				len = o;
				from = "Lengths";
			} else if (b != null) {
				if (b.bytes && !elem.match(HPrim(["hxmc", "unsafe"], "UInt8"))) {
					why[i] = "a length in bytes of elements wider than a byte";
					continue;
				}
				len = b.len;
				from = "attribute";
			} else if (c.extent != null) {
				// (`[_Nonnull]`, `[static 3]`: the qualifiers aside)
				len = ~/\b(_Nonnull|_Nullable|_Null_unspecified|__nonnull|__nullable|static|const|restrict|__restrict|CG_[A-Z0-9_]+)\b/g.replace(c.extent.substring(1, c.extent.length - 1), "").trim();
				if (len == "") {
					why[i] = "an array of a length no parameter gives";
					continue;
				}
				from = "array";
			} else if (pt.h == HVoid) {
				why[i] = "void * (an address: no element type nor length)";
				continue;
			} else if (counted) {
				why[i] = "a pointer in a function taking a length: which pointers it counts is not said";
				continue;
			} else if (!single(elem, pt.readOnly)) {
				why[i] = pt.readOnly ? "const pointer to a scalar (an array, of a length not given)" : "pointer to bytes or characters (a buffer, of a length not given)";
				continue;
			} else if (Types.withoutBounds(c.type.qual).indexOf("*") < 0) {
				why[i] = "a pointer type of its own (AudioQueueBufferRef: a handle, whose address matters)";
				continue;
			} else if (PLURAL.match(c.name) || elem.match(HStruct({name: "AudioStreamPacketDescription"}))) {
				why[i] = "an array by its name (outPacketDescriptions, displays), of a length not given";
				continue;
			} else {
				len = "1";
				from = "one element";
			}
			// (the length: a constant, or an integer parameter)
			var n = Std.parseInt(len);
			if (n == null && !(names.indexOf(len) >= 0 && isInteger(ps[names.indexOf(len)].t))) {
				why[i] = "a length that is no integer parameter (" + len + ")";
				continue;
			}
			// (an optional input: NULL says something a span cannot)
			if (pt.readOnly && n != null && from != "Lengths" && Types.nullable(c.type.qual)) {
				why[i] = "an optional input (_Nullable: hxmc passes no NULL span)";
				continue;
			}
			passes[i] = PSpan(elem, pt.readOnly, len);
			tally(converted, "span (" + from + ")");
		}
		// Strings: only where the function can be @:hxmc.safe (its other
		// parameters and its result values, spans or callbacks, no objects)
		var strings = Lambda.exists(passes, p -> p == PString) || ret == Types.CSTRING;
		var safe = strings;
		// (a string result of a function taking strings may point into one:
		// NSGetSizeAndAlignment's, past the call's copy)
		if (ret == Types.CSTRING && Lambda.exists(passes, p -> p == PString)) safe = false;
		if (strings) {
			for (i in 0...ps.length)
				if (passes[i] == PValue && !value(ps[i].t)) safe = false;
			if (ret != Types.CSTRING && ret != HVoid && !value(ret)) safe = false;
		}
		for (i in 0...ps.length)
			switch passes[i] {
				case PString if (!safe):
					passes[i] = PValue;
					why[i] = "const char * of a function taking or returning an object or raw memory (a String needs @:hxmc.safe, which takes neither)";
				case PString: tally(converted, "String");
				case PCallback(_, _): tally(converted, "typed callback");
				case _:
			}
		for (i in 0...ps.length)
			if (passes[i] == PValue && (ps[i].t == Types.PTR || ps[i].t == Types.CSTRING))
				tally(raw, "C function: " + (why[i] == "" ? "pointer" : why[i]), where + " " + ps[i].name);
		if (ret == Types.CSTRING) tally(safe ? converted : raw, safe ? "String result" : "C function: const char * result of a function that cannot be @:hxmc.safe", where);
		else if (ret == Types.PTR) tally(raw, "C function: pointer result (a span result is for kernels)", where);
		return {passes: passes, safe: safe};
	}

	// what @:hxmc.safe passes as it is: scalars, enums, structs (of them)
	static function value(h:HType):Bool
		return switch h {
			case HPrim(["hxmc", "unsafe"], "Ptr" | "CString"): false;
			case HPrim(["hxmc", "objc"], _): false;
			case HPrim(_, _) | HEnum(_): true;
			case HStruct(_): true;
			case _: false;
		}

	function pointerWhy(t:CType, pt:Null<{h:Null<HType>, why:String, readOnly:Bool}>):String {
		if (~/\b(NSError|CFErrorRef)\b/.match(t.qual + " " + t.desugared)) return "an error out-parameter (NSError **, CFErrorRef *: hxmc has no out-parameter of objects but COM's)";
		if (pt == null) return "a pointer to a pointer (written back: hxmc has no out-parameter of addresses)";
		if (pt.why == "struct not defined" || pt.why == "opaque typedef") return "an opaque handle (AUGraph, CGPDFDictionaryRef: a pointer to a struct the headers do not define)";
		if (pt.why.startsWith("struct") || pt.why == "union") return "a pointer to a struct hxmc does not lay out (" + pt.why + ")";
		return switch pt.h {
			case HCF(_, _) | HClass(_, _, _) | HId(_) | HProto(_, _) | HPrim(["hxmc", "unsafe"], "Ptr"): "a pointer to an object or an address (written back: hxmc has no out-parameter of objects but COM's)";
			case _: "a pointer to a type spans do not hold" + (pt.why != "" ? " (" + pt.why + ")" : "");
		}
	}

	// a message's parameter that stays raw: why (hxmc's messages take none of
	// the typed forms; an `error` parameter is Cocoa's NSError **)
	public function message(t:HType, name:String, where:String) {
		if (t != Types.PTR && t != Types.CSTRING) return;
		var why = t == Types.CSTRING ? "message: const char * (a message takes no String)"
			: ~/^(out)?[eE]rror$/.match(name) ? "message: NSError ** (a message takes no out-parameter)"
			: "message: pointer (a message takes no span, out-parameter or typed callback)";
		tally(raw, why, where + " " + name);
	}
}
