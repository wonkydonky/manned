.PHONY: ManUtils indexer clean

all: ManUtils indexer

ManUtils: lib/ManUtils/Build
	cd lib/ManUtils && perl Build.PL && ./Build install --install-base=inst

lib/ManUtils/Build: lib/ManUtils/Build.PL
	cd lib/ManUtils && perl Build.PL

indexer: indexer/target/release/indexer

indexer/target/release/indexer: indexer/Cargo.toml indexer/src/*.rs
	cd indexer && cargo build --release

clean:
	cd lib/ManUtils && ./Build distclean
	rm -rf lib/ManUtils/inst
	cd indexer && cargo clean
