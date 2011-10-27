module utl.mpeg;

import std.stdio,std.exception;
import utl.util,utl.ape,utl.id3;

enum MpegVersions = [2.5, 0, 2, 1];
enum MpegLayers   = [0  , 3, 2, 1];

auto MpegVersionLayer(uint[] a) {
    if(a[0] > 1)
        return a[0] + a[1];
    return a[1] - a[0];
}

enum MpegBitrate = 
[   [0, 32, 64, 96, 128,160,192,224,256,288,320,352,384,416,448],
    [0, 32, 48, 56, 64, 80, 96, 112,128,160,192,224,256,320,384],
    [0, 32, 40, 48, 56, 64, 80, 96, 112,128,160,192,224,256,320],
    [0, 32, 48, 56, 64, 80, 96, 112,128,144,160,176,192,224,256],
    [0,  8, 16, 24, 32, 40, 48,  56, 64, 80, 96,112,128,144,160]];

enum SampleRates =
[   1:   [44100, 48000, 32000],
    2:   [22050, 24000, 16000],
    2.5: [11025, 12000, 8000]];

class MpegFrameHeader : Properties {
    this(ref File file) {
        auto tmp = file.rawRead(new ubyte[4]);
        auto data = toInt!(uint,BE)(tmp);

        auto frameSync = data >> 21;
        enforce(frameSync == 0x7FF);
        auto mpegVersion = MpegVersions[(data >> 19) & 3];
        auto mpegLayer = MpegLayers[(data >> 17) & 3];
        bitrate = (data >> 12) & 0xF;
        bitrate = cast(ushort) MpegBitrate[MpegVersionLayer([cast(uint)mpegVersion,mpegLayer])][bitrate];
        sample_rate = SampleRates[mpegVersion][(data >> 10) & 3];
    }
}

class Xing {
}