// The lengths of C functions' arrays that the headers do not annotate
// (`__counted_by`, `__sized_by`), by framework: `function parameter length`,
// the length an integer parameter (in elements; in bytes for a `void *`) or
// a constant, or `raw`: a pointer that stays a Ptr. A function name ending
// in `*` names every function it begins. A length 1 of an optional input
// (`const CGAffineTransform * _Nullable m`) says a value does what NULL does
// (the identity). Safe reads them; a pointer in a function taking a length is
// raw unless listed here.
class Lengths {
	static final ALL:Map<String, Array<String>> = [
		"CoreGraphics" => [
			"CGContextFillRects rects count",
			"CGContextAddRects rects count",
			"CGContextClipToRects rects count",
			"CGContextAddLines points count",
			"CGContextStrokeLineSegments points count",
			"CGContextSetLineDash lengths count",
			"CGContextShowGlyphsAtPositions glyphs count",
			"CGContextShowGlyphsAtPositions Lpositions count",
			"CGPathAddRects rects count",
			"CGPathAddLines points count",
			"CGPathCreateCopyByDashingPath lengths count",
			"CGPath* m 1",
			"CGPathCreate* transform 1",
			"CGGradientCreateWithColorComponents locations count",
			"CGGradientCreateWithColorComponents components raw",
			"CGFontGetGlyphAdvances glyphs count",
			"CGFontGetGlyphAdvances advances count",
			"CGFontGetGlyphBBoxes glyphs count",
			"CGFontGetGlyphBBoxes bboxes count",
			"CGEventKeyboardSetUnicodeString unicodeString stringLength",
			"CGEventKeyboardGetUnicodeString unicodeString maxStringLength",
			"CGEventKeyboardGetUnicodeString actualStringLength 1",
			"CGGetActiveDisplayList activeDisplays maxDisplays",
			"CGGetOnlineDisplayList onlineDisplays maxDisplays",
			"CGGetDisplaysWithPoint displays maxDisplays",
			"CGGetDisplaysWithRect displays maxDisplays",
			"CGGetDisplaysWithOpenGLDisplayMask displays maxDisplays",
			"CGGetDisplayTransferByTable redTable capacity",
			"CGGetDisplayTransferByTable greenTable capacity",
			"CGGetDisplayTransferByTable blueTable capacity",
			"CGSetDisplayTransferByTable redTable tableSize",
			"CGSetDisplayTransferByTable greenTable tableSize",
			"CGSetDisplayTransferByTable blueTable tableSize",
			// (an array the system made, freed by the call)
			"CGReleaseScreenRefreshRects rects raw"
		],
		"CoreText" => [
			"CTFontGetGlyphsForCharacters characters count",
			"CTFontGetGlyphsForCharacters glyphs count",
			"CTFontGetAdvancesForGlyphs glyphs count",
			"CTFontGetAdvancesForGlyphs advances count",
			"CTFontGetBoundingRectsForGlyphs glyphs count",
			"CTFontGetBoundingRectsForGlyphs boundingRects count",
			"CTFontGetOpticalBoundsForGlyphs glyphs count",
			"CTFontGetOpticalBoundsForGlyphs boundingRects count",
			"CTFontGetVerticalTranslationsForGlyphs glyphs count",
			"CTFontGetVerticalTranslationsForGlyphs translations count",
			"CTFontDrawGlyphs glyphs count",
			"CTFontDrawGlyphs positions count",
			"CTFontCreatePathForGlyph matrix 1",
			"CTFontCreateWith* matrix 1"
		],
		"CoreAudio" => [
			"AudioObject* inAddress 1",
			"AudioObjectGetPropertyDataSize inQualifierData inQualifierDataSize",
			"AudioObjectGetPropertyData inQualifierData inQualifierDataSize",
			"AudioObjectSetPropertyData inQualifierData inQualifierDataSize",
			"AudioObjectSetPropertyData inData inDataSize"
		],
		"AudioToolbox" => [
			"AudioUnitSetProperty inData inDataSize",
			"AudioQueueSetProperty inData inDataSize",
			"AudioQueueEnqueueBuffer inPacketDescs inNumPacketDescs",
			"AudioConverterSetProperty inPropertyData inPropertyDataSize",
			"AudioConverterConvertBuffer inInputData inInputDataSize",
			"AudioConverterConvertBuffer ioOutputDataSize 1",
			"AudioFileSetProperty inPropertyData inDataSize",
			"ExtAudioFileSetProperty inPropertyData inPropertyDataSize",
			"AudioFormatGetPropertyInfo inSpecifier inSpecifierSize",
			"AudioFormatGetPropertyInfo outPropertyDataSize 1",
			"AudioFormatGetProperty inSpecifier inSpecifierSize",
			"AudioFormatGetProperty ioPropertyDataSize 1",
			"AudioServicesGetProperty inSpecifier inSpecifierSize",
			"AudioServicesGetProperty ioPropertyDataSize 1",
			"AudioServicesSetProperty inSpecifier inSpecifierSize",
			"AudioServicesSetProperty inPropertyData inPropertyDataSize",
			"MusicDeviceSysEx inData inLength"
		],
		"AppKit" => [
			"NSRectFillList rects count",
			"NSRectClipList rects count",
			"NSRectFillListUsingOperation rects count",
			"NSRectFillListWithGrays rects num",
			"NSRectFillListWithGrays grays num",
			"NSDrawTiledRects sides count",
			"NSDrawTiledRects grays count"
		]
	];

	static var byFunction:Null<Map<String, Map<String, String>>>;
	static var prefixes:Array<{prefix:String, param:String, len:String}> = [];

	// the lengths given for the parameters of function f
	public static function of(f:String):Map<String, String> {
		if (byFunction == null) {
			byFunction = new Map();
			for (lines in ALL)
				for (l in lines) {
					var w = l.split(" ");
					if (StringTools.endsWith(w[0], "*")) {
						prefixes.push({prefix: w[0].substr(0, w[0].length - 1), param: w[1], len: w[2]});
						continue;
					}
					if (!byFunction.exists(w[0])) byFunction.set(w[0], new Map());
					byFunction.get(w[0]).set(w[1], w[2]);
				}
		}
		var m = byFunction.exists(f) ? byFunction.get(f).copy() : new Map();
		for (p in prefixes)
			if (StringTools.startsWith(f, p.prefix) && !m.exists(p.param)) m.set(p.param, p.len);
		return m;
	}
}
