module utl.vorbis;
import std.stdio,std.outbuffer,std.string,std.algorithm,
    std.traits,std.conv,std.exception;
import utl.all;

private {
string genChars() {
    string s;
    foreach(char c; 0x20..0x7d) {
        s ~= c;
    }
    return tr(s,"=","","d");
}

enum allowedChars = genChars();
}

package class VorbisComment : Metadata {
private:
    MetadataBlockHeader header;
    string vendorString;
    //string[] user_comment_list;

    this(ubyte[] data) {
        int p;

        vendorString.length = toInt!(uint,LE)(data[p..p+4]); p+=4;
        vendorString = cast(string) data[p..p+vendorString.length];
        p+=vendorString.length;

        auto userCommentListLength = toInt!(uint,LE)(data[p..p+4]); p+=4;

        foreach(i; 0..userCommentListLength) {
            auto commentLength = toInt!(uint,LE)(data[p..p+4]); p+=4;
            auto tmp = cast(string) data[p..p+commentLength];
            p+=commentLength;
            
            auto x = findSplitBefore(tmp,"=");
            skipOver(x[1],"=");

            this[x[0]] = x[1];
        }
    }

    OutBuffer write() {
        auto buf = new OutBuffer;
        writeln("old length: ", header.block_length);
        writeln("new length: ", this.length);

        header.block_length = this.length;
        buf.write(cast(ubyte[]) header);
        buf.write(pack!(LE)(cast(uint) vendorString.length,4));
        buf.write(vendorString);
        auto tmp = makeCommentList();
        buf.write(pack!(LE)(cast(uint) tmp.length,4));

        foreach(str; tmp) {
            buf.write(pack!(LE)(cast(uint) str.length));
            buf.write(str);
        }

        return buf;
    }

public:
    this(ref File f, MetadataBlockHeader _header) {
        header = _header;
        ubyte[] data = new ubyte[header.block_length];
        f.rawRead(data);

        this(data);
    }

    void opIndexAssign(T,S)(T value, S key)
    if((isSomeString!T || is(T == Tag)) && (isSomeString!S || is(S == Key))) {
        tags[Key(key,allowedChars)] = value;
    }

    string[] makeCommentList() {
        string[] tmp;
        foreach(key,value; tags) {
            tmp ~= [key.originalKey ~ "=" ~ value.value];
        }
        return tmp;
    }

    @property override uint length() {
        uint sum;
        sum += 4;
        sum += vendorString.length;
        sum += 4;
        //sum += super.length;
        foreach(key,value; tags) {
            sum += key.length + value.length + 5;
        }
       
        return sum;
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