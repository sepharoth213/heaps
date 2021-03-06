package hxd.res;

enum ImageFormat {
	Jpg;
	Png;
	Gif;
}

class Image extends Resource {

	/**
		Specify if we will automatically convert non-power-of-two textures to power-of-two.
	**/
	public static var ALLOW_NPOT = #if (flash && !flash11_8) false #else true #end;
	public static var DEFAULT_FILTER : h3d.mat.Data.Filter = Linear;

	var tex : h3d.mat.Texture;
	var inf : { width : Int, height : Int, format : ImageFormat };

	public function getFormat() {
		getSize();
		return inf.format;
	}

	public function getSize() : { width : Int, height : Int } {
		if( inf != null )
			return inf;
		var f = new hxd.fs.FileInput(entry);
		var width = 0, height = 0, format;
		switch( f.readUInt16() ) {
		case 0xD8FF: // JPG
			format = Jpg;
			f.bigEndian = true;
			while( true ) {
				switch( f.readUInt16() ) {
				case 0xFFC2, 0xFFC0:
					var len = f.readUInt16();
					var prec = f.readByte();
					height = f.readUInt16();
					width = f.readUInt16();
					break;
				default:
					f.skip(f.readUInt16() - 2);
				}
			}
		case 0x5089: // PNG
			format = Png;
			var TMP = hxd.impl.Tmp.getBytes(256);
			f.bigEndian = true;
			f.readBytes(TMP, 0, 6);
			while( true ) {
				var dataLen = f.readInt32();
				if( f.readInt32() == ('I'.code << 24) | ('H'.code << 16) | ('D'.code << 8) | 'R'.code ) {
					width = f.readInt32();
					height = f.readInt32();
					break;
				}
				// skip data
				while( dataLen > 0 ) {
					var k = dataLen > TMP.length ? TMP.length : dataLen;
					f.readBytes(TMP, 0, k);
					dataLen -= k;
				}
				var crc = f.readInt32();
			}
			hxd.impl.Tmp.saveBytes(TMP);

		case 0x4947: // GIF
			format = Gif;
			f.readInt32(); // skip
			width = f.readUInt16();
			height = f.readUInt16();

		default:
			throw "Unsupported texture format " + entry.path;
		}
		f.close();
		inf = { width : width, height : height, format : format };
		return inf;
	}

	public function getPixels( ?fmt : PixelFormat, ?flipY : Bool ) {
		getSize();
		var pixels : hxd.Pixels;
		switch( inf.format ) {
		case Png:
			var bytes = entry.getBytes(); // using getTmpBytes cause bug in E2

			#if (lime && (cpp || neko || nodejs))
			// native PNG loader is faster
			var i = lime.graphics.format.PNG.decodeBytes( bytes, true );
			pixels = new Pixels(inf.width, inf.height, i.data.toBytes(), RGBA );
			#else
			var png = new format.png.Reader(new haxe.io.BytesInput(bytes));
			png.checkCRC = false;
			pixels = Pixels.alloc(inf.width, inf.height, BGRA);
			#if( format >= "3.1.3" )
			var pdata = png.read();
			try {
				format.png.Tools.extract32(pdata, pixels.bytes, flipY);
			} catch( e : Dynamic ) {
				// most likely, out of memory
				hxd.impl.Tmp.freeMemory();
				format.png.Tools.extract32(pdata, pixels.bytes, flipY);
			}
			if( flipY ) pixels.flags.set(FlipY);
			#else
			format.png.Tools.extract32(png.read(), pixels.bytes);
			#end
			#end
		case Gif:
			var bytes = entry.getBytes();
			var gif = new format.gif.Reader(new haxe.io.BytesInput(bytes)).read();
			pixels = new Pixels(inf.width, inf.height, format.gif.Tools.extractFullBGRA(gif, 0), BGRA);
		case Jpg:
			var bytes = entry.getBytes();
			var p = NanoJpeg.decode(bytes);
			pixels = new Pixels(p.width,p.height,p.pixels, BGRA);
		}
		if( fmt != null ) pixels.convert(fmt);
		if( flipY != null ) pixels.setFlip(flipY);
		return pixels;
	}

	public function toBitmap() : hxd.BitmapData {
		getSize();
		var bmp = new hxd.BitmapData(inf.width, inf.height);
		var pixels = getPixels();
		bmp.setPixels(pixels);
		pixels.dispose();
		return bmp;
	}

	function watchCallb() {
		var w = inf.width, h = inf.height;
		inf = null;
		var s = getSize();
		if( w != s.width || h != s.height )
			tex.resize(w, h);
		tex.realloc = null;
		loadTexture();
	}

	function loadTexture() {
		switch( getFormat() ) {
		case Png, Gif:
			function load() {
				// immediately loading the PNG is faster than going through loadBitmap
				tex.alloc();
				var pixels = getPixels(h3d.mat.Texture.nativeFormat, h3d.mat.Texture.nativeFlip);
				if( pixels.width != tex.width || pixels.height != tex.height )
					pixels.makeSquare();
				tex.uploadPixels(pixels);
				pixels.dispose();
				tex.realloc = loadTexture;
				watch(watchCallb);
			}
			if( entry.isAvailable )
				load();
			else
				entry.load(load);
		case Jpg:
			// use native decoding
			entry.loadBitmap(function(bmp) {
				var bmp = bmp.toBitmap();
				tex.alloc();
				
				if( bmp.width != tex.width || bmp.height != tex.height ) {
					var pixels = bmp.getPixels();
					pixels.makeSquare();
					tex.uploadPixels(pixels);
					pixels.dispose();
				} else
					tex.uploadBitmap(bmp);
				
				bmp.dispose();
				tex.realloc = loadTexture;
				watch(watchCallb);
			});
		}
	}

	public function toTexture() : h3d.mat.Texture {
		if( tex != null )
			return tex;
		getSize();
		var width = inf.width, height = inf.height;
		if( !ALLOW_NPOT ) {
			var tw = 1, th = 1;
			while( tw < width ) tw <<= 1;
			while( th < height ) th <<= 1;
			width = tw;
			height = th;
		}
		tex = new h3d.mat.Texture(width, height, [NoAlloc]);
		if( DEFAULT_FILTER != Linear ) tex.filter = DEFAULT_FILTER;
		tex.setName(entry.path);
		loadTexture();
		return tex;
	}

	public function toTile() : h2d.Tile {
		var size = getSize();
		return h2d.Tile.fromTexture(toTexture()).sub(0, 0, size.width, size.height);
	}

}
