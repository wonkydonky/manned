-- This check is not consistent with the HTML-check in util/add_dir.pl, but it
-- happens to match exactly the same man pages currently.
DELETE FROM man WHERE section = 'html';
DELETE FROM contents c WHERE NOT EXISTS(SELECT 1 FROM man m WHERE m.hash = c.hash);
