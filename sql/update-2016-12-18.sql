-- Delete some non-man-pages, these are already blacklisted in indexer/man.rs:validate().
-- Found with:
--   select hash from contents where content like e'\x7fELF%' or length(content) < 9 or content = e'timestamp\n' or content = e'.so man3/\n';
DELETE FROM man WHERE hash IN(
  '\x0c8b9d6f753e8d8ec9276bfe98e993a133847642',
  '\x2c0f4624792234e2c289eec5b6bad1c699f84128',
  '\x2d8b07a585e3f072aaa2c2b0ebac91d9039ccd54',
  '\x4853d24dbb7d81e4782ef1bb1162c143f808dda1',
  '\x6dfe263ccab32880795dff4479d990ade1daa839',
  '\x72d08cf649f7a5cb0a9434d5b591878b2f7a0df9',
  '\x816aff0cb37d6c9ccbfa48fffec83e39b37193fa',
  '\x8af6f3e189ca29abb3a0ba51d7ef5e7e70451639',
  '\x8e5113f6f47ce34e0437c2105441dbb70f01491a',
  '\x92d754c27d4a6f851505be63aad6366857060f42',
  '\x9312a9f378cc7750c4f473e3fdbd1d9b4aaf1efa',
  '\x9f83db09859f909ce36b5aa97ec412c09ea27a76',
  '\xadc83b19e793491b1c6ea0fd8b46cd9f32e592fc',
  '\xb226262bf9f49e1098612ffdfc01680f7f305f70',
  '\xc1a1a4edf60cfd417d52fc7bf1698bf0b6c814e6',
  '\xda39a3ee5e6b4b0d3255bfef95601890afd80709',
  '\xe04aededffd5ff6a3bc1a5294796ce1efa4dc68d',
  '\xfe847f886e2d883a946282a552123dbba00f9596',
  '\xffecacd94bd2bc4488db35a6b761ed430a65ac8f'
);

DELETE FROM contents c WHERE NOT EXISTS(SELECT 1 FROM man m WHERE m.hash = c.hash);
