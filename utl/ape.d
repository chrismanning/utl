module utl.ape;

import std.stdio,std.conv,std.bitmanip,
    std.file,std.exception,std.typecons,
    std.string,std.outbuffer,std.traits;
import utl.util;

enum HeaderSize = 32;
enum ApeItemType : ubyte {
    text,
    binary,
    external
}

private struct Flags {
    ubyte _flags;

    this(uint f) {
        flags = cast(ubyte) (f & 7) | (f >> 26);
    }

    this(ApeItemType itemType) {
        flags = cast(ubyte) (itemType << 1);
    }

    ref Flags opAssign(T)(T f) if(is(T == Flags) || is(T == uint)) {
        static if(is(T == uint))
            flags = cast(ubyte) (f & 7) | (f >> 26);
        else
            flags = f.flags;
        return this;
    }

    @property {
        void flags(ubyte f) {
            _flags = f;
        }
        ubyte flags() {
            return _flags;
        }
        bool isHeader() {
            return cast(bool) (flags >> 3) & 1;
        }
        bool isFooter() {
            return !cast(bool) (flags >> 3) & 1;
        }
        bool hasHeader() {
            return cast(bool) flags >> 5;
        }
        bool hasFooter() {
            return !cast(bool) (flags >> 4) & 1;
        }
        ubyte itemType() {
            return (flags >> 1) & 3;
        }
    }
    uint opCast() {
        return ((flags << 26) & 0xE0000000) | (flags & 7);
    }
}

class APEHeader {
  private:
    static string preamble = "APETAGEX";
    static immutable Size = 32;

    Flags flags;

    uint apeVersion; //although this is stored, APEv2 (2000)
                     //is always written to file
    uint _tagSize;
    uint _itemCount;

    auto write() {
        auto buf = new OutBuffer;
        buf.reserve(32);

        buf.write(preamble);
        buf.write(ntl(cast(uint)2000));
        buf.write(ntl(tagSize));
        buf.write(ntl(itemCount));
        buf.write(ntl(cast(uint) flags));
        buf.fill0(8);

        return buf;
    }

  public:
    this(ubyte[] data) {
        int p;

        enforceEx!APEException(data[p..8] == APEHeader.preamble, "Invalid APE header");
        p+=8;

        apeVersion = toInt!(uint,LE)(data[p..p+4]); p+=4;
        enforce(apeVersion == 2000 || apeVersion == 1000, "Invalid APE tag version");

        tagSize = toInt!(uint,LE)(data[p..p+4]); p+=4;
        //enforce((data.length - HeaderSize) == _size);

        itemCount = toInt!(uint,LE)(data[p..p+4]); p+=4;
        Flags tmp = toInt!(uint,LE)(data[p..p+4]); p+=4;
        flags = tmp;

        enforce(data[p..p+8] == new ubyte[8]);
    }
    this(uint tagSize, uint items, uint flags) {
        this.tagSize = tagSize;
        itemCount = items;
        Flags tmp = flags;
        this.flags = tmp;
    }

    @property {
        auto tagSize() {
            return _tagSize;
        }
        void tagSize(uint a) {
            _tagSize = a;
        }

        auto itemCount() {
            return _itemCount;
        }
        void itemCount(uint a) {
            _itemCount = a;
        }

        auto size() {
            return Size;
        }
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

class APE : Metadata {
  private:
    APEHeader header;
    APEHeader footer;
    ulong _tagStart;
    uint ape_version;
    uint _size;
    uint item_count;
    uint tag_flags;

    this(ubyte[] data) {
        if(!data.length)
            return;
        int p;

        if(footer.flags.hasHeader) {
            header = new APEHeader(data[p..p+32]);
            p += 32;
        }

        foreach(i; 0..footer.itemCount) {
            auto value_length = toInt!(uint,LE)(data[p..p+4]); p+=4;
            auto itemFlags = toInt!(uint,LE)(data[p..p+4]); p+=4;
            Flags flags = itemFlags;

            //auto itemType = ((cast(ubyte) itemFlags) & 7) >> 1;
            if(flags.itemType > ApeItemType.external)
                continue;

            int x;
            for(; x < 255 && data[p+x] != 0x00; ++x) {}
            auto key = cast(string) data[p..p+x]; p+=x+1;
            if(Key(key) in tags) {
                p += value_length;
                continue;
            }

            if(flags.itemType == ApeItemType.text) {
                this[key] = cast(string) data[p..p+value_length];
                p+=value_length;
            }
            else if(flags.itemType == ApeItemType.binary){
//                 this[key] = data[p..p+value_length];
                p+=value_length;
            }
            else {
                auto value = cast(string)data[p..p+value_length];
                p+=value_length;
                this[key] = value;
//                 this[key] = Tag!string(value,ApeItemType.external);
            }
        }
    }

    auto write() {
        auto buf = new OutBuffer;

        uint tagSize = 32;

        if(header) {
            header.tagSize = tagSize;
            buf.write(cast(ubyte[]) header);
        }
        else {
            //tmp.write(new APEHeader(tagSize,tags.length,
        }

        foreach(key,value; tags) {
            tagSize += (9 + key.length + value.length);
            buf.write(ntl(cast(uint) value.length));
            buf.write(ntl(cast(uint) Flags(value.apeItemType)));
            buf.write(key.originalKey ~ 0x00);
            buf.write(to!string(value));
        }
//         foreach(key,value; binaryDataTags) {
//             tagSize += (9 + key.length + value.length);
//             buf.write(ntl(cast(uint) value.length));
//             buf.write(ntl(cast(uint) Flags(value.apeItemType)));
//             buf.write(key.originalKey ~ 0x00);
//             buf.write(value.value);
//         }

        if(footer) {
            footer.tagSize = tagSize;
            buf.write(cast(ubyte[]) footer);
        }
        else {
            //tmp.write(new APEHeader(tagSize,tags.length,
        }

        return buf;
    }

  public:
    this(ref File file) {
        ubyte[] data;

        enforceEx!APEException(hasAPE(file),"No APE tags found: " ~ file.name);

        file.seek(-8,SEEK_CUR);
        debug writeln(to!string(typeid(this)) ~ ": Position of APE: ",file.tell);

        footer = new APEHeader(file.rawRead(new ubyte[32]));
        //enforce(hasFooter ? isFooter : !isFooter);

        tagStart = file.tell - footer.tagSize - (footer.flags.hasHeader ? 32 : 0);
        file.seek(tagStart);

        data = file.rawRead(new ubyte[footer.tagSize + 32]);
        this(data);
    }
    this() {
    }

    static bool hasAPE(ref File file) {
        if(file.tell >= 32)
            file.seek(-32,SEEK_CUR);

        if(file.rawRead(new char[8]) != "APETAGEX") {
            file.seek(-32,SEEK_END);
            return file.rawRead(new char[8]) == "APETAGEX";
        }
        else return true;

        return false;
    }

    T opCast(T)() {
        static if(is(T == OutBuffer)) {
            return write();
        }
        else static if(is(T == ubyte[])) {
            return write().toBytes();
        }
    }

    @property {
        uint size() {
            return _size;
        }
        auto tagStart() {
            return _tagStart;
        }
        void tagStart(ulong a) {
            _tagStart = a;
        }
    }
}

class APEException : Exception {
    this(string msg) {
        super(msg);
    }
}
