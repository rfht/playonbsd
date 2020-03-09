PREFIX ?= /usr/local

.PHONY: install
install:
	cp playonbsd-cli.pl $(DESTDIR)$(PREFIX)/bin/
	cp playonbsd-cli.1 $(DESTDIR)$(PREFIX)/man/man1/

readme: playonbsd-cli.1
	mandoc -mdoc -T markdown playonbsd-cli.1 > README.md

.PHONY: uninstall
uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/playonbsd-cli.pl
	rm -f $(DESTDIR)$(PREFIX)/man/man1/playonbsd-cli.1
