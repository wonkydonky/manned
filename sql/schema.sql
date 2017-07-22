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

CREATE TABLE packages (
  id       SERIAL    PRIMARY KEY,
  system   integer   NOT NULL REFERENCES systems(id) ON DELETE CASCADE,
  category varchar,
  name     varchar   NOT NULL,
  UNIQUE(system, name, category) -- Note the order, lookups on (system,name) are common
);

CREATE TABLE package_versions (
  id       SERIAL    PRIMARY KEY,
  package  integer   NOT NULL REFERENCES packages(id) ON DELETE CASCADE,
  version  varchar   NOT NULL,
  released date      NOT NULL,
  arch     varchar,
  UNIQUE(package, version)
);

CREATE TABLE man (
  package  integer   NOT NULL REFERENCES package_versions(id) ON DELETE CASCADE,
  name     varchar   NOT NULL,
  filename varchar   NOT NULL,
  locale   varchar,
  hash     bytea     NOT NULL REFERENCES contents(hash),
  section  varchar   NOT NULL,
  encoding varchar,
  UNIQUE(package, filename)
);

CREATE INDEX ON man (hash);
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
  (36, 'FreeBSD',    '2.2.7', 'freebsd-2.2.7',   7),
  (37, 'FreeBSD',    '2.2.8', 'freebsd-2.2.8',   8),
  (38, 'FreeBSD',    '3.0',   'freebsd-3.0',     9),
  (39, 'FreeBSD',    '3.1',   'freebsd-3.1',     10),
  (40, 'FreeBSD',    '3.2',   'freebsd-3.2',     11),
  (41, 'FreeBSD',    '3.3',   'freebsd-3.3',     12),
  (42, 'FreeBSD',    '3.4',   'freebsd-3.4',     13),
  (43, 'FreeBSD',    '3.5',   'freebsd-3.5',     14),
  (44, 'FreeBSD',    '3.5.1', 'freebsd-3.5.1',   15),
  (45, 'FreeBSD',    '4.0',   'freebsd-4.0',     16),
  (46, 'FreeBSD',    '4.1',   'freebsd-4.1',     17),
  (47, 'FreeBSD',    '4.1.1', 'freebsd-4.1.1',   18),
  (48, 'FreeBSD',    '4.2',   'freebsd-4.2',     19),
  (49, 'FreeBSD',    '4.3',   'freebsd-4.3',     20),
  (50, 'FreeBSD',    '4.4',   'freebsd-4.4',     21),
  (51, 'FreeBSD',    '4.5',   'freebsd-4.5',     22),
  (52, 'FreeBSD',    '4.6',   'freebsd-4.6',     23),
  (53, 'FreeBSD',    '4.6.2', 'freebsd-4.6.2',   24),
  (54, 'FreeBSD',    '4.7',   'freebsd-4.7',     25),
  (55, 'FreeBSD',    '4.8',   'freebsd-4.8',     26),
  (56, 'FreeBSD',    '4.9',   'freebsd-4.9',     27),
  (57, 'FreeBSD',    '4.10',  'freebsd-4.10',    28),
  (58, 'FreeBSD',    '4.11',  'freebsd-4.11',    29),
  (59, 'FreeBSD',    '5.0',   'freebsd-5.0',     30),
  (60, 'FreeBSD',    '5.1',   'freebsd-5.1',     31),
  (61, 'FreeBSD',    '5.2',   'freebsd-5.2',     32),
  (62, 'FreeBSD',    '5.2.1', 'freebsd-5.2.1',   33),
  (63, 'FreeBSD',    '5.3',   'freebsd-5.3',     34),
  (64, 'FreeBSD',    '5.4',   'freebsd-5.4',     35),
  (65, 'FreeBSD',    '5.5',   'freebsd-5.5',     36),
  (66, 'FreeBSD',    '6.0',   'freebsd-6.0',     37),
  (67, 'FreeBSD',    '6.1',   'freebsd-6.1',     38),
  (68, 'FreeBSD',    '6.2',   'freebsd-6.2',     39),
  (69, 'FreeBSD',    '6.3',   'freebsd-6.3',     40),
  (70, 'FreeBSD',    '6.4',   'freebsd-6.4',     41),
  (71, 'FreeBSD',    '7.0',   'freebsd-7.0',     42),
  (72, 'FreeBSD',    '7.1',   'freebsd-7.1',     43),
  (73, 'FreeBSD',    '7.2',   'freebsd-7.2',     44),
  (74, 'FreeBSD',    '7.3',   'freebsd-7.3',     45),
  (75, 'FreeBSD',    '7.4',   'freebsd-7.4',     46),
  (76, 'FreeBSD',    '8.0',   'freebsd-8.0',     47),
  (77, 'FreeBSD',    '8.1',   'freebsd-8.1',     48),
  (78, 'FreeBSD',    '8.2',   'freebsd-8.2',     49),
  (79, 'FreeBSD',    '8.3',   'freebsd-8.3',     50),
  (80, 'FreeBSD',    '9.0',   'freebsd-9.0',     52),
  (81, 'Ubuntu',     '12.10', 'ubuntu-quantal',  16),
  (82, 'Ubuntu',     '13.04', 'ubuntu-raring',   17),
  (83, 'Debian',     '7.0',   'debian-wheezy',   11),
  (84, 'FreeBSD',    '8.4',   'freebsd-8.4',     51),
  (85, 'FreeBSD',    '9.1',   'freebsd-9.1',     53),
  (86, 'FreeBSD',    '9.2',   'freebsd-9.2',     54),
  (87, 'Ubuntu',     '13.10', 'ubuntu-saucy',    18),
  (88, 'Ubuntu',     '14.04', 'ubuntu-trusty',   19),
  (89, 'Ubuntu',     '14.10', 'ubuntu-utopic',   20),
  (90, 'Ubuntu',     '15.04', 'ubuntu-vivid',    21),
  (91, 'Debian',     '8.0',   'debian-jessie',   12),
  (92, 'Ubuntu',     '15.10', 'ubuntu-wily',     22),
  (93, 'Ubuntu',     '16.04', 'ubuntu-xenial',   23),
  (94, 'FreeBSD',    '9.3',   'freebsd-9.3',     55),
  (95, 'FreeBSD',    '10.0',  'freebsd-10.0',    56),
  (96, 'FreeBSD',    '10.1',  'freebsd-10.1',    57),
  (97, 'FreeBSD',    '10.2',  'freebsd-10.2',    58),
  (98, 'FreeBSD',    '10.3',  'freebsd-10.3',    59),
  (99, 'FreeBSD',    '11.0',  'freebsd-11.0',    60),
  (100,'Ubuntu',     '16.10', 'ubuntu-yakkety',  24),
  (101,'Fedora',     '1',     'fedora-1',        0),
  (102,'Fedora',     '2',     'fedora-2',        1),
  (103,'Fedora',     '3',     'fedora-3',        2),
  (104,'Fedora',     '4',     'fedora-4',        3),
  (105,'Fedora',     '5',     'fedora-5',        4),
  (106,'Fedora',     '6',     'fedora-6',        5),
  (107,'Fedora',     '7',     'fedora-7',        6),
  (108,'Fedora',     '8',     'fedora-8',        7),
  (109,'Fedora',     '9',     'fedora-9',        8),
  (110,'Fedora',     '10',    'fedora-10',       9),
  (111,'Fedora',     '11',    'fedora-11',       10),
  (112,'Fedora',     '12',    'fedora-12',       11),
  (113,'Fedora',     '13',    'fedora-13',       12),
  (114,'Fedora',     '14',    'fedora-14',       13),
  (115,'Fedora',     '15',    'fedora-15',       14),
  (116,'Fedora',     '16',    'fedora-16',       15),
  (117,'Fedora',     '17',    'fedora-17',       16),
  (118,'Fedora',     '18',    'fedora-18',       17),
  (119,'Fedora',     '19',    'fedora-19',       18),
  (120,'Fedora',     '20',    'fedora-20',       19),
  (121,'Fedora',     '21',    'fedora-21',       20),
  (122,'Fedora',     '22',    'fedora-22',       21),
  (123,'Fedora',     '23',    'fedora-23',       22),
  (124,'Fedora',     '24',    'fedora-24',       23),
  (125,'Fedora',     '25',    'fedora-25',       24),
  (126,'Ubuntu',     '17.04', 'ubuntu-zesty',    25),
  (127,'Debian',     '9.0',   'debian-stretch',  13),
  (128,'Fedora',     '26',    'fedora-26',       25);


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


CREATE OR REPLACE FUNCTION is_english_locale(locale text) RETURNS bool AS $$
  SELECT locale IS NULL OR locale LIKE 'en%';
$$ IMMUTABLE LANGUAGE SQL;


CREATE OR REPLACE FUNCTION is_standard_man_location(path text) RETURNS bool AS $$
  SELECT path LIKE '/usr/share/man/man%' OR path LIKE '/usr/local/man/man%';
$$ IMMUTABLE LANGUAGE sql;
