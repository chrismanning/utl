module utl.util;

import std.traits,std.conv,std.stdio,
    std.outbuffer,std.algorithm,std.exception,
    std.typecons,std.variant,std.typetuple,std.path,
    std.string,std.container,std.range,std.utf,std.random;
package import std.system,std.bitmanip;
import core.bitop;
import utl.all;

class UtlException : Exception {
    this(string msg) {
        super(msg);
    }
}

alias TypeTuple!(FlacFile,WavPackFile,MonkeyFile,Mp3File) FileTypes;
enum Extensions = [".flac",".wv",".ape",".mp3"];

class MediaFile {
    private FileTypes types;
    private UtlFile _utlfile;

    this(string filename) {
        mixin(generateSwitch!FileTypes);
    }

    @property {
        private void set_Utlfile(UtlFile a) {
            _utlfile = a;
        }
        UtlFile get_Utlfile() {
            return _utlfile;
        }
    }

    void delegate(bool stripID3 = false) save;

    alias get_Utlfile this;
}

private string generateSwitch(T...)() {
    string result = "switch(extension(filename)) {\n";
    foreach(i,Type; T) {
        string var = "types[" ~ to!string(i) ~ "]";
        result ~= "case Extensions[" ~ to!string(i) ~ "]:\n"
                ~ var ~ " = new typeof(" ~ var ~ ")(filename);\n"
                ~ "set_Utlfile = " ~ var ~ ";\n"
                ~ "save = &" ~ var ~ ".save;\n"
                ~ "break;\n";
    }
    return result ~ "default:\n"
                ~ "assert(0, q{Bad index: } ~ extension(filename));\n}";
}

abstract class UtlFile {
  protected:
    File file;
    Properties properties;
    Metadata_I metadata;

  public:
    final void close() {
        file.close();
    }

    final auto opIndex(string key) {
        return metadata[key];
    }

    final void opIndexAssign(string value, string key) {
        metadata[key] = value;
    }

    final void removeTag(string key) {
        metadata.remove(Key(key));
    }

    final string printTags() {
        return to!string(metadata);
    }

    auto opDispatch(string s)(string input = "") {
        auto x = toLower(s);
        if(x.startsWith("get"))
            x = x[3..$];
        else if(x.startsWith("set")) {
            x = x[3..$];
            this[x] = input;
        }
        return this[x];
    }
}

private abstract class Props {
    uint sample_rate;
    ubyte channels;
    ubyte bits_per_sample;
    ulong samples;
    double length; //seconds
    ushort bitrate; //kbps
}

class Properties : Props {
    this() {
        constructTags();
    }

    Tag!string[Key] tags;

    string opIndex(string key) {
        return "";
    }

    private void constructTags() {
        foreach(m; __traits(allMembers,Props)[0..6]) {
            tags[Key(m)] = to!string(__traits(getMember,this,m));
        }
    }
}

private abstract class Metadata_I {
    string opIndex(string key);
    void opIndexAssign(T_V, T_K)(T_V value, T_K key);
    void opIndexOpAssign(string op)(string value, string key);
    void assign(string key, string value);
    void remove(Key key);
    string toString();
}

abstract class Metadata(T) if(isSomeString!T || is(T == ubyte[])) : Metadata_I {
    protected Tag!T[Key] tags;

    void assign(string key, string value) {
        this[key] = value;
    }

    final string opIndex(string key) {
        return to!string(tags.get(Key(key),Tag!T("")));
    }

    final void opIndexAssign(T_V = T, T_K)(T_V value, T_K key)
        if((isSomeString!T_V || is(T_V == Tag)) && (isSomeString!T_K || is(T_K == Key)))
    {
        static if(!is(T_V == T)) {
            static if(isSomeString!T) {
                tags[Key(key)] = to!T(value);
            }
        }
        else tags[Key(key)] = value;
    }

    final void opIndexOpAssign(string op)(string value, string key) {
    }

    void remove(Key key) {
        tags.remove(key);
    }

    string toString() {
        return to!string(tags);
    }
}

struct Tag(T) if(isSomeString!T || is(T == ubyte[])) {
  private:
    T _value;
    ApeItemType _apeItemType = ApeItemType.text;

  public:
    this(T value, ApeItemType apeItemType = ApeItemType.text) {
        this.value = value;
        static if(is(T == ubyte[])) {
            _apeItemType = ApeItemType.binary;
        }
        else
            _apeItemType = apeItemType;
    }

    S opBinary(string op, S)(S s)
    if(op == "~" && (is(S == T) || is(S == typeof(this)))) {
        static if(is(S == T)) {
            static if(isSomeString!S)
                validate(s);
            return value ~ s;
        }
        else {
            return Tag!T(value ~ s);
        }
    }

    ref typeof(this) opOpAssign(string op, S)(S s)
    if(op == "~" && (is(S == T) || is(S == typeof(this)))) {
        static if(is(S == T)) {
            static if(isSomeString!S) {
                try validate(s);
                catch(UtfException e) {
                }
            }
            static if(is(S == ubyte[]))
                _apeItemType = ApeItemType.binary;
            _value ~= s;
            return this;
        }
        else {
            _value ~= s.value;
            return this;
        }
    }

    ref typeof(this) opAssign(S)(S s) if(is(S == T) || is(S == typeof(this)))
    {
        static if(is(S == T)) {
            static if(isSomeString!S) {
                try validate(s);
                catch(UtfException e) {
                    value = "";
                    return this;
                }
            }
            static if(is(S == ubyte[]))
                _apeItemType = ApeItemType.binary;
            value = s;
        }
        else {
            value = s.value;
            _apeItemType = s.apeItemType;
        }

        return this;
    }

    @property {
        void value(T a) {
            _value = a;
        }
        T value() {
            return _value;
        }
        ApeItemType apeItemType() {
            return _apeItemType;
        }
        size_t length() {
            return value.length;
        }
    }

    string toString() {
        static if(isSomeString!T) {
            static if(!is(T == string))
                return to!string(value);
            else return value;
        }
        else
            return "[Binary Data: " ~ to!string(length) ~ " bytes]";
    }
}

string genChars() {
    string s;
    foreach(char c; 0x20..0x7e) {
        s ~= c;
    }
    return s;
}

enum allowedChars = genChars();

private string validateKey(string key, string allowedChars) {
    return tr(key,allowedChars,"","cd");
}

struct Key {
  private:
    string _originalKey;
    string _key;

  public:
    this(string key, string allowedChars = allowedChars) {
        _originalKey = validateKey(key, allowedChars);
        _key = toLower(_originalKey);
    }

    const hash_t toHash() {
        hash_t hash;
        foreach(c; _key)
            hash = (hash * 9) + c;
        return hash;
    }

    const bool opEquals(ref const Key s) {
        return std.string.cmp(_key, s._key) == 0;
    }

    const int opCmp(ref const Key s) {
        return std.string.cmp(_key, s._key);
    }

    @property {
        string key() {
            return _key;
        }
        string originalKey() {
            return _originalKey;
        }
        size_t length() {
            return key.length;
        }
    }

    string toString() {
        return key;
    }
}

package string mkstemp(string input) {
    char[] tmp; tmp.length = 6;
    foreach(c; tmp) {
        c = cast(char) uniform(0x30,0x7a);
    }

    return input ~ cast(string) tmp;
}

package alias Endian.bigEndian BE;
package alias Endian.littleEndian LE;

/// Converts a ubyte[] to an integral type
package T toInt(T, Endian endian = std.system.endian)(ref ubyte[] source)
pure nothrow @safe if (isIntegral!T)
in {
    assert(source.length <= T.sizeof);
}
body {
    auto padding = T.sizeof - source.length;
    ubyte[T.sizeof] tmp;
    static if (endian == BE) {
        tmp = new ubyte[padding] ~ source;
        return btn!T(tmp);
    }
    else static if (endian == LE) {
        tmp = source ~ new ubyte[padding];
        return ltn!T(tmp);
    }
}

/// Returns a ubyte[] of given input packed into size bytes and of the given endianness
package ubyte[] pack(Endian endian, T)(T input, size_t bytes = T.sizeof)
if (isIntegral!T) {
    ubyte[] a = new ubyte[bytes];
    static if(endian == BE) {
        return ntb(input).dup[$-bytes..$];
    }
    else static if (endian == LE) {
        return ntl(input).dup[0..bytes];
    }
}

package {
    alias bigEndianToNative btn;
    alias littleEndianToNative ltn;
    alias nativeToBigEndian ntb;
    alias nativeToLittleEndian ntl;
}

private ubyte[T.sizeof] arrayify(T)(T val) pure nothrow @safe if (isNumeric!T || isSomeChar!T) {
    union U {
        T _val;
        ubyte[T.sizeof] arr;
    } U u;
    u._val = val;
    return u.arr;
}
