.PHONY: ManUtils indexer clean

all: ManUtils indexer


ManUtils: lib/ManUtils/inst/lib/perl5/x86_64-linux/ManUtils.pm

lib/ManUtils/inst/lib/perl5/x86_64-linux/ManUtils.pm: lib/ManUtils/Build.PL lib/ManUtils/ManUtils.pm lib/ManUtils/ManUtils.xs web/target/release/libweb.a
	test lib/ManUtils/ManUtils.xs -ot web/target/release/libweb.a && touch -r web/target/release/libweb.a lib/ManUtils/ManUtils.xs
	cd lib/ManUtils && perl Build.PL && ./Build install --install-base=inst
	touch lib/ManUtils/inst/lib/perl5/x86_64-linux/ManUtils.pm

web/target/release/libweb.a: web/Cargo.toml web/src/*.rs
	cd web && cargo build --release
	#strip --strip-unneeded web/target/release/libweb.a


indexer: indexer/target/release/indexer

indexer/target/release/indexer: indexer/Cargo.toml indexer/src/*.rs
	cd indexer && cargo build --release


clean:
	cd lib/ManUtils && ./Build distclean
	rm -rf lib/ManUtils/inst
	cd indexer && cargo clean
	cd web && cargo clean
