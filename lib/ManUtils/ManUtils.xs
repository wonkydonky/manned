#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

struct StringWrap {
  char *buf;
  unsigned long long len, cap;
};

struct StringWrap grotty2html_wrap(const char *, unsigned long long);
void grotty2html_free(struct StringWrap);


MODULE = ManUtils	 PACKAGE = ManUtils

SV *
html(str)
  SV *str
  CODE:
    STRLEN len;
    char *inbuf = SvPV(str, len);
    struct StringWrap buf = grotty2html_wrap(inbuf, len);
    SV *dest = buf.len ? newSVpv(buf.buf, buf.len) : newSVpv("", 0);
    grotty2html_free(buf);
    SvUTF8_on(dest);
    RETVAL = dest;
  OUTPUT:
    RETVAL
