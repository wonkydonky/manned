#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"


// Convert grotty output to HTML for use in a <pre> tag.
// It is assumed that the given input string is valid UTF-8, either represented
// as a Perl Unicode string, or as a UTF-8 encoded byte string. The data may
// not contain the 0 character.
// The formatted HTML is returned as a Perl Unicode string.
// It is also assumed that hyphenation has been disabled when generating the
// grotty output.


// This implementation really is fast enough for "real-time" use in the website
// code, very much unlike my experiments with Perl. My previous Perl
// implementation took about 1.5s for rsync(1), whereas I've not seen this
// implementation take more than 15ms.

// TODO: Unicode characters aren't truncated correctly when a line exceeds
// MAXLINE bytes. I've only seen this happening on man pages that grotty
// couldn't wrap, e.g. some Japanese and Chinese mans.
// (Ideally, I'd tell grotty how to wrap those correctly)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MAXLINE 1024

#define LB 1
#define LI 2

typedef struct ctx_t {
  const char *src; // Pointer to the source data, or what's left of it.
  SV *dest; // Destination string to write to.

  // Current line
  char line[MAXLINE];
  char flags[MAXLINE]; // 0 = no fmt, LB = bold, LI = italic. (No combinations allowed)
  int linelen;
  int noref; // 1 if the current line shouldn't be checked for references. (Used for first and last line)
} ctx_t;



// Escapes and appends a displayed character to the output string.
static inline void flushescape(ctx_t *x, char c) {
  static char str[2] = {};
  // Most HTML-escape functions also escape " to &quot;, but since we aren't
  // going to put a man page in an XML attribute, we don't really have to worry
  // about that one.
  switch(c) {
    case '>': sv_catpvn(x->dest, "&gt;", 4); break;
    case '<': sv_catpvn(x->dest, "&lt;", 4); break;
    case '&': sv_catpvn(x->dest, "&amp;", 5); break;
    default:
      str[0] = c;
      sv_catpvn(x->dest, str, 1);
  }
}


// HTML-escapes and adds formatting tags to a certain chunk of data and appends
// it to the output string. The chunk is considered as an individual part,
// assuming that any formatting is disabled at the start of the chunk, and
// making sure it is disabled again at the end.
// e points to the last character in s that is not considered part of the chunk.
static void flushchunk(ctx_t *x, const char *s, const char *f, const char *e) {
  int fmt = 0;

#define EFMT if(fmt) sv_catpvn(x->dest, fmt == LB ? "</b>" : "</i>", 4)

  while(s != e) {
    // Consider underscore and whitespace to have the same formatting as the
    // previous character.  The grotty escape sequences don't work well for the
    // underscore character, and you can't see the difference either way.
    if(fmt != *f && *s != '_' && *s != ' ') {
      EFMT;
      fmt = *f;
      if(fmt)
        sv_catpvn(x->dest, fmt == LB ? "<b>" : "<i>", 3);
    }
    flushescape(x, *s);
    s++;
    f++;
  }
  EFMT;

#undef EFMT
}


#define ismanchar(x) (isalnum(x) || x == '_' || x == '-' || x == '.')


static void flushinclude(ctx_t *x) {
  char buf[8] = {};
  char *s = x->line;

  s[x->linelen-3] = 0;
  s += 17;
  char *fn = strrchr(s, '/');
  fn = fn ? fn+1 : s;
  sv_catpv(x->dest, "&gt;&gt; Included manual page: <a href=\"/");

  // Replace ‐ (U+2010) with - (U+2d). ASCII dashes are replaced with an
  // Unicode dash when passed through groff, which we need to revert in order
  // to get the link working. (Apparently it recognizes man page references and
  // URLs, as it doesn't do this replacement in those situations.)
  while(*fn) {
    if(*fn == (char)0xe2 && fn[1] == (char)0x80 && fn[2] == (char)0x90) {
      buf[0] = '-';
      fn += 3;
    } else {
      buf[0] = *fn;
      fn++;
    }
    sv_catpvn(x->dest, buf, 1);
  }

  sv_catpv(x->dest, "\">");
  sv_catpv(x->dest, s);
  sv_catpv(x->dest, "</a>");
}


// HTML-escapes and "Flushes" the current line to the output string. Tries to
// convert man references and URLs into links if format is true.
static void flushline(ctx_t *x) {
  static const char eol[] = "\n";
  char *s = x->line, *es = x->line;

  // Special-case [[[MANNEDINCLUDE ..]]] directive
  if(x->linelen > 20 && *s == '[' && strncmp(s, "[[[MANNEDINCLUDE ", 17) == 0 && strcmp("]]]", s+x->linelen-3) == 0) {
    flushinclude(x);
    goto end;
  }

  if(x->noref) {
    flushchunk(x, x->line, x->flags, x->line+x->linelen);
    goto end;
  }

#define flush(end) do {\
    flushchunk(x, es, x->flags+(es-x->line), end);\
    es = end;\
  } while(0)

  while(*s) {
    // Man page reference.
    // Detected by the "(x)", but then checked backwards in the buffer to find
    // the start of the reference. This is pretty fast. Fails on:
    // - JSON.3pm: JSON->new->utf8(1)->pretty(1)->encode($perl_scalar)
    if(*s == '(' && (('1' <= s[1] && s[1] <= '9') || s[1] == 'n') && s[2] == ')' && !isalnum(s[3])) {
      char *n = s-1;
      while(n >= es && ismanchar(*n))
        n--;
      if(++n < s) {
        flush(n);
        *s = 0;
        sv_catpvf(x->dest, "<a href=\"/%s.%c\">%s(%c)</a>", n, s[1], n, s[1]);
        s += 3;
        es = s;
        continue;
      }
    }

    // HTTP(s) URL.
    // This is just a simple q{https?://[^ ][.,;"\)>]?( |$)} match, doesn't
    // always work right:
    // - chmod.1: <http://gnu.org/licenses/gpl.html>.
    // - pod2man.1: <http://www.eyrie.org/~eagle/software/podlators/>.
    // - troff.1: ⟨http://www.gnu.org/copyleft/fdl.html⟩.    <- yes, that's an Unicode character.
    // - roff.7: Has quite a few issues with wrapped URLs and situations similar to the above.
    // - JSON.3pm: "RFC4627"(<http://www.ietf.org/rfc/rfc4627.txt>).
    // Note: Don't use strncmp() before manually checking for 'http'. The parse
    // time is otherwise increased by a factor 2.
    if(s[0] == 'h' && s[1] == 't' && s[2] == 't' && s[3] == 'p' && (strncmp(s, "http://", 7) == 0 || strncmp(s, "https://", 8) == 0)) {
      char *sep = strchr(s, ' ');
      if(!sep)
        sep = s+strlen(s);
      char *sp = sep;
      if(sp > s+10) {
        flush(s);
        char endchr = *sp;
        *(sp--) = 0;
        if(*sp == '.' || *sp == ',' || *sp == ';' || *sp == '"' || *sp == ')' || *sp == '>') {
          sp[1] = endchr;
          endchr = *sp;
          *(sp--) = 0;
        }
        sv_catpvf(x->dest, "<a href=\"%s\" rel=\"nofollow\">%s</a>", s, s);
        *(++sp) = endchr;
        es = s = sp;
        continue;
      }
    }
    s++;
  }

  flush(s);
#undef flush

end:
  sv_catpvn(x->dest, eol, sizeof(eol)-1);
}


// Adds a character to the current line, calls flushline() when a new line is done.
// TODO: Convert \t into spaces? The rest of the code is written with the
// assumption that \t does not occur in the string. I've not seen grotty output
// tabs yet, but it's still a good idea to define what *we* do with tabs.
static void appendline(ctx_t *x, char c, char f) {
  if(c == '\r')
    return;

  if(c == '\n' || x->linelen > MAXLINE+1) {
    x->line[x->linelen] = 0;
    flushline(x);
    x->linelen = 0;
    x->noref = 0;
    if(c == '\n')
      return;
  }

  x->line[x->linelen] = c;
  x->flags[x->linelen] = f;
  x->linelen++;
}


// Parses the grotty escapes and calls appendline() for each character.
static void parselines(ctx_t *x) {
  int i, ini = 0, inb = 0;
  const char *buf = x->src;

  while(*buf) {
    int c1 = UTF8SKIP(buf);
    // Escape character right after a formatting code? Ignore the escape
    // character and formatting code after that. Grotty sometimes
    // double-formats a character, so you get "f ESC c ESC f ESC c", which you
    // should read as "(f ESC c) ESC (f ESC c)".
    if(*buf == 8 && buf[1] && buf[1+UTF8SKIP(buf+1)] == 8 && buf[2+UTF8SKIP(buf+1)]) {
      int c2 = UTF8SKIP(buf+1);
      buf += 2 + c2 + UTF8SKIP(buf+1+c2);
      continue;
    }
    // Formatting code
    if(buf[c1] == 8 && buf[c1+1]) {
      int c2 = UTF8SKIP(buf+c1+1);
      for(i=0; i<c2; i++)
        appendline(x, buf[c1+i+1], *buf == '_' ? LI : LB);
      buf += c1+c2+1;
      continue;
    }
    // Regular character
    if(*buf == '\n' && !buf[1])
      x->noref = 1;
    appendline(x, *buf, 0);
    buf++;
  }
  x->noref = 1;
  appendline(x, '\n', 0);
}



MODULE = ManUtils	 PACKAGE = ManUtils

SV *
html(str)
  SV *str
  INIT:
    ctx_t *x = malloc(sizeof(ctx_t));
  CODE:
    x->src = SvPV_nolen(str);
    x->dest = newSVpv("", 0);
    x->linelen = 0;
    x->noref = 1;
    parselines(x);
    // Set the UTF8 flag *after* generating the result string. For some reason
    // that prevents sv_catpvf() from interpreting our C strings as something
    // other than UTF-8.
    SvUTF8_on(x->dest);
    RETVAL = x->dest;
    free(x);
  OUTPUT:
    RETVAL

