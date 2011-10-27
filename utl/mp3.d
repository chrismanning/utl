module utl.mp3;

import std.stdio,std.conv,
    std.file,std.exception,std.typecons,
    std.regex,std.string,std.outbuffer,
    std.traits,std.file;
import utl.util,utl.mpeg,utl.ape,utl.id3;

class Mp3File : UtlFile {
    ID3v1 id3v1tags;
    ID3v2 id3v2tags;
    APE   apetags;

    this(string filename) {
        file = File(filename);

        try id3v2tags = new ID3v2(file);
        catch(ID3Exception e) {
        }
        writeln("pos: ",file.tell);

        if(id3v2tags) {
            metadata = id3v2tags;
        }

        properties = new MpegFrameHeader(file);

        try id3v1tags = new ID3v1(file);
        catch(ID3Exception e) {
        }
        if(id3v1tags)
            metadata = id3v1tags;
    }

    void save(bool stripID3 = false) {
    }
}