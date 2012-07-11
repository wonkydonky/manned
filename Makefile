.PHONY: ManUtils

ManUtils: lib/ManUtils/Build
	cd lib/ManUtils && ./Build install --install-base=inst

lib/ManUtils/Build: lib/ManUtils/Build.PL
	cd lib/ManUtils && perl Build.PL

clean:
	cd lib/ManUtils && ./Build distclean
	rm -rf lib/ManUtils/inst

