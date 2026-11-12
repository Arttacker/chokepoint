PREFIX ?= /usr/local
BINDIR  = $(PREFIX)/bin
DATADIR = $(PREFIX)/share/chokepoint

.PHONY: install uninstall check

install:
	install -Dm755 chokepoint $(DESTDIR)$(BINDIR)/chokepoint
	install -d $(DESTDIR)$(DATADIR)/profiles
	install -m644 profiles/*.yml $(DESTDIR)$(DATADIR)/profiles/

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/chokepoint
	rm -rf $(DESTDIR)$(DATADIR)

check:
	bash -n chokepoint
	./chokepoint check
