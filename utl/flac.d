module utl.flac;

import std.stdio,std.conv,std.bitmanip,
    std.file,std.exception,std.typecons,
    std.regex,std.string,std.outbuffer,
    std.traits,std.md5,std.algorithm,
    std.ascii;
import std.typetuple;
import core.bitop;

import utl.util,utl.id3,utl.vorbis;

class FlacException : Exception {
    this(string msg) {
        super(msg);
    }
}

class MetadataBlockHeader {
    bool last;
    ubyte block_type;
    uint block_length;

    this(ubyte[] data) {
        last = cast(bool) (data[0] >> 7);
        block_type = (data[0] & 127);
        block_length = toInt!(uint,BE)(data[1..$]);
    }

    this(bool last, ubyte block_type, uint block_length) {
        this.last = last;
        this.block_type = block_type;
        this.block_length = block_length;
    }

    this(ref File f) {
        ubyte[4] data;
        f.rawRead(data);
        this(data);
    }
    alias asBytes this;

    @property {
        private ubyte[] asBytes() {
            return write.toBytes();
        }

        bool isLast() {
            return last;
        }

        void length(uint newlen) {
            if(block_length != newlen)
                block_length = newlen;
        }

        const uint length() {
            return block_length;
        }
    }

    private OutBuffer write() {
        auto buf = new OutBuffer;
        buf.reserve(4);

        buf.write(cast(ubyte) ((last << 7) | block_type));
        buf.write(pack!(BE)(block_length,3));

        return buf;
    }

    T opCast(T)() {
        static if(is(T == OutBuffer)) {
            return write();
        }
        else static if(is(T == ubyte[])) {
            return write().toBytes();
        }
    }

    string toString() {
        return "last: " ~ to!string(last) ~ " | type: "
            ~ to!string(block_type) ~ " | length: " ~ to!string(block_length);
    }
}

alias Tuple!(StreamInfo,Padding,Application,SeekTable,VorbisComment,CueSheet,Picture) Blocks;

alias MetadataBlock Application;

template BlockType(T) {
    enum BlockType = staticIndexOf!(T,Blocks.Types);
}

class MetadataBlock {
    MetadataBlockHeader header;
    ubyte[] data;

    this(ubyte[] input) {
        data = input.dup;
    }

    this(ref File f, MetadataBlockHeader _header) {
        header = _header;
        data = new ubyte[header.block_length];
        f.rawRead(data);
    }

    private OutBuffer write() {
        auto buf = new OutBuffer;

        buf.write(cast(ubyte[]) header);
        buf.write(data);

        return buf;
    }

    T opCast(T)() {
        static if(is(T == OutBuffer)) {
            return write();
        }
        else static if(is(T == ubyte[])) {
            return write().toBytes();
        }
    }
}

class StreamInfo : Properties {
private {
    MetadataBlockHeader header;

    ushort min_block_size;
    ushort max_block_size;
    uint min_frame_size;
    uint max_frame_size;
    ubyte[] md5_raw;
    string md5 = "";
    ushort bitrate;
    double file_length;

    this(ubyte[] data) {
        int p;

        min_block_size = toInt!(ushort,BE)(data[p..p+2]); p+=2;
        max_block_size = toInt!(ushort,BE)(data[p..p+2]); p+=2;
        min_frame_size = toInt!(uint,  BE)(data[p..p+3]); p+=3;
        max_frame_size = toInt!(uint,  BE)(data[p..p+3]); p+=3;

        auto tmp = toInt!(uint,BE)(data[p..p+4]); p+=4;
        sample_rate = tmp >> 12;
        channels = cast(ubyte)(((tmp >> 9) & 7) + 1);
        bits_per_sample = cast(ubyte)(((tmp >> 4) & 31) + 1);
        samples = cast(uint)(data[p] << 28) << 4 |
            toInt!(ulong,BE)(data[p..p+4]); p+=4;

        md5_raw = data[p..$];
        const ubyte[16] a = md5_raw;

        md5 = digestToString(a);

        length = cast(double) samples / sample_rate;

        super();
    }

    OutBuffer write() {
        auto buf = new OutBuffer;
        buf.reserve(38);

        buf.write(header);

        buf.write(pack!(BE)(min_block_size));
        buf.write(pack!(BE)(max_block_size));

        buf.write(pack!(BE)(min_frame_size,3));
        buf.write(pack!(BE)(max_frame_size,3));

        ubyte x;
        buf.write(pack!(BE)(sample_rate >> 4,2));
        x = cast(ubyte) (sample_rate << 4);
        x |= (channels - 1) << 1;
        x |= ((bits_per_sample - 1) >> 4);
        buf.write(x);

        buf.write(cast(ubyte) (((bits_per_sample - 1) << 4) | (samples >> 32)));

        buf.write(bswap(cast(uint)samples));

        buf.write(md5_raw);

        return buf;
    }
    }

public {
    this(ref File file, uint block_length) {
        ubyte[] data = new ubyte[block_length];
        file.rawRead(data);
        this(data);
    }
    this(ref File file, MetadataBlockHeader _header) {
        header = _header;
        auto data = file.rawRead(new ubyte[header.length]);
        this(data);
    }

    T opCast(T)() {
        static if(is(T == OutBuffer)) {
            return write();
        }
        else static if(is(T == ubyte[])) {
            return write().toBytes();
        }
    }
    }
}

class Padding {
    MetadataBlockHeader header;

    this(ref File f, MetadataBlockHeader _header) {
        header = _header;
        f.seek(header.block_length,SEEK_CUR);
    }

    alias asBytes this;

    @property {
        private ubyte[] asBytes() {
            return write().toBytes();
        }

        void length(uint newlen) {
            if(length != newlen)
                header.length = newlen;
        }

        const uint length() {
            return header.length;
        }
    }

    private OutBuffer write() {
        auto buf = new OutBuffer;
        buf.write(header);
        buf.write(new ubyte[header.block_length]);

        return buf;
    }

    T opCast(T)() {
        static if(is(T == OutBuffer)) {
            return write();
        }
        else static if(is(T == ubyte[])) {
            return write().toBytes();
        }
    }
}

class SeekTable {
    MetadataBlockHeader header;
    SeekPoint[] seek_points;

    private this(ubyte[] data) {
        int p;
        seek_points.length = data.length / 18;

        foreach(ref s; seek_points) {
            s.first_sample_num = toInt!(ulong,BE)(data[p..p+8]); p+=8;
            if(s.first_sample_num == 0xFFFFFFFFFFFFFFFF && data.length>p+10) {
                p+=10;
                continue;
            }
            s.offset = toInt!(ulong,BE)(data[p..p+8]); p+=8;
            s.samples = toInt!(ushort,BE)(data[p..p+2]); p+=2;
        }
    }

    this(ref File f, MetadataBlockHeader _header) {
        header = _header;
        ubyte[] data = new ubyte[header.block_length];
        f.rawRead(data);

        this(data);
    }

    private OutBuffer write() {
        auto buf = new OutBuffer;
        buf.reserve(4 + (18 * seek_points.length));

        buf.write(cast(ubyte[])header);

        foreach(s; seek_points) {
            buf.write(pack!BE(s[0]));
            buf.write(pack!BE(s[1]));
            buf.write(pack!BE(s[2]));
        }

        return buf;
    }

    T opCast(T)() {
        static if(is(T == OutBuffer)) {
            return write();
        }
        else static if(is(T == ubyte[])) {
            return write().toBytes();
        }
    }
}

alias Tuple!(ulong,"first_sample_num",ulong,"offset",ushort,"samples") SeekPoint;

class CueSheet {
    MetadataBlockHeader header;
    string catalog_no;
    ulong lead_in_samples;
    bool isCD;
    ubyte number_of_tracks;
    CueSheetTrack[] tracks;
    
    this(ref File f, MetadataBlockHeader _header) {
        header = _header;
        ubyte[] data = new ubyte[header.block_length];
        f.seek(data.length,SEEK_CUR);

        //this(data);
    }

    private OutBuffer write() {
        auto buf = new OutBuffer;

        return buf;
    }

    T opCast(T)() {
        static if(is(T == OutBuffer)) {
            return write();
        }
        else static if(is(T == ubyte[])) {
            return write().toBytes();
        }
    }
}

class CueSheetTrack {
    ulong track_offset;
    ubyte track_number;
    string isrc;
    bool track_type;
    bool pre_emphasis;
    //ubyte index_points;
    CueSheetTrackIndex[] track_indexes;

    this(string s,bool isCD) {
        int p;
        track_offset = parse!ulong(s[p..p+64],2); p+=64;
        track_number = parse!ubyte(s[p..p+8],2); p+=8;
        for(int i=p;i<p+(12*8);i+=8) {
            isrc ~= cast(char)parse!ubyte(s[i..i+8],2);
        }
        p += 12 * 8;
        track_type = cast(bool)to!ubyte(s[p]); ++p;
        pre_emphasis = cast(bool)to!ubyte(s[p]); ++p;
        p += 110;
        track_indexes.length = parse!ubyte(s[p..p+8]); p+=8;
        foreach(t;track_indexes) {
            t = new CueSheetTrackIndex(s[p..$],isCD);
            p += 96;
        }
    }
}

class CueSheetTrackIndex {
    ulong index_offset;
    ubyte index_point_num;

    this(string s,bool isCD) {
        index_offset = parse!ulong(s[0..64],2);
        index_point_num = parse!ubyte(s[64..72],2);
    }
}

class Picture {
    MetadataBlockHeader header;
    uint picture_type;
    string mime_type;
    string description;
    uint width;
    uint height;
    uint colour_depth;
    uint no_colours;
    uint data_length;
    ubyte[] picture_data;

    private this(ubyte[] data) {
        int p;

        picture_type = toInt!(uint,BE)(data[p .. p + 4]); p+=4;
        mime_type.length = toInt!(uint,BE)(data[p .. p + 4]); p+=4;
        mime_type = cast(string) data[p .. p + mime_type.length]; p+=mime_type.length;
        description.length = toInt!(uint,BE)(data[p .. p + 4]); p+=4;
        description = cast(string) data[p .. p + description.length]; p+=description.length;
        width = toInt!(uint,BE)(data[p .. p + 4]); p+=4;
        height = toInt!(uint,BE)(data[p .. p + 4]); p+=4;
        colour_depth = toInt!(uint,BE)(data[p .. p + 4]); p+=4;
        no_colours = toInt!(uint,BE)(data[p .. p + 4]); p+=4;
        data_length = toInt!(uint,BE)(data[p .. p + 4]); p+=4;
        picture_data = data[p .. p + data_length];
    }

    this(ref File f, uint block_length) {
        ubyte[] data = new ubyte[block_length];
        f.rawRead(data);

        this(data);
    }
    this(ref File f, MetadataBlockHeader _header) {
        header = _header;
        ubyte[] data = new ubyte[header.block_length];
        f.rawRead(data);

        this(data);
    }

    private OutBuffer write() {
        auto buf = new OutBuffer;

        buf.write(cast(ubyte[]) header);
        buf.write(pack!(BE)(picture_type));
        buf.write(pack!(BE)(mime_type.length));
        buf.write(mime_type);
        buf.write(pack!(BE)(description.length));
        buf.write(description);
        buf.write(pack!(BE)(width));
        buf.write(pack!(BE)(height));
        buf.write(pack!(BE)(colour_depth));
        buf.write(pack!(BE)(no_colours));
        buf.write(pack!(BE)(data_length));
        buf.write(picture_data);

        return buf;
    }

    T opCast(T)() {
        static if(is(T == OutBuffer)) {
            return write();
        }
        else static if(is(T == ubyte[])) {
            return write().toBytes();
        }
    }
}

enum defaultPaddingSize = 8192;
enum minPaddingSize = 4096;

T makePositive(T)(T a) pure nothrow @safe if(isSigned!T) {
    return a < 0 ? -a : a;
}

private string generateSwitches(T...)()
{
    string result = "switch(headers[$-1].block_type) {\n";
    foreach(i,Type; T) {
        string var = "blocks[" ~ to!string(i) ~ "]";
        result ~= "case " ~ to!string(i) ~ ":\n"
            ~ var ~ " = new typeof(" ~ var ~ ")(file,headers[$-1]);\n"
            ~ "break;\n";
    }
    return result ~ "case 6:\n"
        ~ "pictures ~= new Picture(file,headers[$-1]);\n"
        ~ "break;\n"
        ~ "default:\n"
        ~ "assert(0, q{Bad index: } ~ to!string(headers[$-1].block_type));\n}";
}

class FlacFile : UtlFile {
private {
    Flac flac;
    ID3v2 id3tags;
}
public {
    string filename;
    uint initialSize;

    this(string filename) {
        file = File(filename,"rb");
        this.filename = filename;

        try id3tags = new ID3v2(file);
        catch(ID3Exception e) {
            file.seek(0);
        }

        enforce(isFlac(file),new FlacException("flac doesnt start at: " ~ to!string(file.tell)));
        flac = new Flac(file);
        properties = flac.blocks[BlockType!StreamInfo];
        metadata = flac.blocks[BlockType!VorbisComment];
        initialSize = flac.size();
    }

    static bool isFlac(ref File file) {
        if(file.rawRead(new char[4]) != "fLaC") {
            file.seek(0);
            return file.rawRead(new char[4]) == "fLaC";
        }
        return true;
    }

    @property bool hasPadding() {
        return flac.blocks[BlockType!Padding] !is null;
    }

    uint calcPadding(int difference) {
        if(hasPadding && flac.blocks[BlockType!Padding].length > makePositive(difference))
            return flac.blocks[BlockType!Padding].length + difference;
        else
            return minPaddingSize;
    }

    uint bufferSize() {
        return 1024;
    }

    void save(bool stripID3 = false) {
        auto buf = flac.write;
        uint newSize = flac.size();

        if(exists(filename))
            file.open(filename,"rb+");
        else return;

        writeln("Saving file: " ~ filename);
        writeln("Padding: ",calcPadding(initialSize - newSize));
        if(!hasPadding || calcPadding(initialSize - newSize) == minPaddingSize) {
            writeln("Rewriting file: " ~ filename);
            flac.blocks[BlockType!Padding].header.block_length = calcPadding(initialSize - newSize);
            writeln(flac.blocks[BlockType!Padding].header.block_length);
            buf.write(cast(ubyte[]) flac.blocks[BlockType!Padding]);

            //auto a = cast(char*)toStringz(file.name ~ "XXXXXX");
            auto tmpname = mkstemp(file.name);
            File tmpfile = File(tmpname,"wb");

            file.seek(initialSize);
            tmpfile.rawWrite(buf.toBytes);

            while(!file.eof) {
                auto buffer = file.rawRead(new ubyte[1024]);
                tmpfile.rawWrite(buffer);
            }

            file.close();
            tmpfile.close();

            std.file.remove(filename);
            std.file.rename(tmpname,filename);
        }
        else {
            writeln("No need to rewrite file: " ~ filename);
            flac.blocks[BlockType!Padding].header.block_length += initialSize - newSize;
            buf.write(cast(ubyte[]) flac.blocks[BlockType!Padding]);
            file.rawWrite(buf.toBytes);
        }

        if(file.isOpen) {
            file.flush();
        }
        else file.open(filename,"rb");
    }
}
}

class Flac {
    MetadataBlockHeader[] headers;
    Blocks blocks;
    Picture[] pictures;
    MetadataBlock[] unknown_blocks;
    string marker = "fLaC";

    this(ref File file) {
        headers ~= new MetadataBlockHeader(file);
        enforce(headers[0].block_type == BlockType!StreamInfo,
                "No stream info, invalid FLAC");

        blocks[BlockType!StreamInfo] = new StreamInfo(file, headers[0]);

        while(!headers[$-1].isLast()) {
            headers ~= new MetadataBlockHeader(file);
            mixin(generateSwitches!(blocks.Types[0..$-1]));
        }
    }

    OutBuffer write() {
        auto buf = new OutBuffer;
        buf.write(marker);
        writeln("size: ",size);
        foreach(i,T; blocks.Types) {
            if(blocks[BlockType!T] !is null) {
                writeln(typeid(T));
                if(is(T == Padding))
                    continue;
                writeln("in loop");
                buf.write(cast(ubyte[])blocks[BlockType!T]);
            }
        }
        writeln(buf.toBytes.length);

        return buf;
    }

    /**
       Returns the total size of metadata in flac_file
    */
    @property uint size() {
        uint sum;
        foreach(h;headers) {
//             if(h.block_type == BlockType!Padding)
//                 continue;
            sum += h.block_length + 4;
        }
        return sum;
    }
}