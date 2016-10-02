CREATE TABLE packages (
  id       SERIAL    PRIMARY KEY,
  system   integer   NOT NULL REFERENCES systems(id),
  category varchar,
  name     varchar   NOT NULL,
  UNIQUE(system, name, category) -- Note the order, lookups on (system,name) are common
);

CREATE TABLE package_versions (
  id       SERIAL    PRIMARY KEY,
  package  integer   NOT NULL REFERENCES packages(id),
  version  varchar   NOT NULL,
  released date      NOT NULL,
  UNIQUE(package, version)
);

INSERT INTO packages (system, category, name) SELECT system, category, name FROM package GROUP BY system, category, name;
INSERT INTO package_versions (id, package, version, released)
  SELECT p.id, pn.id, p.version, p.released FROM package p JOIN packages pn ON pn.system = p.system AND pn.category = p.category AND pn.name = p.name;

SELECT setval('package_versions_id_seq', nextval('package_id_seq'));

ALTER TABLE man DROP CONSTRAINT man_package_fkey;
ALTER TABLE man ADD FOREIGN KEY (package) REFERENCES package_versions(id);

-- Use a proper b-tree index
DROP INDEX man_hash_idx;
CREATE INDEX ON man (hash);

-- DROP TABLE package;
