-- Create a new table before replacing in order to avoid a long-held lock on
-- the table being replaced. The site should remain responsive while these
-- queries are run.
BEGIN;
CREATE TABLE man_index_new AS SELECT DISTINCT name, section FROM man;
CREATE INDEX ON man_index_new USING btree(lower(name) text_pattern_ops);
DROP TABLE man_index;
ALTER TABLE man_index_new RENAME TO man_index;
COMMIT;
