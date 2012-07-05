#!/usr/bin/perl

use strict;
use warnings;
use TUWF ':html', 'html_escape';
use IPC::Open2;
use IO::Select;
use Encode 'encode_utf8', 'decode_utf8';
use Time::HiRes 'tv_interval', 'gettimeofday';
use JSON::XS;

use Cwd 'abs_path';
our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/www/index\.pl$}{}; }


use lib "$ROOT/lib/GrottyParser/inst/lib/perl5";
use GrottyParser;


TUWF::set(
  logfile => $ENV{TUWF_LOG},
  db_login => [undef, undef, undef],
  debug => 1,
  xml_pretty => 0,
  # Cache the system information
  pre_request_handler => sub {
    my $self = shift;
    if(!$self->{systems}) {
      $self->{systems} = $self->dbSystemGet;
      $_->{full} = $_->{name}.($_->{release}?' '.$_->{release}:'') for(@{$self->{systems}});
      $self->{sysbyid} = { map +($_->{id}, $_), @{$self->{systems}} };
      $self->{sysbyshort} = { map +($_->{short}, $_), @{$self->{systems}} };
    }
    1;
  },
);


TUWF::register(
  qr// => \&home,
  qr{info/about} => \&about,
  qr{browse/([^/]+)} => \&browsesys,
  qr{browse/([^/]+)/([^/]+)} => \&browsepkg,
  qr{([^/]+)/([0-9a-f]{8})} => \&man,
  qr{([^/]+)/([0-9a-f]{8})/src} => \&src,
  qr{([^/]+)} => \&man,
);

TUWF::run();


sub home {
  my $self = shift;
  $self->htmlHeader(title => 'Man Pages Archive');
  h1 'Man Pages Archive';
  # Relevant query: SELECT count(distinct hash), count(distinct name), count(*), count(distinct package) FROM man;
  # It's far too slow to run that on every pageview. :-(
  p style => 'float: none'; lit <<'  _';
   Indexing <b>519,202</b> versions of <b>127,527</b> manual pages found in
   <b>1,663,033</b> files of <b>176,474</b> packages.
   <br /><br />
   Manned.org aims to index all manual pages from a variety of systems, both
   old and new, and provides a convenient interface for looking up and viewing
   the various versions of each man page. This site is still in its early life,
   so we're actively adding new systems to the database and finding ways to
   improve the online interface. <a href="/info/about">About manned.org &raquo;</a>
  _
  end;

  h2 'Browse the manuals';
  ul id => 'systems';
   my %sys;
   push @{$sys{$_->{name}}}, $_ for(@{$self->{systems}});
   for my $sys (sort keys %sys) {
     $sys = $sys{$sys};
     (my $img = $sys->[0]{short}) =~ s/^(.+)-.+$/$1/;
     li;
      a href => "/browse/$sys->[0]{short}" if @$sys == 1;
       span style => "background-image: url('images/$img.png')", '';
       b $sys->[0]{name};
       if(@$sys > 1) {
         my $i = 0;
         for(reverse @$sys) {
           a href => "/browse/$_->{short}", ++$i > 3 ? (class => 'hidden') : (), $_->{release};
           lit ' ';
         }
         a href => "#", class => 'more', 'more...' if $i > 3;
       }
      end 'a' if @$sys == 1;
     end;
   }
  end;

  h2 'Other sites';
  ul id => 'external';
   li; a href => 'http://man.cx/', 'Man.cx'; end;
   li; a href => 'http://man.he.net/', 'Man.he.net'; end;
   li; a href => 'http://linux.die.net/man/', 'Die.net'; end;
   li; a href => 'http://www.freebsd.org/cgi/man.cgi', 'FreeBSD.org Man Pages'; end;
   li; a href => 'http://www.openbsd.org/cgi-bin/man.cgi', 'OpenBSD Man Pages'; end;
   li; a href => 'http://linuxmanpages.net/', 'Fedora Manuals'; end;
   li; a href => 'http://manpages.ubuntu.com/', 'Ubuntu Manuals'; end;
   li; a href => 'http://www.manpagez.com/', 'Manpagez.com'; txt ' (Mac OS X, has some texinfo documentation as well)'; end;
   # li; a href => 'http://www.ma.utexas.edu/cgi-bin/man-cgi', 'ma.utexas.edu'; end; <- No idea what this has to offer when compared to the rest
  end;
  $self->htmlFooter;
}


sub about {
  my $self = shift;
  $self->htmlHeader(title => 'About');
  h1 'About Manned.org';

  h2 'Goal';
  p; lit <<'  _';
   The state of online indices of manual pages is a sad one. Existing sites
   only offer you a single version of a man page: From one origin, and often
   only in a single language. Most don't even tell you where the manual
   actually originated from, making it very hard to determine whether the
   manual you found actually applies to your situation and even harder to find
   a manual from a specific system. Additionally, some sites render the manuals
   in an unreadable way, don't correctly handle special formatting - like
   tables - or don't correctly display non-ASCII characters.
   <br /><br />
   Manned.org was created in order to improve this situation. This site aims to
   index the manual pages from a variaty of systems, both old and new, and
   allows you to browse through the various versions of a manual page to find
   out how each system behaves. The manuals are stored in the database as
   UTF-8, and are passed through <a
   href="http://www.gnu.org/software/groff/">groff</a> to render them in
   (mostly) the same way as they are displayed in your terminal.
  _
  end;

  h2 'The indexing process';
  p; lit <<'  _';
   All man pages are fetched right from the (binary) packages available on the
   public repositories of Linux distributions. In particular:<br />
   <br />
   <dl>
    <dt>Arch Linux</dt><dd>
     The core, extra and community repositories are fetched from a local
     Arch mirror. Indexing started around begin June 2012.</dd>
    <dt>Ubuntu</dt><dd>
     Historical releases were fetched from <a
     href="http://old-releases.ubuntu.com/ubuntu/">http://old-releases.ubuntu.com/ubuntu/</a>,
     supported releases from a local mirror.  All components (main, universe,
     restricted and multiverse) from the $release, $release-updates and
     $release-security repositories are indexed.  Backports are not included at
     the moment. Indexing started around mid June 2012.</dd>
    <dt>Debian</dt><dd>
     Historical releases were fetched from <a
     href="http://archive.debian.org/debian/">http://archive.debian.org/debian/</a>.
     For buzz, rex and bo, only the 'main' component has been indexed, and
     we're missing a few man pages because some packages were missing from the
     repository archives. For the other releases, all components (main, contrib
     and non-free) from the $release and $release-updates repositories are
     indexed.
    </dd>
   </dl><br />
   Only packages for a single architecture (i386 or i686) are scanned. To my
   knowledge, packages that come with different manuals for different
   architectures either don't exist or are extremely rare. It does happen that
   some packages are not available for all architectures.  Usually, though,
   every package is at least available for i386/i686, so hopefully we're not
   missing out on much.
   <br /><br />
   The repositories are scanned for new packages on a daily basis.
  _
  end;

  h2 'Other systems';
  p; lit <<'  _';
   I'd love to index the manuals of most major Linux distributions in the
   future. In the short term, this means all Fedora and OpenSUSE releases will
   get indexed. In the long term, many others may be added as well.
   <br /><br />
   It would also be great to index a few non-Linux systems such as *BSD,
   Solaris/Illumos and Mac OS X. Unfortunately, those don't always follow a
   binary package based approach, or are otherwise less easy to properly index.
   The FreeBSD ports look like a good future target, however.
   <br /><br />
   In general, systems that follow an entirely source-based distribution
   approach can't be indexed without compiling everything. Since that is both
   very resource-heavy and open to security issues, there are no plans to
   include manuals from such systems at the moment. So unless someone comes
   with a solution I hadn't thought of yet, there won't be any Gentoo manuals
   here. :-(
  _
  end;

  h2 'Copyright';
  p; lit <<'  _';
   All manual pages are copyrighted by their respective authors. The manuals
   have been fetched from publically available repositories of free and
   (primarily) open source software. The distributors of said software have put
   in efforts to only include software and documentation that allows free
   distribution. Nonetheless, if a manual that does not allow to be
   redistributed has been inadvertently included in our index, please let me
   know and I will have it removed as soon as possible.
  _
  end;
  $self->htmlFooter;
}


sub browsesys {
  my($self, $short) = @_;

  my $sys = $self->{sysbyshort}{$short};
  return $self->resNotFound if !$sys;

  my $f = $self->formValidate(
    { get => 'c', required => 0, enum => [ '0', 'all', 'a'..'z' ], default => 'all' },
    { get => 's', required => 0, regex => qr/^[a-zA-Z0-9_+.-]+$/i },
  );
  return $self->resNotFound if $f->{_err};

  my $pkg = $self->dbPackageList(
    hasman => 1,
    sysid => $sys->{id},
    char => $f->{c} eq 'all' ? undef : $f->{c},
    start => $f->{s},
    results => 201,
  );

  my $more = @$pkg > 200 && pop @$pkg;

  # TODO: A "previous" link would be nice...
  my $next = sub {
    use utf8;
    p class => 'pagination';
     a href => "/browse/$short?c=$f->{c};s=$pkg->[199]{name}", class => 'next', 'next »' if $more;
    end;
  };

  my $title = "Packages for $sys->{name}".($sys->{release}?" $sys->{release}":"");
  $self->htmlHeader(title => $title);
  h1 $title;

  p;
   for('all', 0, 'a'..'z') {
     a href => "/browse/$short?c=$_", $_?uc$_:'#' if $_ ne $f->{c};
     b $_?uc$_:'#' if $_ eq $f->{c};
   }
  end;

  p 'Note: Packages without man pages are not listed.';
  $next->();
  ul id => 'packages';
   for(@$pkg) {
     li;
      a href => "/browse/$short/$_->{name}", $_->{name};
      i $_->{category};
     end;
   }
  end;
  $next->();
  $self->htmlFooter;
}


sub browsepkg {
  my($self, $short, $name) = @_;

  my $sys = $self->{sysbyshort}{$short};
  return $self->resNotFound if !$sys;

  my $pkgs = $self->dbPackageGet($sys->{id}, $name);
  return $self->resNotFound if !@$pkgs;

  my $title = "$sys->{name}".($sys->{release}?" $sys->{release}":"")." / $name";
  $self->htmlHeader(title => $title);
  h1 $title;

  #TODO: Link back to the system browsing page
  #TODO: Have a menu/index listing the versions of this package? (With links to the anchors)
  #TODO: Collapse the man page list by default for older versions if the page becomes too long?

  for my $pkg (@$pkgs) {
    h2;
     a name => $pkg->{version}, href => "#$pkg->{version}", "$pkg->{category} / $pkg->{name} $pkg->{version} ($pkg->{released})";
    end;

    my $mans = $self->dbManInfo(package => $pkg->{id});
    # This can be a table as well.
    ul id => 'packages';
     # TODO: Put this sort in the SQL query
     for(sort { $a->{name} cmp $b->{name} || ($a->{locale}||'') cmp ($b->{locale}||'') } @$mans) {
       li;
        a href => "/$_->{name}/".substr($_->{hash},0,8), "$_->{name}($_->{section})";
        b " $_->{locale}" if $_->{locale};
        i " $_->{filename}";
       end;
     }
    end;
  }

  $self->htmlFooter;
}


# TODO: Store/cache the result of this of this function in the database.
sub manfmt {
  my $c = shift;

  # tix comes with[1] a custom(?) macro package. But it looks okay even without
  # loading that.
  # [1] It actually doesn't, the tcllib package appears to have that file, but
  # doesn't '.so' it.
  $c =~ s/^\.so man.macros$//mg;
  # Other .so's should be handled by the web interface
  $c =~ s/^\.so (.+)$/\[\[\[MANNEDINCLUDE $1\]\]\]/mg;

  # Disable hyphenation, since that screws up man page references. :-(
  $c = ".hy 0\n.de hy\n..\n$c";

  # Call grog to figure out which preprocessors to use.
  # $MANWIDTH works by using the following groff options: -rLL=100n -rLT=100n
  my($out, $in);
  my $pid = open2($out, $in, qw|grog -Tutf8 -P-c -DUTF-8 -|);
  binmode $in, ':utf8';
  print $in $c;
  close($in);
  chomp(my $grog = <$out>);
  waitpid $pid, 0;

  # Call groff
  $pid = open2($out, $in, split / /, $grog);
  $c = encode_utf8($c);
  my $ret;
  # Read/write the data in chunks to avoid a deadlock on large I/O
  while($c) {
    my @a = IO::Select::select(IO::Select->new($out), IO::Select->new($in), undef);
    die "IO::Select failed: $!\n" if !@a;
    if(@{$a[0]}) {
      my $b;
      my $r = sysread($out, $b, 4096);
      die "sysread failed: $!\n" if $r < 0;
      $ret .= $b if $r;
    }
    if(@{$a[1]}) {
      my $w = syswrite($in, $c, 4096);
      die "syswrite failed: $!\n" if $w <= 0;
      $c = substr($c, $w);
    }
  }
  close($in);
  local $/;
  $ret .= <$out>; # Now I'm mixing sysread and buffered read. I don't suppose that is an issue in this case, though.
  waitpid $pid, 0;

  $ret = decode_utf8($ret);
  $ret =~ s/[\t\s\r\n]+$//;
  return $ret;
}


sub manjslist {
  my($self, $m) = @_;

  # For JS: (Already sorted)
  # [
  #   ["System", "Full name", "short" [
  #       [ "package", "version", [
  #           [ "section", "locale"||null ],
  #           ...
  #         ],
  #       ],
  #       ...
  #     ],
  #   ],
  #   ...
  # ]
  my %sys;
  push @{$sys{$_->{system}}}, $_ for (@$m);
  [
    map [ $self->{sysbyid}{$_}{name}, $self->{sysbyid}{$_}{full}, $self->{sysbyid}{$_}{short},
      do {
        my %pkgs;
        for(@{$sys{$_}}) {
          my $pn = "$_->{package}-$_->{version}";
          $pkgs{$pn} = [ $_->{package}, $_->{version}, [], $_->{released} ] if !$pkgs{$pn};
          push @{$pkgs{$pn}[2]}, [ $_->{section}, $_->{locale}, substr $_->{hash}, 0, 8 ];
        }
        [ grep
          delete($_->[3]) && ($_->[2] = [sort { $a->[0] cmp $b->[0] || ($a->[1]||'') cmp ($b->[1]||'') } @{$_->[2]}]),
          sort { $a->[0] cmp $b->[0] || $b->[3] cmp $a->[3] } values %pkgs ];
      }
    ],
    sort { my $x=$self->{sysbyid}{$a}; my $y=$self->{sysbyid}{$b}; $x->{name} cmp $y->{name} or $y->{relorder} <=> $x->{relorder} } keys %sys
  ]
}


# Given the name and optionally the hash of a man page, check with a list of
# man pages with the same name to select the right one for display.
sub getman {
  my($self, $name, $hash, $list) = @_;

  my $sect = $name =~ /\.([0-9n])$/ ? $1 : undef;

  # If we already have a shorthash, just get the full hash
  if($hash) {
    $_->{hash} =~ /^$hash/ && return $_ for (@$list);
  }

  # If that failed, use some heuristics
  my $cmp = sub {
    local($a,$b) = @_;
    # English or non-locale packages always win
    !(($a->{locale}||'') =~ /^(en|$)/) != !(($b->{locale}||'') =~ /^(en|$)/)
      ? (($a->{locale}||'') =~ /^(en|$)/ ? -1 : 1)
    # Newer versions of a package have higher priority
    : $a->{system} == $b->{system} && $a->{package} eq $b->{package} && $a->{version} ne $b->{version}
      ? $b->{released} cmp $a->{released}
    # Section prefix match.
    : $sect && !($a->{section} =~ /^\Q$sect/) != !($b->{section} =~ /^\Q$sect/)
      ? ($a->{section} =~ /^\Q$sect/ ? -1 : 1)
    # Give lower priority to pages in a non-standard directory
    : !($a->{filename} =~ q{^/usr/share/man}) != !($b->{filename} =~ q{^/usr/share/man})
      ? ($a->{filename} =~ q{^/usr/share/man} ? -1 : 1)
    # Lower sections > higher sections (because 'man' does this as well)
    : substr($a->{section},0,1) ne substr($b->{section},0,1)
      ? $a->{section} cmp $b->{section}
    # Prefer Arch over other systems
    : $a->{system} != $b->{system}
      ? ($a->{system} == 1 ? -1 : 1)
    # Prefer a later system release over an older one
    : $a->{system} != $b->{system} && $self->{sysbyid}{$a->{system}}{name} eq $self->{sysbyid}{$b->{system}}{name}
      ? $self->{sysbyid}{$b->{system}}{relorder} <=> $self->{sysbyid}{$a->{system}}{relorder}
    # Sections without appendix before sections with appendix
    : $a->{section} ne $b->{section}
      ? $a->{section} cmp $b->{section}
    # Fallback to hash if nothing else matters (guarantees the order is at least stable)
    : $a->{hash} cmp $b->{hash};
  };

  my $winner = $list->[0];
  $cmp->($winner, $_) > 0 and ($winner = $_) for (@$list);
  return $winner;
}


sub man {
  my($self, $name, $hash) = @_;

  my $m = $self->dbManInfo(name => $name);
  return $self->resNotFound() if !@$m;
  my $man = getman($self, $name, $hash, $m);

  $self->htmlHeader(title => $name);
  div id => 'nav', ' '; # To be filled in by JS

  h1 $man->{name};
  p;
   a href => "/$man->{name}/".substr($man->{hash}, 0, 8), 'permalink';
   txt ' - ';
   a href => "/$man->{name}/".substr($man->{hash}, 0, 8).'/src', 'source';
  end;

  div id => 'contents';
   my $c = $self->dbManContent($man->{hash});
   pre; lit GrottyParser::html(manfmt $c); end;
  end;

  div id => 'locations';
   h2 'Locations of this man page';
   table;
    thead; Tr;
     td 'System';
     td 'Package';
     td 'Version';
     td 'Name';
     td 'Filename';
    end; end;
    my @l = sort {
         $self->{sysbyid}{$a->{system}}{name}     cmp $self->{sysbyid}{$b->{system}}{name}
      || $self->{sysbyid}{$b->{system}}{relorder} <=> $self->{sysbyid}{$a->{system}}{relorder}
      || $b->{released} cmp $a->{released}
      || $a->{filename} cmp $b->{filename}
    } @{$self->dbManInfo(hash => $man->{hash})};
    for(@l) {
      Tr;
       td $self->{sysbyid}{$_->{system}}{full};
       td "$_->{category}/$_->{package}";
       td $_->{version};
       td;
        a href => "/$_->{name}", $_->{name} if $_->{name} ne $man->{name};
        txt $_->{name} if $_->{name} eq $man->{name};
        txt ".$_->{section}";
       end;
       td $_->{filename};
      end;
    }
   end;
  end;

  $self->htmlFooter(js => { hash => substr($man->{hash}, 0, 8), name => $man->{name}, mans => manjslist($self, $m) });
}


sub src {
  my($self, $name, $hash) = @_;

  my $m = $self->dbManInfo(name => $name, shorthash => $hash);
  return $self->resNotFound if !@$m;

  $self->resHeader('Content-Type', 'text/plain; charset=UTF-8');
  my $c = $self->dbManContent($m->[0]{hash});
  lit $c;
}



package TUWF::Object;

use TUWF ':html', 'html_escape';

sub htmlHeader {
  my $self = shift;
  my %o = @_;

  html;
   head;
    Link rel => 'stylesheet', type => 'text/css', href => '/man.css';
    title $o{title}.' - manned.org';
   end 'head';
   body;

    div id => 'header';
     a href => '/', 'manned.org';
     form;
      input type => 'text', name => 'q';
      input type => 'submit', value => 'Search';
     end;
    end;

    div id => 'body';
}


sub htmlFooter {
  my($self, %o) = @_;

     br style => 'clear: both';
    end;
    div id => 'footer';
     lit 'All manual pages are copyrighted by their respective authors.
       | <a href="/info/about">About manned.org</a> | <a href="mailto:contact@manned.org">Contact</a>';
    end;
    if($o{js}) {
      script type => 'text/javascript';
       lit 'VARS = ';
       lit(JSON::XS->new->ascii->encode($o{js}));
       lit ';';
      end;
    }
    script type => 'text/javascript', src => '/man.js', '';
   end;
  end 'html';

  # write the SQL queries as a HTML comment when debugging is enabled
  # (stolen from VNDB code)
  if($self->debug) {
    lit "\n<!--\n SQL Queries:\n";
    for (@{$self->{_TUWF}{DB}{queries}}) {
      my $q = !ref $_->[0] ? $_->[0] :
        $_->[0][0].(exists $_->[0][1] ? ' | "'.join('", "', map defined()?$_:'NULL', @{$_->[0]}[1..$#{$_->[0]}]).'"' : '');
      $q =~ s/^\s//g;
      lit sprintf "  [%6.2fms] %s\n", $_->[1]*1000, $q;
    }
    lit "-->\n";
  }
}


sub dbManContent {
  my($s, $hash) = @_;
  return $s->dbRow(q{SELECT content FROM contents WHERE hash = decode(?, 'hex')}, $hash)->{content};
}


# Options: name, section, shorthash, locale, package
sub dbManInfo {
  my $s = shift;
  my %o = @_;

  (my $oname = $o{name}||'') =~ s/\.([0-9n])$//;
  my %where = (
    $o{name}      ? ('m.name IN(!l)' => [[ $o{name}, $oname ne $o{name} ? $oname : () ]]) : (),
    $o{package}   ? ('m.package = ?' => $o{package}) : (),
    $o{section}   ? ('m.section = ?' => $o{section}) : (),
    $o{shorthash} ? (q{substring(m.hash from 1 for 4) = decode(?, 'hex')} => $o{shorthash}) : (),
    $o{hash}      ? (q{m.hash = decode(?, 'hex')} => $o{hash}) : (),
    $o{locale}    ? ('m.locale = ?', $o{locale}) : exists $o{locale} ? ('m.locale IS NULL' => 1) : (),
  );

  # TODO: Flags to indicate what to information to fetch
  return $s->dbAll(q{
    SELECT p.system, p.category, p.name AS package, p.version, p.released, m.name, m.section, m.filename, m.locale, encode(m.hash, 'hex') AS hash
      FROM package p
      JOIN man m ON m.package = p.id
        !W
  }, \%where);
}


sub dbSystemGet {
  return shift->dbAll('SELECT id, name, release, short, relorder FROM systems ORDER BY name, relorder');
}


# TODO: Optimize
# Options: sysid char hasman start results
sub dbPackageList {
  my $s = shift;
  my %o = (results => 10, @_);

  my @where = (
    $o{sysid} ? ('system = ?' => $o{sysid}) : (),
    $o{start} ? ('name > ?' => $o{start}) : (),
    defined($o{hasman}) ? ('!s EXISTS(SELECT 1 FROM man m WHERE m.package = p.id)' => $o{hasman}?'':'NOT') : (),
    $o{char} ? ( 'LOWER(SUBSTR(name, 1, 1)) = ?' => $o{char} ) : (),
    defined($o{char}) && !$o{char} ? ( '(ASCII(name) < 97 OR ASCII(name) > 122) AND (ASCII(name) < 65 OR ASCII(name) > 90)' => 1 ) : (),
    # Only get the latest version
    # TODO: This is more efficient than using, e.g. SELECT DISTINCT to achieve
    # the same effect. The downside of this solution is that packages of which
    # the latest release does not include man pages are not listed, even if an
    # earlier version does have mans.
    'NOT EXISTS(SELECT 1 FROM package p2 WHERE p2.system = p.system AND p2.name = p.name AND p2.released > p.released)'
  );

  return $s->dbAll(q{
      SELECT name, category
        FROM package p
          !W
    ORDER BY name
       LIMIT ?},
  \@where, $o{results})
}


# TODO: Optimize?
sub dbPackageGet {
  my($s, $sysid, $name) = @_;

  return $s->dbAll(q{
      SELECT id, category, name, version, released
        FROM package p
       WHERE system = ?
         AND name = ?
         AND EXISTS(SELECT 1 FROM man m WHERE m.package = p.id)
    ORDER BY released DESC},
  $sysid, $name)
}

