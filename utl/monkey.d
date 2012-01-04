module utl.monkey;

import std.stdio,std.conv,std.bitmanip,
    std.exception,std.string,std.outbuffer,
    std.traits,std.file;
import utl.util,utl.ape,utl.id3;

class MonkeyException : Exception {
    this(string msg) {
        super(msg);
    }
}

class MonkeyFile : UtlFile {
    APE apetags;
    ID3v1 id3tags;
    private string filename;

    this(string filename) {
        file = File(filename,"rb");
        this.filename = filename;

        enforceEx!MonkeyException(isApe(file),"Invalid Monkey's Audio File: " ~ file.name);

        properties = new MonkeyHeader(file);

        try id3tags = new ID3v1(file);
        catch(ID3Exception e) {
            debug writeln(to!string(typeid(this)) ~ ": " ~ e.msg);
        }

        try apetags = new APE(file);
        catch(APEException e) {
            debug writeln(to!string(typeid(this)) ~ ": " ~ e.msg);
        }

        if(apetags)
            metadata = apetags;
        else if(id3tags)
            metadata = id3tags;
        else
            metadata = new APE;
    }

    static bool isApe(ref File file) {
        return file.rawRead(new char[4]) == "MAC ";
    }

    override void save(bool stripID3 = false) {
        scope(exit) file.flush();

        if(exists(filename) && metadata !is null) {
            //core.sys.posix.unistd.truncate(cast(const char*)toStringz(filename),apeTags.tagStart);
            file.open(filename,"rb+");
        }
        else return;

        if(apetags) {
            file.seek(apetags.tagStart);
            file.rawWrite(cast(ubyte[]) apetags);
        }
        if(id3tags && !stripID3) {
            return;
        }
    }
}

class MonkeyHeader : Properties {
    ushort apeVersion;

    this(ref File file) {
        auto v = file.rawRead(new ubyte[2]);
        apeVersion = toInt!(ushort,LE)(v);
        ubyte[] data;

        if(apeVersion <= 3970) {
            data = file.rawRead(new ubyte[24]);

            int p = 4;
            channels = cast(ubyte)toInt!(ushort,LE)(data[p..p+2]); p+=2;
            sample_rate = toInt!(uint,LE)(data[p..p+4]); p+=4;
        }
        else {
            data = file.rawRead(new ubyte[70]);

            int p = 50;
            uint blocks_per_frame   =     toInt!(uint,LE)(data[p..p+4]);   p+=4;
            uint final_frame_blocks =     toInt!(uint,LE)(data[p..p+4]);   p+=4;
            uint total_frames       =     toInt!(uint,LE)(data[p..p+4]);   p+=4;
            bits_per_sample = cast(ubyte) toInt!(ushort,LE)(data[p..p+2]); p+=2;
            channels        = cast(ubyte) toInt!(ushort,LE)(data[p..p+2]); p+=2;
            sample_rate     =             toInt!(uint,LE)(data[p..p+4]);   p+=4;

            samples = --total_frames * blocks_per_frame + final_frame_blocks;

            length = cast(double) samples / sample_rate;
        }

        super();
    }
}