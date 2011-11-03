DMD=dmd
CC=gcc
DFILES=utl/*.d
OFILES=utl/all.o utl/ape.o utl/flac.o utl/id3.o utl/monkey.o utl/mp3.o utl/mpeg.o utl/ogg.o utl/util.o utl/vorbis.o utl/wavpack.o
# utl/ape.d flac.d  id3.d  monkey.d  mp3.d  mpeg.d  ogg.d  util.d  utl.visualdproj  vorbis.d  wavpack.d
FLAGS=-gc -inline

all: libutl

libutl:
	$(DMD) $(FLAGS) -lib $(DFILES) -of$@.a

unittest: unittests.d
	$(DMD) $(FLAGS) -debug -$@ $@s.d $(DFILES) -of$@
	./unittest

.PHONY: clean

clean:
	rm -f libutl.a unittest{,.o} *.o */*.o test1{,.o}

%.d:
	$(DMD) $(FLAGS) -c $@

%.o: %.d
	$(DMD) $(FLAGS) -c -of$@ $<

test: test/test.d libutl
	$(DMD) $(FLAGS) $< -of$@1 -Llibutl.a
