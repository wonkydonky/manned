-- Various non-manpages
DELETE FROM man
 WHERE filename ~ '/Makefile\.(in|am)$'
    OR filename ~ '/\.cvsignore(\.gz)?$'
    OR filename !~ '/[^/]*\.[^/]*$'
    OR filename ~ '/man\.tmp$';

-- Wrong locales, found with:
--   SELECT DISTINCT Locale FROM man ORDER BY locale;
UPDATE man SET locale = NULL
 WHERE locale = '5man'
    OR locale = 'c'
    OR locale ~ '^man.?$'
    OR locale ~ '^Man-Part[12]$';

-- Man page containing only a '$1'. Likely a build failure in earlier FreeBSD releases.
DELETE FROM man WHERE hash = '\x5ea7b8101325c704551852f70b652e0a2b0d7c12';

DELETE FROM contents c WHERE NOT EXISTS(SELECT 1 FROM man m WHERE m.hash = c.hash);
