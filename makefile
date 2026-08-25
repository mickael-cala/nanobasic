# Makefile pour NanoBasic
# (c) 2026 Mickaël Cala
# Cible : Linux/macOS/MSYS2 (GNU make + shell POSIX).
# Sous Windows natif, utiliser les harnais batch : tests\run_tests_exe.bat + tests\run_tests_bas.bat

FPC = fpc
FPCFLAGS = -Mobjfpc -O2 -S2h -Ci -Co -Ct -Cri -Fu$(SRCDIR)
TARGET = nanobasic
SRCDIR = src
OBJDIR = obj
BINDIR = bin

# Suffixe executeur : .exe sous Windows (make sous MSYS2/Cygwin), rien ailleurs
ifeq ($(OS),Windows_NT)
EXEEXT = .exe
else
EXEEXT =
endif
TARGETBIN = $(BINDIR)/$(TARGET)$(EXEEXT)

SOURCES = $(SRCDIR)/nanotypes.pas $(SRCDIR)/nanolexer.pas \
          $(SRCDIR)/nanoparser.pas $(SRCDIR)/nanovm.pas \
          $(SRCDIR)/nanobasic.pas

# Scripts de test NON interactifs (aucun INPUT bloquant) qui doivent passer
TEST_BAS = examples/test_3d.bas examples/test_arrays.bas examples/test_demo.bas \
           examples/test_functions.bas examples/test_gosub.bas examples/test_io.bas \
           examples/test_logic.bas examples/test_master.bas examples/test_routines.bas \
           examples/test_select.bas examples/test_stress_loops.bas examples/test_stress_math.bas \
           examples/test_stress_memory.bas examples/test_structured.bas \
           examples/test_torture_master.bas examples/test_types.bas \
           examples/test_v1.bas examples/test_v2.bas
# demo.bas / test.bas : exemples interactifs (INPUT) -> volontairement exclus
# test_loop_dos.bas : test du watchdog (long) ; test_bad.bas : cas negatif -> cible test-negative

all: $(TARGETBIN)

$(TARGETBIN): $(SOURCES) | $(BINDIR) $(OBJDIR)
	$(FPC) $(FPCFLAGS) $(SRCDIR)/nanobasic.pas -FU$(OBJDIR) -o$@

$(BINDIR) $(OBJDIR):
	mkdir -p $@

check: $(TARGETBIN)
	@fail=0; for ex in $(TEST_BAS); do \
		echo "== LINT $$ex"; \
		$(TARGETBIN) --check "$$ex" || fail=1; \
	done; \
	if [ $$fail -ne 0 ]; then echo "ECHEC du lint statique"; exit 1; fi; \
	echo "Lint OK sur $$(echo $(TEST_BAS) | wc -w) scripts."

test: $(TARGETBIN)
	@fail=0; for ex in $(TEST_BAS); do \
		echo "== EXEC $$ex"; \
		$(TARGETBIN) "$$ex" < /dev/null || fail=1; \
	done; \
	if [ $$fail -ne 0 ]; then echo "ECHEC des tests"; exit 1; fi; \
	echo "Tests OK sur $$(echo $(TEST_BAS) | wc -w) scripts."

# Cas negatif : test_bad.bas DOIT etre rejete par le linter
test-negative: $(TARGETBIN)
	@echo "== LINT (doit echouer) examples/test_bad.bas"; \
	if $(TARGETBIN) --check examples/test_bad.bas < /dev/null 2>&1; then \
		echo "ECHEC : test_bad.bas aurait du etre rejete par le linter"; \
		exit 1; \
	fi; \
	echo "OK : test_bad.bas correctement rejete."

clean:
	rm -rf $(OBJDIR)/*.o $(OBJDIR)/*.ppu $(TARGETBIN)

install: $(TARGETBIN)
	install -m 755 $(TARGETBIN) $(DESTDIR)/usr/local/bin/

.PHONY: all check test test-negative clean install