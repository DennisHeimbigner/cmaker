# Uncomment on Visual Studio
#XGETOPT = XGetopt.c XGetopt.h

all: makeparser compile check

compile: cmaker.tab.c
	gcc -g -O0 -o cmaker.exe cmaker.tab.c ${XGETOPT}

# These rules are used if someone wants to rebuild cmakerl.c or cmakery.c
# Otherwise never invoked, but records how to do it.
# BTW: Note that these will be deleted on 'make distclean'.
# Note also that this should be built under linux or cygwin
# using bison version 3 or later.

makeparser::
	rm -f cmaker.tab.c
	bison -t -v cmaker.y

check::
	gcc -g -O0 -o tst_vutils.exe tst_vutils.c ${XGETOPT}
	./tst_vutils
