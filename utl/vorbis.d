module utl.vorbis;
import std.stdio,std.outbuffer,std.string,std.algorithm,
    std.traits,std.conv,std.exception;
import utl.util,utl.flac;

class VorbisException : Exception {
    this(string msg) {
        super(msg);
    }
}

class VorbisComment : Metadata!(string,true) {
  private:
    MetadataBlockHeader header;
    string vendorString;

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
        debug writeln(to!string(typeid(this)) ~ ": old length: ", header.block_length);
        debug writeln(to!string(typeid(this)) ~ ": new length: ", this.length);

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

  package:
    this(ref File f, MetadataBlockHeader _header) {
        header = _header;
        ubyte[] data = new ubyte[header.block_length];
        f.rawRead(data);

        this(data);
    }

    public void opIndexAssign(T_V = T, T_K)(T_V value, T_K key)
    if((isSomeString!T_V || is(T_V == Tag)) && (isSomeString!T_K || is(T_K == Key)))
    {
        tags[Key(key,allowedChars)] = value;
    }

    string[] makeCommentList() {
        string[] tmp;
        foreach(key,value; tags.toAA()) {
            tmp ~= [key.originalKey ~ "=" ~ value.value];
        }
        return tmp;
    }

    @property uint length() {
        uint sum;
        sum += 4;
        sum += vendorString.length;
        sum += 4;

        foreach(s; makeCommentList()) {
            sum += s.length + 4;
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

private string genChars() {
    string s;
    foreach(char c; 0x20..0x7d) {
        s ~= c;
    }
    return tr(s,"=","","d");
}

private enum allowedChars = genChars();
