import std.stdio,std.conv,std.algorithm,std.string,
    std.traits,std.file,std.exception;
import utl.all;

void main(string[] args)
{
    Outer: foreach(string name; dirEntries(args.length>1?args[1]:".",SpanMode.shallow)) {
            Inner: foreach(string ext; Extensions) {
                if(name.endsWith(ext))
                    break;
                if(ext == Extensions[Extensions.length-1])
                    continue Outer;
            }
        try {
            auto f = new MediaFile(name);
            writeln(f["artist"]);
            f.close();
        }
        catch(Exception e) {
            writeln(e.msg);
        }
        catch(Error err) {
            writeln(err.msg);
            goto wait;
        }
    }

    wait: version(Windows) stdin.rawRead(new char[1]);
}