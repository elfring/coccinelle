# Copyright 2005-2010, Ecole des Mines de Nantes, University of Copenhagen
# Yoann Padioleau, Julia Lawall, Rene Rydhof Hansen, Henrik Stuart, Gilles Muller, Nicolas Palix
# This file is part of Coccinelle.
#
# Coccinelle is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, according to version 2 of the License.
#
# Coccinelle is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Coccinelle.  If not, see <http://www.gnu.org/licenses/>.
#
# The authors reserve the right to distribute this or future versions of
# Coccinelle under other licenses.



#############################################################################
# Configuration section
#############################################################################

-include Makefile.config
-include /etc/lsb-release

VERSION=$(shell cat globals/config.ml.in |grep version |perl -p -e 's/.*"(.*)".*/$$1/;')
CCVERSION=$(shell cat scripts/coccicheck/README |grep "Coccicheck version" |perl -p -e 's/.*version (.*)[ ]*/$$1/;')
PKGVERSION=$(shell dpkg-parsechangelog -ldebian/changelog.$(DISTRIB_CODENAME) 2> /dev/null \
	 | sed -n 's/^Version: \(.*\)/\1/p' )

##############################################################################
# Variables
##############################################################################
TARGET=spatch
PRJNAME=coccinelle

SRC=flag_cocci.ml cocci.ml testing.ml test.ml main.ml

ifeq ($(FEATURE_PYTHON),1)
PYCMA=pycaml/pycaml.cma
PYDIR=pycaml
PYLIB=dllpycaml_stubs.so
# the following is essential for Coccinelle to compile under gentoo (weird)
OPTLIBFLAGS=-cclib dllpycaml_stubs.so
else
PYCMA=
PYDIR=
PYLIB=
OPTLIBFLAGS=
endif

SEXPSYSCMA=bigarray.cma nums.cma

SYSLIBS=str.cma unix.cma $(SEXPSYSCMA)
LIBS=commons/commons.cma \
     ocamlsexp/sexplib1.cma commons/commons_sexp.cma \
     globals/globals.cma \
     ctl/ctl.cma \
     parsing_cocci/cocci_parser.cma parsing_c/parsing_c.cma \
     engine/cocciengine.cma popl09/popl.cma \
     extra/extra.cma $(PYCMA) python/coccipython.cma

#used for clean: and depend: and a little for rec & rec.opt
MAKESUBDIRS=commons ocamlsexp \
 globals menhirlib $(PYDIR) ctl parsing_cocci parsing_c \
 engine popl09 extra python
INCLUDEDIRS=commons commons/ocamlextra ocamlsexp \
 globals menhirlib $(PYDIR) ctl \
 parsing_cocci parsing_c engine popl09 extra python

##############################################################################
# Generic variables
##############################################################################

INCLUDES=$(INCLUDEDIRS:%=-I %)

OBJS=    $(SRC:.ml=.cmo)
OPTOBJS= $(SRC:.ml=.cmx)

EXEC=$(TARGET)

##############################################################################
# Generic ocaml variables
##############################################################################

OCAMLCFLAGS=

# for profiling add  -p -inline 0
# but 'make forprofiling' below does that for you.
# This flag is also used in subdirectories so don't change its name here.
# To enable backtrace support for native code, you need to put -g in OPTFLAGS
# to also link with -g, but even in 3.11 the backtrace support seems buggy so
# not worth it.
OPTFLAGS=
# the following is essential for Coccinelle to compile under gentoo
# but is now defined above in this file
#OPTLIBFLAGS=-cclib dllpycaml_stubs.so

OCAMLC=ocamlc$(OPTBIN) $(OCAMLCFLAGS)  $(INCLUDES)
OCAMLOPT=ocamlopt$(OPTBIN) $(OPTFLAGS) $(INCLUDES)
OCAMLLEX=ocamllex #-ml # -ml for debugging lexer, but slightly slower
OCAMLYACC=ocamlyacc -v
OCAMLDEP=ocamldep $(INCLUDES)
OCAMLMKTOP=ocamlmktop -g -custom $(INCLUDES)

# can also be set via 'make static'
STATIC= #-ccopt -static

# can also be unset via 'make purebytecode'
BYTECODE_STATIC=-custom

##############################################################################
# Top rules
##############################################################################
.PHONY:: all all.opt byte opt top clean distclean configure
.PHONY:: $(MAKESUBDIRS) $(MAKESUBDIRS:%=%.opt) subdirs subdirs.opt

all: Makefile.config byte preinstall

opt: all.opt
all.opt: opt-compil preinstall

world: preinstall
	$(MAKE) byte
	$(MAKE) opt-compil

byte: .depend
	$(MAKE) subdirs
	$(MAKE) $(EXEC)

opt-compil: .depend
	$(MAKE) subdirs.opt
	$(MAKE) $(EXEC).opt

top: $(EXEC).top

subdirs:
	$(MAKE) -C commons OCAMLCFLAGS="$(OCAMLCFLAGS)"
	$(MAKE) -C ocamlsexp OCAMLCFLAGS="$(OCAMLCFLAGS)"
	$(MAKE) -C commons sexp OCAMLCFLAGS="$(OCAMLCFLAGS)"
	+for D in $(MAKESUBDIRS); do $(MAKE) $$D || exit 1 ; done

subdirs.opt:
	$(MAKE) -C commons all.opt OCAMLCFLAGS="$(OCAMLCFLAGS)"
	$(MAKE) -C ocamlsexp all.opt OCAMLCFLAGS="$(OCAMLCFLAGS)"
	$(MAKE) -C commons sexp.opt OCAMLCFLAGS="$(OCAMLCFLAGS)"
	+for D in $(MAKESUBDIRS); do $(MAKE) $$D.opt || exit 1 ; done

$(MAKESUBDIRS):
	$(MAKE) -C $@ OCAMLCFLAGS="$(OCAMLCFLAGS)" all

$(MAKESUBDIRS:%=%.opt):
	$(MAKE) -C $(@:%.opt=%) OCAMLCFLAGS="$(OCAMLCFLAGS)" all.opt

#dependencies:
# commons:
# globals:
# menhirlib:
# parsing_cocci: commons globals menhirlib
# parsing_c:parsing_cocci
# ctl:globals commons
# engine: parsing_cocci parsing_c ctl
# popl09:engine
# extra: parsing_cocci parsing_c ctl
# pycaml:
# python:pycaml parsing_cocci parsing_c

clean::
	set -e; for i in $(MAKESUBDIRS); do $(MAKE) -C $$i $@; done
	$(MAKE) -C demos/spp $@

$(LIBS): $(MAKESUBDIRS)
$(LIBS:.cma=.cmxa): $(MAKESUBDIRS:%=%.opt)

$(OBJS):$(LIBS)
$(OPTOBJS):$(LIBS:.cma=.cmxa)

$(EXEC): $(LIBS) $(OBJS)
	$(OCAMLC) $(BYTECODE_STATIC) -o $@ $(SYSLIBS)  $^

$(EXEC).opt: $(LIBS:.cma=.cmxa) $(OPTOBJS)
	$(OCAMLOPT) $(STATIC) -o $@ $(SYSLIBS:.cma=.cmxa) $(OPTLIBFLAGS)  $^

$(EXEC).top: $(LIBS) $(OBJS)
	$(OCAMLMKTOP) -custom -o $@ $(SYSLIBS) $^

clean::
	rm -f $(TARGET) $(TARGET).opt $(TARGET).top
	rm -f dllpycaml_stubs.so

.PHONY:: tools configure

configure:
	./configure

Makefile.config:
	@echo "Makefile.config is missing. Have you run ./configure?"
	@exit 1

tools:
	$(MAKE) -C tools

clean::
	if [ -d tools ] ; then $(MAKE) -C tools clean ; fi

static:
	rm -f spatch.opt spatch
	$(MAKE) STATIC="-ccopt -static" spatch.opt
	cp spatch.opt spatch

purebytecode:
	rm -f spatch.opt spatch
	$(MAKE) BYTECODE_STATIC="" spatch
	perl -p -i -e 's/^#!.*/#!\/usr\/bin\/ocamlrun/' spatch


##############################################################################
# Build documentation
##############################################################################
.PHONY:: docs

docs:
	make -C docs

clean::
	make -C docs clean

distclean::
	make -C docs distclean

##############################################################################
# Pre-Install (customization of spatch frontend script)
##############################################################################

preinstall: scripts/spatch scripts/spatch.opt scripts/spatch.byte

# user will use spatch to run spatch.opt (native)
scripts/spatch:
	cp scripts/spatch.sh scripts/spatch.tmp2
	sed "s|SHAREDIR|$(SHAREDIR)|g" scripts/spatch.tmp2 > scripts/spatch.tmp
	sed "s|LIBDIR|$(LIBDIR)|g" scripts/spatch.tmp > scripts/spatch
	rm -f scripts/spatch.tmp2 scripts/spatch.tmp

# user will use spatch to run spatch (bytecode)
scripts/spatch.byte:
	cp scripts/spatch.sh scripts/spatch.byte.tmp3
	sed "s|\.opt||" scripts/spatch.byte.tmp3 > scripts/spatch.byte.tmp2
	sed "s|SHAREDIR|$(SHAREDIR)|g" scripts/spatch.byte.tmp2 \
		> scripts/spatch.byte.tmp
	sed "s|LIBDIR|$(LIBDIR)|g" scripts/spatch.byte.tmp \
		> scripts/spatch.byte
	rm -f   scripts/spatch.byte.tmp3 \
		scripts/spatch.byte.tmp2 \
		scripts/spatch.byte.tmp

# user will use spatch.opt to run spatch.opt (native)
scripts/spatch.opt:
	cp scripts/spatch.sh scripts/spatch.opt.tmp2
	sed "s|SHAREDIR|$(SHAREDIR)|g" scripts/spatch.opt.tmp2 \
		> scripts/spatch.opt.tmp
	sed "s|LIBDIR|$(LIBDIR)|g" scripts/spatch.opt.tmp \
		> scripts/spatch.opt
	rm -f scripts/spatch.opt.tmp scripts/spatch.opt.tmp2

clean::
	rm -f scripts/spatch scripts/spatch.byte scripts/spatch.opt

##############################################################################
# Install
##############################################################################

# don't remove DESTDIR, it can be set by package build system like ebuild
# for staged installation.
install-common:
	mkdir -p $(DESTDIR)$(BINDIR)
	mkdir -p $(DESTDIR)$(LIBDIR)
	mkdir -p $(DESTDIR)$(SHAREDIR)
	mkdir -p $(DESTDIR)$(MANDIR)/man1
	$(INSTALL_DATA) standard.h $(DESTDIR)$(SHAREDIR)
	$(INSTALL_DATA) standard.iso $(DESTDIR)$(SHAREDIR)
	$(INSTALL_DATA) docs/spatch.1 $(DESTDIR)$(MANDIR)/man1/
	@if [ $(FEATURE_PYTHON) -eq 1 ]; then $(MAKE) install-python; fi

install-python:
	mkdir -p $(DESTDIR)$(SHAREDIR)/python/coccilib/coccigui
	$(INSTALL_DATA) python/coccilib/*.py \
		$(DESTDIR)$(SHAREDIR)/python/coccilib
	$(INSTALL_DATA) python/coccilib/coccigui/*.py \
		$(DESTDIR)$(SHAREDIR)/python/coccilib/coccigui
	$(INSTALL_DATA) python/coccilib/coccigui/pygui.glade \
		$(DESTDIR)$(SHAREDIR)/python/coccilib/coccigui
	$(INSTALL_DATA) python/coccilib/coccigui/pygui.gladep \
		$(DESTDIR)$(SHAREDIR)/python/coccilib/coccigui
	$(INSTALL_LIB) dllpycaml_stubs.so $(DESTDIR)$(LIBDIR)

install: install-common
	@if test -x spatch -a ! -x spatch.opt ; then \
		$(MAKE) install-byte;fi
	@if test ! -x spatch -a -x spatch.opt ; then \
		$(MAKE) install-def; $(MAKE) install-opt;fi
	@if test -x spatch -a -x spatch.opt ; then \
		$(MAKE) install-byte; $(MAKE) install-opt;fi
	@if test ! -x spatch -a ! -x spatch.opt ; then \
		echo "\n\n\t==> Run 'make', 'make opt', or both first. <==\n\n";fi
	@echo ""
	@echo "\tYou can also install spatch by copying the program spatch"
	@echo "\t(available in this directory) anywhere you want and"
	@echo "\tgive it the right options to find its configuration files."
	@echo ""

# user will use spatch to run spatch.opt (native)
install-def:
	$(INSTALL_PROGRAM) spatch.opt $(DESTDIR)$(SHAREDIR)
	$(INSTALL_PROGRAM) scripts/spatch $(DESTDIR)$(BINDIR)/spatch

# user will use spatch to run spatch (bytecode)
install-byte:
	$(INSTALL_PROGRAM) spatch $(DESTDIR)$(SHAREDIR)
	$(INSTALL_PROGRAM) scripts/spatch.byte $(DESTDIR)$(BINDIR)/spatch

# user will use spatch.opt to run spatch.opt (native)
install-opt:
	$(INSTALL_PROGRAM) spatch.opt $(DESTDIR)$(SHAREDIR)
	$(INSTALL_PROGRAM) scripts/spatch.opt $(DESTDIR)$(BINDIR)/spatch.opt

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/spatch
	rm -f $(DESTDIR)$(BINDIR)/spatch.opt
	rm -f $(DESTDIR)$(LIBDIR)/dllpycaml_stubs.so
	rm -f $(DESTDIR)$(SHAREDIR)/standard.h
	rm -f $(DESTDIR)$(SHAREDIR)/standard.iso
	rm -rf $(DESTDIR)$(SHAREDIR)/python/coccilib
	rm -f $(DESTDIR)$(MANDIR)/man1/spatch.1

version:
	@echo "spatch     $(VERSION)"
	@echo "spatch     $(PKGVERSION) ($(DISTRIB_ID))"
	@echo "coccicheck $(CCVERSION)"


##############################################################################
# Package rules
##############################################################################

PACKAGE=$(PRJNAME)-$(VERSION)
CCPACKAGE=coccicheck-$(CCVERSION)

BINSRC=spatch env.sh env.csh standard.h standard.iso \
       *.txt \
       docs/manual/manual.pdf docs/manual/options.pdf docs/manual/main_grammar.pdf docs/spatch.1 \
       docs/manual/cocci-python.txt \
       demos/*
BINSRC-PY=$(BINSRC) $(PYLIB) python/coccilib/
BINSRC2=$(BINSRC:%=$(PACKAGE)/%)
BINSRC2-PY=$(BINSRC-PY:%=$(PACKAGE)/%)

TMP=/tmp
OCAMLVERSION=$(shell ocaml -version |perl -p -e 's/.*version (.*)/$$1/;')

# Procedure to do first time:
#  cd ~/release
#  cvs checkout coccinelle -dP
#  cd coccinelle
#
# Procedure to do each time:
#
#  1) make prepackage # WARN: These will clean your local rep. of pending modifications
#
#  UPDATE VERSION number in globals/config.ml.in
#  and commit it with
#
#  2) make release
#
#  The project is then automatically licensified.
#
#  Remember to comment the -g -dtypes in this Makefile
#  You can also remove a few things, for instance I removed in this
#   Makefile things related to popl/ and popl09/
#  make sure that ocaml is the distribution ocaml of /usr/bin, not ~pad/...
#
#  3) make package
#
#  if WEBSITE is set properly, you can also run 'make website'
# Check that run an ocaml in /usr/bin

# To test you can try compile and run spatch from different instances
# like my ~/coccinelle, ~/release/coccinelle, and the /tmp/coccinelle-0.X
# downloaded from the website.

# For 'make srctar' it must done from a clean
# repo such as ~/release/coccinelle. It must also be a repo where
# the scripts/licensify has been run at least once.
# For the 'make bintar' I can do it from my original repo.

prepackage:
	cvs up -CdP
	$(MAKE) distclean
	sed -i "s|^OCAMLCFLAGS=.*$$|OCAMLCFLAGS=|" Makefile

release:
	cvs ci -m "Release $(VERSION)" globals/config.ml.in
	$(MAKE) licensify

package:
	$(MAKE) package-src
	$(MAKE) package-nopython
	$(MAKE) package-python

package-src:
	$(MAKE) distclean       # Clean project
	$(MAKE) srctar
	$(MAKE) coccicheck

package-nopython:
	$(MAKE) distclean       # Clean project
	./configure --without-python
	$(MAKE) docs
	$(MAKE) bintar
	$(MAKE) bytecodetar
	$(MAKE) staticbintar

package-python:
	$(MAKE) distclean       # Clean project
	./configure             # Reconfigure project with Python support
	$(MAKE) docs
	$(MAKE) bintar-python
	$(MAKE) bytecodetar-python


# I currently pre-generate the parser so the user does not have to
# install menhir on his machine. We could also do a few cleanups.
# You may have first to do a 'make licensify'.
#
# update: make docs generates pdf but also some ugly .log files, so
# make clean is there to remove them while not removing the pdf
# (only distclean remove the pdfs).
srctar:
	make distclean
	make docs
	make clean
	cp -a .  $(TMP)/$(PACKAGE)
	cd $(TMP)/$(PACKAGE); cd parsing_cocci/; make parser_cocci_menhir.ml
	cd $(TMP); tar cvfz $(PACKAGE).tgz --exclude-vcs $(PACKAGE)
	rm -rf  $(TMP)/$(PACKAGE)


bintar: all
	rm -f $(TMP)/$(PACKAGE)
	ln -s `pwd` $(TMP)/$(PACKAGE)
	cd $(TMP); tar cvfz $(PACKAGE)-bin-x86.tgz --exclude-vcs $(BINSRC2)
	rm -f $(TMP)/$(PACKAGE)

staticbintar: all.opt
	rm -f $(TMP)/$(PACKAGE)
	ln -s `pwd` $(TMP)/$(PACKAGE)
	make static
	cd $(TMP); tar cvfz $(PACKAGE)-bin-x86-static.tgz --exclude-vcs $(BINSRC2)
	rm -f $(TMP)/$(PACKAGE)

# add ocaml version in name ?
bytecodetar: all
	rm -f $(TMP)/$(PACKAGE)
	ln -s `pwd` $(TMP)/$(PACKAGE)
	make purebytecode
	cd $(TMP); tar cvfz $(PACKAGE)-bin-bytecode-$(OCAMLVERSION).tgz --exclude-vcs $(BINSRC2)
	rm -f $(TMP)/$(PACKAGE)

bintar-python: all
	rm -f $(TMP)/$(PACKAGE)
	ln -s `pwd` $(TMP)/$(PACKAGE)
	cd $(TMP); tar cvfz $(PACKAGE)-bin-x86-python.tgz --exclude-vcs $(BINSRC2-PY)
	rm -f $(TMP)/$(PACKAGE)

# add ocaml version in name ?
bytecodetar-python: all
	rm -f $(TMP)/$(PACKAGE)
	ln -s `pwd` $(TMP)/$(PACKAGE)
	make purebytecode
	cd $(TMP); tar cvfz $(PACKAGE)-bin-bytecode-$(OCAMLVERSION)-python.tgz --exclude-vcs $(BINSRC2-PY)
	rm -f $(TMP)/$(PACKAGE)

coccicheck:
	cp -a `pwd`/scripts/coccicheck $(TMP)/$(CCPACKAGE)
	tar cvfz $(TMP)/$(CCPACKAGE).tgz -C $(TMP) --exclude-vcs $(CCPACKAGE)
	rm -rf $(TMP)/$(CCPACKAGE)

clean-packages::
	rm -f $(TMP)/$(PACKAGE).tgz
	rm -f $(TMP)/$(PACKAGE)-bin-x86.tgz
	rm -f $(TMP)/$(PACKAGE)-bin-x86-static.tgz
	rm -f $(TMP)/$(PACKAGE)-bin-bytecode-$(OCAMLVERSION).tgz
	rm -f $(TMP)/$(PACKAGE)-bin-x86-python.tgz
	rm -f $(TMP)/$(PACKAGE)-bin-bytecode-$(OCAMLVERSION)-python.tgz
	rm -f $(TMP)/$(CCPACKAGE).tgz

#
# No need to licensify 'demos'. Because these is basic building blocks
# to use SmPL.
#
TOLICENSIFY=ctl engine globals parsing_cocci popl popl09 python scripts tools
licensify:
	ocaml str.cma tools/licensify.ml
	set -e; for i in $(TOLICENSIFY); do cd $$i; ocaml str.cma ../tools/licensify.ml; cd ..; done

# When checking out the source from diku sometimes I have some "X in the future"
# error messages.
fixdates:
	echo do 'touch **/*.*'

#fixCVS:
#	cvs update -d -P
#	echo do 'rm -rf **/CVS'

ocamlversion:
	@echo $(OCAMLVERSION)


##############################################################################
# Packaging rules -- To build deb packages
##############################################################################
EXCL_SYNC=--exclude ".git"          \
	--exclude ".gitignore"      \
	--exclude ".cvsignore"      \
	--exclude "tests"           \
	--exclude "TODO"            \
	--cvs-exclude

prepack:
	rsync -a $(EXCL_SYNC) . $(TMP)/$(PACKAGE)
	$(MAKE) -C $(TMP)/$(PACKAGE) licensify
	rm -rf $(TMP)/$(PACKAGE)/tools

packsrc: prepack
#	$(MAKE) -C $(TMP)/$(PACKAGE)/debian lucid
	$(MAKE) -C $(TMP)/$(PACKAGE)/debian karmic
	$(MAKE) push
	rm -rf  $(TMP)/$(PACKAGE)/

push:
	cd $(TMP)/ && for p in `ls $(PRJNAME)_$(VERSION).deb*_source.changes`; do dput $(PRJNAME) $$p ; done
	rm -rf $(TMP)/$(PRJNAME)_$(VERSION).deb*_source.changes
	rm -rf $(TMP)/$(PRJNAME)_$(VERSION).deb*_source.$(PRJNAME).upload
	rm -rf $(TMP)/$(PRJNAME)_$(VERSION).deb*.dsc
	rm -rf $(TMP)/$(PRJNAME)_$(VERSION).deb*.tar.gz

packbin: prepack
	$(MAKE) -C $(TMP)/$(PACKAGE)/debian binary
	rm -rf  $(TMP)/$(PACKAGE)/
	rm -rf $(TMP)/$(PRJNAME)_$(VERSION).deb*_source.build

##############################################################################
# Developer rules
##############################################################################

-include Makefile.dev

test: $(TARGET)
	./$(TARGET) -testall

testparsing:
	./$(TARGET) -D standard.h -parse_c -dir tests/



# -inline 0  to see all the functions in the profile.
# Can also use the profile framework in commons/ and run your program
# with -profile.
forprofiling:
	$(MAKE) OPTFLAGS="-p -inline 0 " opt

clean::
	rm -f gmon.out

tags:
	otags -no-mli-tags -r  .

dependencygraph:
	find  -name "*.ml" |grep -v "scripts" | xargs ocamldep -I commons -I globals -I ctl -I parsing_cocci -I parsing_c -I engine -I popl09 -I extra > /tmp/dependfull.depend
	ocamldot -lr /tmp/dependfull.depend > /tmp/dependfull.dot
	dot -Tps /tmp/dependfull.dot > /tmp/dependfull.ps
	ps2pdf /tmp/dependfull.ps /tmp/dependfull.pdf

##############################################################################
# Misc rules
##############################################################################

# each member of the project can have its own test.ml. this file is
# not under CVS.
test.ml:
	echo "let foo_ctl () = failwith \"there is no foo_ctl formula\"" \
	  > test.ml

beforedepend:: test.ml


#INC=$(dir $(shell which ocaml))
#INCX=$(INC:/=)
#INCY=$(dir $(INCX))
#INCZ=$(INCY:/=)/lib/ocaml
#
#prim.o: prim.c
#	gcc -c -o prim.o -I $(INCZ) prim.c


##############################################################################
# Generic ocaml rules
##############################################################################

.SUFFIXES: .ml .mli .cmo .cmi .cmx

.ml.cmo:
	$(OCAMLC)    -c $<
.mli.cmi:
	$(OCAMLC)    -c $<
.ml.cmx:
	$(OCAMLOPT)  -c $<

.ml.mldepend:
	$(OCAMLC) -i $<

clean::
	rm -f *.cm[iox] *.o *.annot
	rm -f *~ .*~ *.exe #*#

distclean:: clean
	set -e; for i in $(MAKESUBDIRS); do $(MAKE) -C $$i $@; done
	rm -f .depend
	rm -f Makefile.config
	rm -f python/pycocci.ml
	rm -f python/pycocci_aux.ml
	rm -f globals/config.ml
	rm -f TAGS
	rm -f tests/SCORE_actual.sexp
	rm -f tests/SCORE_best_of_both.sexp
	find -name ".#*1.*" | xargs rm -f

beforedepend::

depend:: beforedepend
	$(OCAMLDEP) *.mli *.ml > .depend
	set -e; for i in $(MAKESUBDIRS); do $(MAKE) -C $$i $@; done

.depend::
	@if [ ! -f .depend ] ; then $(MAKE) depend ; fi

-include .depend
