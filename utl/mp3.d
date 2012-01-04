module utl.mp3;

import std.stdio,std.conv,
    std.file,std.exception,std.typecons,
    std.regex,std.string,std.outbuffer,
    std.traits,std.file;
import utl.util,utl.mpeg,utl.ape,utl.id3;

version(unittest) {
    import std.path;

    Mp3File testVbr;
    static this() {
        testVbr = new Mp3File(buildPath("test","vbr.mp3"));
    }
    static ~this() {
        testVbr.close();
    }
}

class Mp3File : UtlFile {
    ID3v1 id3v1tags;
    ID3v2 id3v2tags;
    APE   apetags;

    this(string filename) {
        file = File(filename);
        this.filename = filename;

        try {
            id3v2tags = new ID3v2(file);
        }
        catch(ID3Exception e) {
            debug writeln(to!string(typeid(this)) ~ ": " ~ e.msg);
        }

        if(id3v2tags) {
            metadata = id3v2tags;
        }

        properties = new MpegFrameHeader(file);

        try {
            id3v1tags = new ID3v1(file);
        }
        catch(ID3Exception e) {
            debug writeln(to!string(typeid(this)) ~ ": " ~ e.msg);
        }

        if(id3v1tags && !id3v2tags) {
            metadata = id3v1tags;
        }

        try {
            apetags = new APE(file);
        }
        catch(APEException e) {
            debug writeln(to!string(typeid(this)) ~ ": " ~ e.msg);
        }
    }

    override void save(bool stripID3 = false) {
    }
}

unittest {
    debug writeln("utl: testing mp3");
    assert(testVbr.getaRTisT() == "Øresund Space Collective");
}