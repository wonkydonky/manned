
-- TODO: "system" -> "repository"?
-- TODO: index of (reverse) man page references?
-- TODO: Probably want an index on man(name) and man(hash)
-- TODO: Use some consistent naming of tables and columns


CREATE TABLE systems (
  id       integer PRIMARY KEY,  -- hardcoded ID.
  name     varchar NOT NULL,
  release  varchar,
  relorder integer NOT NULL DEFAULT 0, -- simple way of ordering different releases for the same system
  short    varchar NOT NULL
);


CREATE TABLE contents (
  hash    bytea      PRIMARY KEY,
  content varchar    NOT NULL
);


-- Note: If there are multiple arches available for the same package, then
-- generally only a single one is chosen (not stored here which one).
-- Also, a package may be listed here even if it has no man pages indexed, in
-- order for the fetcher to determine whether it has already processed the
-- package or not. This doesn't mean all packages of a repository are listed
-- here. For example, the Arch fetcher checks the file list of a package before
-- considering to handle it.
CREATE TABLE package (
  id       SERIAL    PRIMARY KEY,
  system   integer   NOT NULL REFERENCES systems(id),
  category varchar,            -- depends on system (e.g. "community" on Arch, "x11" on Debian)
  name     varchar   NOT NULL,
  version  varchar   NOT NULL,
  released date      NOT NULL,
  UNIQUE(system, name, version)
);


CREATE TABLE man (
  package  integer   NOT NULL REFERENCES package(id),
  name     varchar   NOT NULL, -- 'fopen', 'du', etc (TODO: An index on name_from_filename(filename) may also work)
  section  varchar   NOT NULL, -- extracted from filename (TODO: Is this column really necessary?)
  filename varchar   NOT NULL, -- full path + file name
  locale   varchar,            -- parsed from the file name, NULL for the "main" man page (in the C or en_US locale)
  hash     bytea     NOT NULL REFERENCES contents(hash),
  UNIQUE(package, filename)
);


INSERT INTO systems (id, name, release, short, relorder) VALUES
  (1, 'Arch Linux', NULL,   'arch', 0),
  (2, 'Ubuntu',     '4.10', 'ubuntu-warty', 0),
  (3, 'Ubuntu',     '5.04', 'ubuntu-hoary', 1),
  (4, 'Ubuntu',     '5.10', 'ubuntu-breezy', 2);


-- Removes any path components and compression extensions from the filename.
CREATE OR REPLACE FUNCTION basename_from_filename(fn text) RETURNS text AS $$
DECLARE
  ret text;
  tmp text;
BEGIN
  ret := regexp_replace(fn, '^.+/([^/]+)', E'\\1');
  LOOP
    tmp := regexp_replace(regexp_replace(regexp_replace(ret, E'\\.gz$', ''), E'\\.lzma$', ''), E'\\.bz2$', '');
    EXIT WHEN tmp = ret;
    ret := tmp;
  END LOOP;
  RETURN ret;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION section_from_filename(text) RETURNS text AS $$
  SELECT regexp_replace(basename_from_filename($1), E'^.+\\.([^.]+)$', E'\\1');
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION name_from_filename(text) RETURNS text AS $$
  SELECT regexp_replace(basename_from_filename($1), E'^(.+)\\.[^.]+$', E'\\1');
$$ LANGUAGE SQL;




-- Some handy admin queries

--BEGIN;
--DELETE FROM man WHERE package IN(SELECT id FROM package WHERE name = '');
--DELETE FROM package WHERE name = '';
--DELETE FROM contents c WHERE NOT EXISTS(SELECT 1 FROM man m WHERE m.hash = c.hash);
--COMMIT;

