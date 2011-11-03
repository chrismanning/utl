module utl.wavpack;

import std.stdio,std.conv,std.bitmanip,
    std.file,std.exception,std.typecons,
    std.regex,std.string,std.outbuffer,
    std.traits,std.file;
import utl.util,utl.ape,utl.id3;

class WavPackException : Exception {
    this(string msg) {
        super(msg);
    }
}

private static immutable ubyte[4] BPS = [8,16,24,32];
private static immutable uint[15] SampleRates =
    [6000, 8000, 9600, 11025, 12000, 16000, 22050,
    24000, 32000, 44100, 48000, 64000, 88200, 96000, 192000];

class WavPackFile : UtlFile {
    string filename;
    ID3v1 id3tags;
    APE apetags;

    this(string filename) {
        file = File(filename,"rb");
        this.filename = filename;
        this(file);
    }
    this(ref File file) {
        enforceEx!WavPackException(WavPackFile.isWavPack(file),"Not a wavpack: " ~ file.name);
        properties = new WavPackInfo(file);

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

    static bool isWavPack(ref File file) {
        return file.rawRead(new char[4]) == "wvpk";
    }

    void save(bool stripID3 = false) {
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

private class WavPackInfo : Properties {
    this(ref File file) {
        auto data = file.rawRead(new ubyte[28]);

        int p;

        uint blockSize = toInt!(uint,LE)(data[p..p+4]); p+=8;
        samples = toInt!(uint,LE)(data[p..p+4]); p+=12;
        uint flags = toInt!(uint,LE)(data[p..p+4]);
        bits_per_sample = BPS[flags & 3];
        sample_rate = SampleRates[(flags >> 23) & 15];

        length = cast(double) samples / sample_rate;

        if((flags >> 11) & 1) {
            while(file.tell < blockSize) {
                ubyte id = file.rawRead(new ubyte[1])[0];
                uint size;

                if(id & 0x80) {
                    auto z = file.rawRead(new ubyte[3]);
                    size = toInt!(uint,LE)(z);
                }
                else {
                    size = file.rawRead(new ubyte[1])[0];
                    if(id & 0x40)
                        --size;
                }

                if(id == 0xd) {
                    channels = file.rawRead(new ubyte[1])[0];
                    break;
                }
                else
                    file.seek(size * 2,SEEK_CUR);
            }
        }
        else
            channels = (flags & 4) ? 1 : 2;

        super();
    }
}
