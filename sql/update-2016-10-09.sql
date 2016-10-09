CREATE OR REPLACE FUNCTION is_english_locale(locale text) RETURNS bool AS $$
  SELECT locale IS NULL OR locale LIKE 'en%';
$$ IMMUTABLE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION is_standard_man_location(path text) RETURNS bool AS $$
  SELECT path LIKE '/usr/share/man/man%' OR path LIKE '/usr/local/man/man%';
$$ IMMUTABLE LANGUAGE sql;
