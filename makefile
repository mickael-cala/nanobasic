# Makefile pour Nanobasic
# (c) 2026 Mickaël Cala

FPC = fpc
FPCFLAGS = -Mobjfpc -O2 -S2h -Ci -Co -Ct -Cri -FUobj -FEbin
TARGET = nanobasic
SRCDIR = src
OBJDIR = obj
BINDIR = bin
SOURCES = $(SRCDIR)/nanobasic.pas $(SRCDIR)/scanner.pas $(SRCDIR)/parser.pas \
          $(SRCDIR)/interpreter.pas $(SRCDIR)/ast.pas $(SRCDIR)/errors.pas
OBJECTS = $(OBJDIR)/scanner.o $(OBJDIR)/parser.o $(OBJDIR)/interpreter.o \
          $(OBJDIR)/ast.o $(OBJDIR)/errors.o $(OBJDIR)/nanobasic.o

all: $(BINDIR)/$(TARGET)

$(BINDIR)/$(TARGET): $(SOURCES) | $(BINDIR)
	$(FPC) $(FPCFLAGS) $(SRCDIR)/nanobasic.pas -o$@

$(BINDIR):
	mkdir -p $(BINDIR)

$(OBJDIR):
	mkdir -p $(OBJDIR)

clean:
	rm -rf $(OBJDIR)/*.o $(OBJDIR)/*.ppu $(BINDIR)/$(TARGET) $(BINDIR)/$(TARGET).exe

test: $(BINDIR)/$(TARGET)
	@echo "Running examples..."
	@for ex in examples/*.bas; do \
		echo "Executing $$ex"; \
		$(BINDIR)/$(TARGET) "$$ex"; \
	done

install: $(BINDIR)/$(TARGET)
	install -m 755 $(BINDIR)/$(TARGET) /usr/local/bin/

.PHONY: all clean test install