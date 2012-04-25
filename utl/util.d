module utl.util;

import std.traits, std.conv, std.stdio, std.functional,
    std.outbuffer, std.algorithm, std.exception,
    std.typecons, std.typetuple, std.path,
    std.string, std.container, std.range, std.utf, std.random,
    std.system, std.bitmanip;
import utl.all;

class UtlException : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

alias TypeTuple!(FlacFile,WavPackFile,MonkeyFile,Mp3File) FileTypes;
enum Extensions = [".flac",".wv",".ape",".mp3"];

/**
 * Passes $(D_PARAM filename) along to the appropriate class, determined by its extension
 * Returns a $(B UtlFile).
 */
UtlFile openMediaFile(string filename) {
    auto idx = countUntil(Extensions, extension(filename));
    if(idx == -1) {
        throw new UtlException("File type not supported for file: " ~ filename);
    }
    FileTypes types;
    foreach(i, Type; types) {
        if(i == idx)
            return new typeof(Type)(filename);
    }
    assert(0);
}

abstract class UtlFile {
  protected:
    File file;
    Properties properties;
    Metadata_I metadata;

    @property void filename(string f) {
        filename_ = f;
    }

  public:
    final void close() {
        file.close();
    }

    final auto opIndex(S)(S key) if(isSomeString!S) {
        return metadata[key];
    }

    final void opIndexAssign(S,T)(S value, T key) if(isSomeString!S && isSomeString!T) {
        metadata[key] = value;
    }

    final void remove(string key) {
        metadata.remove(Key(key));
    }

    @property string filename() {
        return filename;
    }

    final string printTags() {
        return to!string(metadata);
    }

    void save(bool stripID3 = false);

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

    private string filename_;
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

mixin template Assign(A) {
    override void assign(A value, string key) {
        static if(is(T == A)) {
            this[key] = value;
        }
        else this[key] = to!T(value);
    }
}

private abstract class Metadata_I {
    string opIndex(S)(S key) if(isSomeString!S) {
        static if(!is(S == string)) {
            return get(to!string(key));
        }
        else return get(key);
    }
    void opIndexAssign(T_V, T_K)(T_V value, T_K key)
    if((isSomeString!T_V || is(T_V == Tag)) && isKeyCompat!T_K)
    {
        assign(value,to!string(key));
    }
    void opIndexOpAssign(string op)(string value, string key);
  abstract:
    override string toString();
    string get(string key);
    void assign(string value, string key);
    void assign(wstring value, string key);
    void assign(dstring value, string key);
    void remove(Key key);
}

template isTagCompat(T,S) {
    enum isTagCompat = isSomeString!T || is(T == Tag!S);
}
template isKeyCompat(T) {
    enum isKeyCompat = isSomeString!T || is(T == Key);
}

abstract class Metadata(T, bool allowDuplicates = false)
if(isSomeString!T || is(T == ubyte[])) : Metadata_I {
    TagTable!(Tag!T,allowDuplicates) tags;

    final string opIndex(S)(S key) if(isSomeString!S) {
        return to!string(tags[Key(key)]);
    }
    static if(allowDuplicates) {
        string[] getAll(S)(S key) if(isSomeString!S) {
            return tags.get(Key(key),[Tag!T("")]);
        }
    }
    final override string get(string key) {
        return this[key];
    }
    mixin Assign!string;
    mixin Assign!wstring;
    mixin Assign!dstring;

    final void opIndexAssign(T_V = T, T_K)(T_V value, T_K key)
        if(isTagCompat!(T_V,T) && isKeyCompat!T_K)
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

    override void remove(Key key) {
        tags.remove(key);
    }

    override string toString() {
        return tags.toString();
    }
}

private struct TagTable(T, bool allowDuplicates) {
    private struct Pair {
        Key key;
        T value;
    }
    private Array!Pair pairs;

    this(T[Key] tagAA) {
        foreach(Key k, T v; tagAA) {
            pairs.insertBack(Pair(k,v));
        }
    }

    T opIndex(K)(K key) if(isKeyCompat!K) {
        auto idx = contains(key);
        if(idx == -1)
            return T("");
        return pairs[idx].value;
    }

    void opIndexAssign(K,V)(V value, K key) if(isKeyCompat!K && isTagCompat!(V,string)) {
        static if(!allowDuplicates) {
            auto idx = contains(key);
            if(idx != -1) {
                pairs[idx].value = T(value);
                return;
            }
        }
        pairs.insertBack(Pair(Key(key),T(value)));
    }

    size_t contains(K)(K key) if(isKeyCompat!K) {
        return countUntil!`a.key == b`(pairs[], Key(key));
    }

    void remove(K)(K key) if(isKeyCompat!K) {
        auto r = rFilter!`a.key != b`(pairs[],Key(key));
        pairs = Array!Pair(array(r));
    }

    T[Key] toAA() {
        T[Key] aa;
        foreach(p; pairs) {
            aa[p.key] = p.value;
        }
        return aa;
    }

    string toString() {
        return to!string(toAA());
    }
}

/*
 * Copied from std.algorithm.filter but changed unaryfun to binaryfun
 * and added an extra parameter
 */
private auto rFilter(alias pred = "a == b", Range, K)(Range rs, K k)
if (isInputRange!(Unqual!Range)) {
    struct Result
    {
        alias Unqual!Range R;
        R _input;

        this(R r)
        {
            _input = r;
            while (!_input.empty && !binaryFun!pred(_input.front,k))
            {
                _input.popFront();
            }
        }

        auto opSlice() { return this; }

        static if (isInfinite!Range)
        {
            enum bool empty = false;
        }
        else
        {
            @property bool empty() { return _input.empty; }
        }

        void popFront()
        {
            do
            {
                _input.popFront();
            } while (!_input.empty && !binaryFun!pred(_input.front,k));
        }

        @property auto ref front()
        {
            return _input.front;
        }

        static if(isForwardRange!R)
        {
            @property auto save()
            {
                return Result(_input);
            }
        }
    }

    return Result(rs);
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

    const bool opEquals(ref const Tag!T b) {
        return std.string.cmp(_value, b._value) == 0;
    }

    const int opCmp(ref const Tag!T b) {
        return std.string.cmp(_value, b._value);
    }

    @property {
        T value() {
            return _value;
        }
        void value(T a) {
            _value = a;
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
    this(S)(S key, string allowedChars = allowedChars) if(isKeyCompat!S) {
        static if(isSomeString!S) {
            _originalKey = validateKey(to!string(key), allowedChars);
            _key = toLower(_originalKey);
        }
        else {
            this = key;
        }
    }

    hash_t toHash() const nothrow @safe {
        return typeid(string).getHash(&_key);
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
