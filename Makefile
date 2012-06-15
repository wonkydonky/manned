.PHONY: GrottyParser

GrottyParser: lib/GrottyParser/Build
	cd lib/GrottyParser && ./Build install --install-base=inst

lib/GrottyParser/Build: lib/GrottyParser/Build.PL
	cd lib/GrottyParser && perl Build.PL

clean:
	cd lib/GrottyParser && ./Build distclean
	rm -rf lib/GrottyParser/inst

