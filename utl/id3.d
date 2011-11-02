module utl.id3;

import std.stdio,std.conv,std.bitmanip,
    std.exception,std.regex,std.string,
    std.outbuffer,std.traits,std.algorithm,
    std.utf,std.encoding;
import core.bitop;
import utl.util;

class ID3Exception : Exception {
    this(string msg) {
        super(msg);
    }
}

class ID3v2 : Metadata {
    uint size;

    this(ref File file) {
        enforce(hasID3v2(file),new ID3Exception("No ID3v2"));
        debug writeln("Position of ID3v2: ",file.tell-3);

        file.seek(3,SEEK_CUR);
        auto x = file.rawRead(new ubyte[4]);
        //x = x[3..$];

        foreach(i, b; x.reverse) {
            size |= (b & 127) << (i * 7);
        }
        if(size) {
            file.seek(size,SEEK_CUR);
        }
        throw new ID3Exception("Not implemented yet");
    }
    /**
     * Check for ID3v2 tags in a file
     */
    bool hasID3v2(ref File file) {
        char[] tmp = new char[3];

        tmp = file.rawRead(tmp);

        if(tmp != "ID3") {
            file.seek(0);
            tmp = file.rawRead(tmp);
        }

        return tmp == "ID3";
    }
}

private string decodeLatin1(ubyte[] input) {
    string output;

    transcode(cast(Latin1String) input, output);

    return output;
}

private string strip(string input) {
    auto x = countUntil(input,cast(char)0x00);
    if(x < 0) return input;
    return std.string.strip(input[0..x]);
}

class ID3v1 : Metadata {
    this(ref File file) {
        enforce(hasID3v1(file),new ID3Exception(file.name ~ " has no ID3v1"));
        debug writeln("Position of ID3v1: ", file.tell-3);

        auto data = file.rawRead(new ubyte[125]);
        enforce(data.length == 125,new ID3Exception("ID3 data incorrect length"));
        int p;

        this["title"] = .strip(decodeLatin1(data[p..p+30])); p+=30;
        this["artist"] = .strip(decodeLatin1(data[p..p+30])); p+=30;
        this["album"] = .strip(decodeLatin1(data[p..p+30])); p+=30;
        this["year"] = .strip(decodeLatin1(data[p..p+4])); p+=4;
        if(data[p+28] == 0x00) {
            this["comment"] = .strip(decodeLatin1(data[p..p+28])); p+=29;
            this["tracknumber"] = to!string(data[p]); ++p;
        }
        else {
            this["comment"] = .strip(decodeLatin1(data[p..p+30])); p+=30;
        }
        this["genre"] = genres[data[p]];

        if(hasEnhancedID3v1(file)) {
            p = 0;
            data = file.rawRead(new ubyte[223]);
            enforce(data.length == 223,new ID3Exception("Enhanced ID3 data incorrect length"));
            file.seek(-227,SEEK_CUR);

            this["title"] ~= .strip(decodeLatin1(data[p..p+60])); p+=60;
            this["artist"] ~= .strip(decodeLatin1(data[p..p+60])); p+=60;
            this["album"] ~= .strip(decodeLatin1(data[p..p+60])); p+=61;
            auto x = .strip(decodeLatin1(data[p..p+30])); p+=30;
            if(x.length) {
                this["genre"] = x;
            }
            file.seek(-335,SEEK_END);
        }
        else
            file.seek(-128,SEEK_END);
    }
    /**
     * Check for ID3v1 tags in a file
     */
    bool hasID3v1(ref File file) {
        file.seek(-128, SEEK_END);
        char[4] x = file.rawRead(new char[4]);
        file.seek(-1,SEEK_CUR);
        if(x[3] == 'E')
            return false;
        return x[0..3] == "TAG";
    }
    /**
     * Check for enhanced ID3v1 tags in a file
     */
    bool hasEnhancedID3v1(ref File file) {
        file.seek(-355,SEEK_END);
        return file.rawRead(new char[4]) == "TAG+";
    }
}

/* id3v1 genre list. includes winamp extensions
 * (even undocumented ones http://forums.winamp.com/showthread.php?p=882810)
 */
string[148] genres = ["Blues","Classic Rock","Country","Dance","Disco","Funk","Grunge","Hip-Hop",
"Jazz","Metal","New Age","Oldies","Other","Pop","R&B","Rap","Reggae","Rock","Techno","Industrial",
"Alternative","Ska","Death Metal","Pranks","Soundtrack","Euro-Techno","Ambient","Trip-Hop","Vocal",
"Jazz+Funk","Fusion","Trance","Classical","Instrumental","Acid","House","Game","Sound Clip",
"Gospel","Noise","AlternRock","Bass","Soul","Punk","Space","Meditative","Instrumental Pop",
"Instrumental Rock","Ethnic","Gothic","Darkwave","Techno-Industrial","Electronic","Pop-Folk",
"Eurodance","Dream","Southern Rock","Comedy","Cult","Gangsta","Top 40","Christian Rap",
"Pop/Funk","Jungle","Native American","Cabaret","New Wave","Psychadelic","Rave","Showtunes",
"Trailer","Lo-Fi","Tribal","Acid Punk","Acid Jazz","Polka","Retro","Musical","Rock & Roll",
"Hard Rock","Folk","Folk-Rock","National Folk","Swing","Fast Fusion","Bebob","Latin","Revival",
"Celtic","Bluegrass","Avantgarde","Gothic Rock","Progressive Rock","Psychedelic Rock",
"Symphonic Rock","Slow Rock","Big Band","Chorus","Easy Listening","Acoustic","Humour","Speech",
"Chanson","Opera","Chamber Music","Sonata","Symphony","Booty Bass","Primus","Porn Groove",
"Satire","Slow Jam","Club","Tango","Samba","Folklore","Ballad","Power Ballad","Rhythmic Soul",
"Freestyle","Duet","Punk Rock","Drum Solo","A capella","Euro-House","Dance Hall","Goa",
"Drum & Bass","Club House","Hardcore","Terror","Indie","BritPop","Negerpunk","Polsk Punk",
"Beat","Christian Gangsta Rap","Heavy Metal","Black Metal","Crossover","Contemporary Christian",
"Christian Rock","Merengue","Salsa","Thrash Metal","Anime","JPop","Synthpop"];

string[] frames =
["AENC","APIC","COMM","COMR","ENCR","EQUA","ETCO","GEOB","GRID","IPLS",
 "LINK","MCDI","MLLT","OWNE","PRIV","PCNT","POPM","POSS","RBUF","RVAD",
 "RVRB","SYLT","SYTC","TALB","TBPM","TCOM","TCON","TCOP","TDAT","TDLY",
 "TENC","TEXT","TFLT","TIME","TIT1","TIT2","TIT3","TKEY","TLAN","TLEN",
 "TMED","TOAL","TOFN","TOLY","TOPE","TORY","TOWN","TPE1","TPE2","TPE3",
 "TPE4","TPOS","TPUB","TRCK","TRDA","TRSN","TRSO","TSIZ","TSRC","TSSE",
 "TYER","TXXX","UFID","USER","USLT","WCOM","WCOP","WOAF","WOAR","WOAS",
 "WORS","WPAY","WPUB","WXXX"];
