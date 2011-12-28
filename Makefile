DMD = dmd
CC = gcc

SRCS := $(wildcard utl/*.d)
OBJS := $(patsubst %.d, %.o, $(SRCS))

FLAGS = -gc

libutl: $(SRCS)
	$(DMD) $(FLAGS) -lib $(SRCS) -of$@.a

unittest: unittests.d
	$(DMD) $(FLAGS) -debug -$@ $@s.d $(SRCS) -of$@
	./unittest

.PHONY: libutl unittest clean test %.o

clean:
	rm -f libutl.a unittest{,.o} *.o */*.o test1{,.o}

$(OBJS): $(SRCS)
	$(DMD) $(FLAGS) -c -of$@ $(patsubst %.o, %.d, $@)

test: test/test.d libutl
	$(DMD) $(FLAGS) $< -of$@1 -Llibutl.a
