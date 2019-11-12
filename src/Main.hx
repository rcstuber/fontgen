import sys.io.File;
import sys.FileSystem;
import haxe.Json;
import haxe.io.Path;
import binpacking.MaxRectsPacker;
import GlyphRender;
import DataTypes;
import msdfgen.Msdfgen;

class Main {
	static inline var SIZE:Int = 4096;
	
	static var atlasWidth : Int;
	static var atlasHeight : Int;
	
	public static var verbose:Bool = false;
	public static var warnings:Bool = true;
	public static var info:Bool = false;
	public static var timings:Bool = false;
	public static var printMissing:Bool = false;
	
	public static var globalNonprint:Bool = false;
	
	static function main() {
		
		var configs = readInput();
		
		inline function ts() return haxe.Timer.stamp();
		inline function timeStr(ts:Float) return Std.string(Math.round(ts * 1000)) + "ms";
		
		var start = ts();
		Msdfgen.initializeFreetype();
		
		for (config in configs) {
			
			var rasterMode = config.mode == Raster;
			var dfSize = rasterMode ? 0 : config.dfSize;
			var halfDF = (dfSize * .5);
			var fontSize = config.fontSize;
			
			if (info) {
				Sys.println("[Info] Rendering mode: " + config.mode);
				Sys.println("[Info] Font size: " + config.fontSize);
				if (!rasterMode) Sys.println("[Info] SDF size: " + config.dfSize);
				Sys.println("[Info] Output format: text .fnt");
			}
			
			Msdfgen.setParameters(dfSize, fontSize);
			
			var stamp = ts();
			var renderers:Array<GlyphRender> = [];
			for ( inp in config.inputs ) {
				if (info) Sys.println("[Info] TTF: " + inp);
				renderers.push(new GlyphRender(inp));
			}
			var ttfParse = ts();
			if (timings) Sys.println("[Timing] Parsed ttf: " + timeStr(ttfParse - stamp));
			
			// Find all corresponding glyphs to render.
			var missing:Array<Int> = [];
			var glyphs:Array<GlyphInfo> = [];
			var inserted:Array<Int> = [];
			var skipNonprint:Bool = config.options.indexOf("allownonprint") == -1 && !globalNonprint;
			for ( cset in Charset.parse(config.charset) ) {
				for (char in cset) {
					if (skipNonprint && Charset.NONPRINTING.contains(char)) continue;
					if (inserted.indexOf(char) != -1) continue; // Already rendering with another charset.
					var found = false;
					for (renderer in renderers) {
						var glyph = renderer.get(char);
						if (glyph == null) continue;
						glyphs.push(glyph);
						renderer.renderGlyphs.push(glyph);
						found = true;
						inserted.push(char);
						break;
					}
					if (!found) missing.push(char);
				}
			}
			
			var charsetProcess = ts();
			if ((warnings || printMissing) && missing.length != 0) {
				Sys.println('[Warn] Could not locate ${missing.length} glyphs!');
				if (printMissing) {
					Sys.print(missing[0] + ": " + String.fromCharCode(missing[0]));
					var i = 1, l = missing.length;
					while (i < l) {
						var char = missing[i++];
						Sys.print(", " + char + ": " + String.fromCharCode(char));
					}
					Sys.print("\n");
				}
			}
			if (info) Sys.println('[Info] Rendering ${inserted.length} glyphs');
			if (timings) Sys.println("[Timing] Glyph lookup: " + timeStr(charsetProcess - ttfParse));
			
			var extendWidth = config.padding.left + config.padding.right + dfSize + config.spacing.x;
			var extendHeight = config.padding.top + config.padding.bottom + dfSize + config.spacing.y;
			
			packGlyphs(glyphs, fontSize, extendWidth, extendHeight);
			
			extendWidth -= config.spacing.x;
			extendHeight -= config.spacing.y;
			
			var glyphPacking = ts();
			if (info) Sys.println('[Info] Atlas size: ${atlasWidth}x${atlasHeight}');
			if (timings) Sys.println("[Timing] Glyph packing: " + timeStr(glyphPacking - charsetProcess));
			
			Msdfgen.beginAtlas(atlasWidth, atlasHeight, rasterMode ? 0 : 0xff);
			var paddingLeft = config.padding.left;
			var paddingTop = config.padding.top;
			var paddingBottom = config.padding.bottom;
			var dfCorrX, dfCorrY;
			if (rasterMode) {
				dfCorrX = halfDF;
				dfCorrY = halfDF;
			} else {
				dfCorrX = halfDF - 0.5;
				dfCorrY = halfDF - 0.5;
			}
			
			for (renderer in renderers) {
				if (renderer.renderGlyphs.length == 0) continue;
				if (info)
					Sys.println("[Info] Started rendering glyphs from " + renderer.file);
				
				
				inline function glyphWidth(g:GlyphInfo) return g.width + extendWidth;
				inline function glyphHeight(g:GlyphInfo) return g.height + extendHeight;
				inline function canvasX(g:GlyphInfo) return Std.int(g.rect.x);
				inline function canvasY(g:GlyphInfo) return Std.int(g.rect.y);
				inline function translateX(g:GlyphInfo) return Math.ceil(halfDF) - 0.5 - g.xOffset + paddingLeft;
				inline function translateY(g:GlyphInfo) return Math.floor(halfDF) + 0.5 - g.descent + paddingBottom;
				
				switch (config.mode) {
					case MSDF:
						for (g in renderer.renderGlyphs) {
							if (g.width != 0 && g.height != 0)
								Msdfgen.generateMSDFGlyph(g.renderer.slot, g.char, glyphWidth(g), glyphHeight(g), canvasX(g), canvasY(g), translateX(g), translateY(g), g.isCCW);
						}
					case SDF:
						for (g in renderer.renderGlyphs) {
							if (g.width != 0 && g.height != 0)
								Msdfgen.generateSDFGlyph(g.renderer.slot, g.char, glyphWidth(g), glyphHeight(g), canvasX(g), canvasY(g), translateX(g), translateY(g), g.isCCW);
						}
					case PSDF:
						for (g in renderer.renderGlyphs) {
							if (g.width != 0 && g.height != 0)
								Msdfgen.generatePSDFGlyph(g.renderer.slot, g.char, glyphWidth(g), glyphHeight(g), canvasX(g), canvasY(g), translateX(g), translateY(g), g.isCCW);
						}
					case Raster:
						for (g in renderer.renderGlyphs) {
							if (g.width != 0 && g.height != 0)
								Msdfgen.rasterizeGlyph(g.renderer.slot, g.char, glyphWidth(g), glyphHeight(g), canvasX(g) + paddingLeft, canvasY(g) + paddingTop);
						}
				}
			}
			
			var pngPath = Path.withExtension(config.output, "png");
			Msdfgen.endAtlas(pngPath);
			var glyphRendering = ts();
			if (info) Sys.println("[Info] Writing PNG file to " + pngPath);
			if (timings) Sys.println("[Timing] Glyph rendering: " + timeStr(glyphRendering - glyphPacking));
			
			// TODO: Optimize: Start building file right away.
			var file = new FntFile(config, renderers[0]);
			
			file.texture = Path.withoutDirectory(pngPath);
			file.textureWidth = atlasWidth;
			file.textureHeight = atlasHeight;
			
			for (g in glyphs) {
				file.chars.push({
					id: g.char,
					x: Std.int(g.rect.x),
					y: Std.int(g.rect.y),
					w: g.width + extendWidth,
					h: g.height + extendHeight,
					xa: g.advance,
					xo: g.xOffset - paddingLeft - Math.ceil(halfDF),
					yo: (file.base - g.yOffset) - paddingTop - Math.ceil(halfDF),
				});
			}
			
			final len = inserted.length;
			for (i in 0...len) {
				var left = glyphs[i];
				var slot = left.renderer.slot;
				for (j in (i+1)...len) {
					var right = glyphs[j];
					if (right.renderer.slot == slot) {
						var kern = Msdfgen.getKerning(slot, left.char, right.char);
						if (kern != 0) {
							file.kernings.push({ first: left.char, second: right.char, amount: kern });
						}
						kern = Msdfgen.getKerning(slot, right.char, left.char);
						if (kern != 0) {
							file.kernings.push({ first: right.char, second: left.char, amount: kern });
						}
					}
				}
			}
			
			Msdfgen.unloadFonts();
			File.saveContent(Path.withExtension(config.output, "fnt"), file.writeString());
			
			var ttfGen = ts();
			if (timings) {
				Sys.println("[Timing] FNT generation: " + timeStr(ttfGen - glyphRendering));
				Sys.println("[Timing] Total config processing time: " + timeStr(ttfGen - stamp));
			}
			
		}
		
		Msdfgen.deinitializeFreetype();
		if (timings && configs.length > 1) {
			Sys.println("[Timing] Total work time: " + timeStr(ts() - start));
		}
	}
	
	static function packGlyphs(glyphs:Array<GlyphInfo>, fontSize:Int, extendWidth:Int, extendHeight:Int) {
		
		glyphs.sort(glyphSort);
		
		var packer = new MaxRectsPacker(SIZE, SIZE, false);
		var xMax = 0;
		var yMax = 0;
		for (g in glyphs) {
			var rect = g.rect = packer.insert(g.width + extendWidth, g.height + extendHeight, BestShortSideFit);
			var tmp = Std.int(rect.x + rect.width);
			if (tmp > xMax) xMax = tmp;
			tmp = Std.int(rect.y + rect.height);
			if (tmp > yMax) yMax = tmp;
		}
		atlasWidth = xMax;
		atlasHeight = yMax;
	}
	
	static function readInput():Array<GenConfig> {
		var args = Sys.args();
		if (args.length == 0) printHelp();
		var flags = args.filter( (a) -> a.charCodeAt(0) == '-'.code );
		args = args.filter( (a) -> a.charCodeAt(0) != '-'.code );
		
		for (arg in flags) {
			switch (arg.toLowerCase()) {
				case "-verbose":
					verbose = true;
					warnings = true;
					info = true;
					timings = true;
					printMissing = true;
				case "-nowarnings":
					warnings = false;
				case "-info":
					info = true;
				case "-timings":
					timings = true;
				case "-printmissing":
					printMissing = true;
				case "-silent":
					verbose = false;
					warnings = false;
					info = false;
					timings = false;
					printMissing = false;
				case "-allownonprint":
					globalNonprint = true;
				case "-help":
					printHelp();
			}
		}
		for (arg in args) {
			if (FileSystem.exists(arg)) {
				Sys.setCwd(Path.directory(arg));
				return jsonConfig(File.getContent(arg));
			}
			// TODO: CLI
		}
		printHelp();
		return null;
	}
	
	static function printHelp() {
		#if (hlc || cpp)
		final exe = Sys.systemName() == "Windows" ? "fontgen.exe" : "fontgen";
		#elseif hl
		final exe = "hl fontgen.hl";
		#else
		final exe = "{haxe eval here}";
		#end
		Sys.println(StringTools.replace(haxe.Resource.getString("help"), "{{exe}}", exe));
		Sys.exit(0);
	}
	
	static function jsonConfig(inp:String):Array<GenConfig> {
		var cfg:Dynamic = Json.parse(inp);
		if (Std.is(cfg, Array)) {
			var arr:Array<GenConfig> = cfg;
			for (conf in arr) {
				fillDefaults(conf);
			}
			return arr;
		} else {
			return [fillDefaults(cfg)];
		}
	}
	
	static function fillDefaults(cfg:GenConfig):GenConfig {
		if ( cfg.mode == null ) cfg.mode = MSDF;
		else {
			cfg.mode = (cfg.mode:String).toLowerCase();
			cfg.mode.validate();
		}
		if ( cfg.fontSize == null ) throw "Font size should be specified!";
		if ( cfg.inputs == null ) {
			if ( cfg.input == null || !FileSystem.exists(cfg.input) ) throw "Path to TTF file should be specified!";
			cfg.inputs = [cfg.input];
		} else {
			if ( cfg.input != null ) cfg.inputs.unshift(cfg.input);
			for ( inp in cfg.inputs ) {
				if (!FileSystem.exists(inp)) throw "Input file does not exists: " + inp;
			}
		}
		if ( cfg.options == null ) cfg.options = [];
		else {
			for (i in 0...cfg.options.length) {
				cfg.options[i] = cfg.options[i].toLowerCase();
			}
		}
		if ( cfg.output == null ) throw "Output to FNT file should be specified!";
		if ( cfg.charset == null ) cfg.charset = ["ansi"];
		if ( cfg.dfSize == null ) cfg.dfSize = cfg.mode == Raster ? 0 : 6;
		if ( cfg.padding == null ) cfg.padding = { top: 0, bottom: 0, left: 0, right: 0 };
		else {
			if ( cfg.padding.top == null ) cfg.padding.top = 0;
			if ( cfg.padding.bottom == null ) cfg.padding.bottom = 0;
			if ( cfg.padding.left == null ) cfg.padding.left = 0;
			if ( cfg.padding.right == null ) cfg.padding.right = 0;
		}
		if ( cfg.spacing == null ) cfg.spacing = { x: 1, y: 1 };
		else {
			if ( cfg.spacing.x == null) cfg.spacing.x = 0;
			if ( cfg.spacing.y == null) cfg.spacing.y = 0;
		}
		return cfg;
	}
	
	static function glyphSort(a:GlyphInfo, b:GlyphInfo):Int
	{
		return Math.round(a.height - b.height);
	}
	
}