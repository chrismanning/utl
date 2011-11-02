import std.stdio,std.conv,std.algorithm,std.string,
    std.traits,std.file,std.exception;
import utl.all;

void main(string[] args)
{
    try {
        uint i;
        Outer: foreach(string name; dirEntries(args?args[1]:".",SpanMode.shallow)) {
            Inner: foreach(string ext; Extensions) {
                if(name.endsWith(ext))
                    break;
                if(ext == Extensions[Extensions.length-1])
                    continue Outer;
            }
            auto f = new MediaFile(name);
            //enforce(f.metadata["ARTIST"] == artists[i],"Failed to retrieve Artist for \"" ~ name ~ "\"");
            writeln(f.getARTIST());
            f.close();
            ++i;
        }
        writeln("Success!");
    }
    catch(Exception e) {
        writeln(e.msg);
    }
    catch(Error err) {
        writeln(err.msg);
    }

    version(Windows) stdin.rawRead(new char[1]);
}