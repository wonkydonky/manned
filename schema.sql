
-- TODO: "system" -> "repository"?
-- TODO: index of (reverse) man page references?
-- TODO: Probably want an index on man(name). Or try swapping column order in the unique index.
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


CREATE INDEX ON man USING hash (hash);
CREATE INDEX ON man (name);


CREATE TABLE man_index AS SELECT DISTINCT name, section FROM man;
CREATE INDEX ON man_index USING btree(lower(name) text_pattern_ops);

CREATE TABLE stats_cache AS SELECT count(distinct hash) AS hashes, count(distinct name) AS mans, count(*) AS files, count(distinct package) AS packages FROM man;


INSERT INTO systems (id, name, release, short, relorder) VALUES
  (1,  'Arch Linux', NULL,    'arch',            0),
  (2,  'Ubuntu',     '4.10',  'ubuntu-warty',    0),
  (3,  'Ubuntu',     '5.04',  'ubuntu-hoary',    1),
  (4,  'Ubuntu',     '5.10',  'ubuntu-breezy',   2),
  (5,  'Ubuntu',     '6.06',  'ubuntu-dapper',   3),
  (6,  'Ubuntu',     '6.10',  'ubuntu-edgy',     4),
  (7,  'Ubuntu',     '7.04',  'ubuntu-feisty',   5),
  (8,  'Ubuntu',     '7.10',  'ubuntu-gutsy',    6),
  (9,  'Ubuntu',     '8.04',  'ubuntu-hardy',    7),
  (10, 'Ubuntu',     '8.10',  'ubuntu-intrepid', 8),
  (11, 'Ubuntu',     '9.04',  'ubuntu-jaunty',   9),
  (12, 'Ubuntu',     '9.10',  'ubuntu-karmic',   10),
  (13, 'Ubuntu',     '10.04', 'ubuntu-lucid',    11),
  (14, 'Ubuntu',     '10.10', 'ubuntu-maverick', 12),
  (15, 'Ubuntu',     '11.04', 'ubuntu-natty',    13),
  (16, 'Ubuntu',     '11.10', 'ubuntu-oneiric',  14),
  (17, 'Ubuntu',     '12.04', 'ubuntu-precise',  15),
  (18, 'Debian',     '1.1',   'debian-buzz',     0),
  (19, 'Debian',     '1.2',   'debian-rex',      1),
  (20, 'Debian',     '1.3',   'debian-bo',       2),
  (21, 'Debian',     '2.0',   'debian-hamm',     3),
  (22, 'Debian',     '2.1',   'debian-slink',    4),
  (23, 'Debian',     '2.2',   'debian-potato',   5),
  (24, 'Debian',     '3.0',   'debian-woody',    6),
  (25, 'Debian',     '3.1',   'debian-sarge',    7),
  (26, 'Debian',     '4.0',   'debian-etch',     8),
  (27, 'Debian',     '5.0',   'debian-lenny',    9),
  (28, 'Debian',     '6.0',   'debian-squeeze',  10),
  (29, 'FreeBSD',    '1.0',   'freebsd-1.0',     0),
  (30, 'FreeBSD',    '2.0.5', 'freebsd-2.0.5',   1),
  (31, 'FreeBSD',    '2.1.5', 'freebsd-2.1.5',   2),
  (32, 'FreeBSD',    '2.1.7', 'freebsd-2.1.7',   3),
  (33, 'FreeBSD',    '2.2.2', 'freebsd-2.2.2',   4),
  (34, 'FreeBSD',    '2.2.5', 'freebsd-2.2.5',   5),
  (35, 'FreeBSD',    '2.2.6', 'freebsd-2.2.6',   6),
  (36, 'FreeBSD',    '2.2.7', 'freebsd-2.2.7',   7);


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

--DELETE FROM package WHERE system = 18 AND NOT EXISTS(SELECT 1 FROM man WHERE id = package);
