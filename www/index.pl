#!/usr/bin/perl

use strict;
use warnings;
use TUWF ':html', 'html_escape', ':xml';
use JSON::XS;
use POSIX 'ceil';

use Cwd 'abs_path';
our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/www/index\.pl$}{}; }


use lib "$ROOT/lib/ManUtils/inst/lib/perl5";
use ManUtils;


TUWF::set(
  logfile => $ENV{TUWF_LOG},
  db_login => [undef, undef, undef],
  debug => 0,
  xml_pretty => 0,
  log_slow_pages => 500,
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
  error_404_handler => sub {
    my $self = shift;
    $self->resStatus(404);
    my $title = 'No manual entry for '.$self->reqPath;
    $self->htmlHeader(title => $title);
    h1 $title;
    p 'That is, the page you were looking for doesn\'t exist.';
    $self->htmlFooter;
  },
);


TUWF::register(
  qr// => \&home,
  qr{info/about} => \&about,
  qr{browse/search} => \&browsesearch,

  # These have to go before the other mappings, to ensure that links work for
  # man pages called 'pkg' or 'man'. This also means that we can't have a
  # system named 8 hex digits, but at least that's easy to guarantee. :)
  qr{([^/]+)/([0-9a-f]{8})} => \&man,
  qr{([^/]+)/([0-9a-f]{8})/src} => \&src,
  # We don't have any other single-component paths
  qr{([^/]+)} => \&man,

  qr{pkg/([^/]+)} => \&pkg_list,
  # pkg/$system/$category/$name (/$version); $category may contain a slash, too.
  qr{pkg/([^/]+)/(.+)} => \&pkg_info,

  # Redirects for canonical URLs
  qr{man/([^/]+)/(.+)} => \&man_redir,

  # Redirects for old URLs.
  # /browse/<pkg> has been moved to /pkg/ with the package category added to the path
  qr{browse/([^/]+)} => sub { $_[0]->resRedirect("/pkg/$_[1]", 'perm'); },
  qr{browse/([^/]+)/([^/]+)(?:/([^/]+))?} => sub {
    my($self, $sys, $name, $ver) = @_;
    $sys = $self->{sysbyshort}{$sys};
    return $self->resNotFound if !$sys;
    my $pkgs = $self->dbPackageGet(sysid => $sys->{id}, name => $name, results => 1);
    return $self->resNotFound if !@$pkgs;
    $self->resRedirect("/pkg/$sys->{short}/$pkgs->[0]{category}/$name".($ver ? "/$ver" :''), 'perm');
  },

  # Redirect for a specific language for a man page.
  # I'm not a fan of this solution; might drop it in the future.
  qr{lang/([^/]+)/([^/]+)} => sub {
    my($s, $l, $n) = @_;
    $n = _normalizename($n);
    my($m, undef) = $s->dbManPrefName($n, language => $l);
    return $s->resNotFound if !$m;
    $s->resRedirect("/$m->{name}/".substr($m->{hash}, 0, 8), 'temp');
  },

  qr{xml/search\.xml} => \&xmlsearch,
  qr{json/tree\.json} => \&jsontree,
);

TUWF::run();


sub home {
  my $self = shift;
  my $stats = $self->dbStats;
  my $fn = sub { local $_=shift; 1 while(s/(\d)(\d{3})($|,)/$1,$2/); $_ };
  $self->htmlHeader(title => 'Man Pages Archive');
  h1 'Man Pages Archive';
  p class => 'txt'; lit sprintf <<'  _', map $fn->($stats->{$_}), qw|hashes mans files packages|;
   Indexing <b>%s</b> versions of <b>%s</b> manual pages found in <b>%s</b>
   files of <b>%s</b> packages.
   <br /><br />
   Manned.org aims to index all manual pages from a variety of systems, both
   old and new, and provides a convenient interface for looking up and viewing
   the various versions of each man page.
   <a href="/info/about">About manned.org &raquo;</a>
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
      a href => "/pkg/$sys->[0]{short}" if @$sys == 1;
       span style => "background-image: url('images/$img.png')", '';
       b $sys->[0]{name};
       if(@$sys > 1) {
         my $i = 0;
         for(reverse @$sys) {
           a href => "/pkg/$_->{short}", ++$i > 3 ? (class => 'hidden') : (), $_->{release};
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
   li; a href => 'http://man7.org/linux/man-pages/index.html', 'man7.org'; txt ' - Linux man pages from several upstream projects.'; end;
   li; a href => 'http://manpag.es/', 'ManPag.es'; txt ' - Man pages from several Linux distributions.'; end;
   li; a href => 'http://man.cx/', 'man.cx'; txt ' - Man pages extracted from Debian testing.'; end;
   li; a href => 'http://man.he.net/', 'man.he.net'; txt ' - Also seems to be from a Debian-like system.'; end;
   li; a href => 'http://linux.die.net/man/', 'die.net'; txt ' - Seems to be based on an RPM-based Linux distribution.'; end;
   li; a href => 'http://manpages.org/', 'manpages.org'; txt ' - Lots of mostly-nicely formatted man pages, no clue about source.'; end;
   li; a href => 'http://www.manpagez.com/', 'manpagez.com'; txt ' - Mac OS X, has some GTK-html and texinfo documentation as well.'; end;
   li; a href => 'https://jlk.fjfi.cvut.cz/arch/manpages/dev', 'Arch Linux Man Pages'; end;
   li; a href => 'https://manpages.debian.org/', 'Debian Man Pages'; end;
   li; a href => 'https://www.dragonflybsd.org/cgi/web-man', 'DragonFlyBSD Man Pages'; end;
   li; a href => 'http://www.freebsd.org/cgi/man.cgi', 'FreeBSD.org Man Pages'; end;
   li; a href => 'http://netbsd.gw.com/cgi-bin/man-cgi', 'NetBSD Man Pages'; end;
   li; a href => 'http://www.openbsd.org/cgi-bin/man.cgi', 'OpenBSD Man Pages'; end;
   li; a href => 'http://manpages.ubuntu.com/', 'Ubuntu Manuals'; end;
   li; a href => 'https://man.voidlinux.eu/', 'Void Linux manpages'; end;
  end;
  $self->htmlFooter;
}


sub about {
  my $self = shift;
  $self->htmlHeader(title => 'About');
  h1 'About Manned.org';
  div id => 'about';

  h2 'Goal';
  p; lit <<'  _';
   The state of online indices of manual pages used to be a sad one. Existing
   sites used to only offer you a single version of a man page: From one
   origin, and often only in a single language. Most didn't even tell you where
   the manual actually originated from, making it very hard to determine
   whether the manual you found actually applied to your situation and even
   harder to find a manual for a specific system. Additionally, some sites
   rendered the manuals in an unreadable way, didn't correctly handle special
   formatting - like tables - or didn't correctly display non-ASCII characters.
   <br /><br />
   Nowadays there are many good alternatives, but Manned.org was one of the
   sites created in order to improve situation. This site aims to index the
   manual pages from a variaty of systems, both old and new, and allows you to
   browse through the various versions of a manual page to find out how each
   system behaves. The manuals are stored in the database as UTF-8, and are
   passed through <a href="http://www.gnu.org/software/groff/">groff</a> to
   render them in (mostly) the same way as they are displayed in your terminal.
   <br /><br />
   This website is <a href="https://g.blicky.net/manned.git/">open source</a>
   (MIT licensed) and written in a combination of Perl and Rust. The entire
   PostgreSQL database is available for download (see "Database download"
   below).
  _
  end;

  h2 'URL format';
  lit <<'  _';
   <p>You can link to specific packages and man pages with several URL formats.
   These URLs will keep working in the future, so you should not have to worry
   about eventual dead links.</p>
   <h3>Man pages</h3>
   <p>The following URLs are available to refer to an individual man page:</p>
   <dl>
    <dt><code>/&lt;name>/&lt;8-hex-digits></code></dt><dd>
     This is the permalink format for a specific man page (e.g. <a href="/ls/910be0ed">/ls/910be0ed</a>).</dd>
    <dt><code>/&lt;name>[.&lt;section>]</code></dt><dd>
     Will try to get the latest and most-close-to-upstream version of a man
     page (e.g. <a href="/socket">/socket</a> or <a
     href="/socket.7">/socket.7</a>). Note that this may fetch the man page
     from any available system, so may result in confusing scenarios for
     system-specific documentation.</dd>
    <dt><code>/man/&lt;system>/&lt;name>[.&lt;section>]</code></dt><dd>
     Will get the latest version of a man page from the given system (e.g. <a
     href="/man/ubuntu-xenial/rsync">/man/ubuntu-xenial/rsync</a>)</dd>
    <dt><code>/man/&lt;system>/&lt;category>/&lt;package>/&lt;name>[.&lt;section>]</code></dt><dd>
     Will get the latest version of a man page from the given package (e.g. <a
     href="/man/ubuntu-xenial/net/rsync/rsync">/man/ubuntu-xenial/net/rsync/rsync</a>)</dd>
    <dt><code>/man/&lt;system>/&lt;category>/&lt;package>/&lt;version>/&lt;name>[.&lt;section>]</code></dt><dd>
     Will get the man page from a specific package version (e.g. <a
     href="/man/ubuntu-xenial/net/rsync/3.1.1-3ubuntu1/rsync">/man/ubuntu-xenial/net/rsync/3.1.1-3ubuntu1/rsync</a>)</dd>
   </dl>
   <p>Currently, the last three URLs will perform a redirect to the
   appropriate permalink URL, but this may change in the future.<br />
   In all URLs where an optional <code>.&lt;section></code> can be provided,
   the search is performed as a prefix match. For example, <a
   href="/cat.3">/cat.3</a> will provide the <code>cat.3tcl</code> man page if
   no exact <code>cat.3</code> version is available. Linking to the full
   section name is also possible: <a href="/cat.3tcl">/cat.3tcl</a>. If no
   section is given and multiple sections are available, the lowest section
   number is chosen.</p>
   <h3>Packages</h3>
   <p>Linking to individual packages is also possible. These pages will show a
   listing of all manual pages available in the given package.</p>
   <dl>
    <dt><code>/pkg/&lt;system>/&lt;category>/&lt;package></code></dt><dd>
     For the latest version of a package (e.g. <a
     href="/pkg/arch/core/coreutils">/pkg/arch/core/coreutils</a>).</dd>
    <dt><code>/pkg/&lt;system>/&lt;category>/&lt;package>/&lt;version></code></dt><dd>
     For a particular version of a package (e.g. <a
     href="/pkg/arch/core/coreutils/8.25-2">/pkg/arch/core/coreutils/8.25-2</a>).</dd>
   </dl>
   <p>Note that this site only indexes packages that actually have manual
   pages; Linking to a package that doesn't have any will result in a 404
   page.</p>
  _

  h2 'The indexing process';
  p; lit <<'  _';
   All man pages are fetched right from the (binary) packages available on the
   public repositories of Linux distributions. In particular:<br />
   <dl>
    <dt>Arch Linux</dt><dd>
     The core, extra and community repositories are fetched from a local
     Arch mirror. Indexing started around begin June 2012. The i686
     architecture was indexed until November 6th, 2016, packages after that
     were fetched from from x86_64.</dd>
    <dt>Debian</dt><dd>
     Historical releases were fetched from <a
     href="http://archive.debian.org/debian/">http://archive.debian.org/debian/</a>
     and <a href="http://snapshot.debian.org/">http://snapshot.debian.org/</a>.
     For buzz, rex and bo, we're missing a few man pages because some packages
     were missing from the repository archives. Where available, all components
     (main, contrib and non-free) from the $release and $release-updates
     repositories are indexed.</dd>
    <dt>CentOS</dt><dd>
     Historical releases were fetched from <a
     href="http://vault.centos.org/">vault.centos.org</a>, current releases
     from a local mirror. Where applicable, the following repositories were
     indexed: addons, centosplus, contrib, extras, os. The i386 architecture
     was indexed for versions lower than 7.0, since 7.0 the packages from
     x86_64 are indexed.
    <dt>Fedora</dt><dd>
     Historical releases were fetched from <a
     href="http://archives.fedoraproject.org/pub/archive/fedora/linux/">archives.fedoraproject.org</a>,
     current releases from a local repository. Fedora Core 1 till 6 are
     (incorrectly) called 'Fedora' here. To compensate for that, Fedora 3 till
     6 also include the Extras repository. For Fedora 7 and later, the
     'Everything' and 'updates' repositories are indexed. The i386 arch was
     indexed for Fedora 17 and older, the x86_64 arch starting with Fedora
     18.</dd>
    <dt>FreeBSD</dt><dd>
     Historical releases were fetched from <a
     href="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/">http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/</a>.
     The base installation tarballs are included in the database as packages
     prefixed with <i>core-</i>. The package repositories have also been
     indexed, except for 2.0.5 - 2.2.7 and 3.0 - 3.3 because those were not
     available on the ftp archive. Only the -RELEASE repositories have been
     included, which is generally a snapshot of the ports directory around the
     time of the release. The release dates indicated for many packages were
     guessed from the file modification dates in the tarball, and may be
     inaccurate. The i368 arch was indexed for FreeBSD 11.0 and older, the
     amd64 arch starting with 11.1.</dd>
    <dt>Ubuntu</dt><dd>
     Historical releases were fetched from <a
     href="http://old-releases.ubuntu.com/ubuntu/">http://old-releases.ubuntu.com/ubuntu/</a>,
     supported releases from a local mirror.  All components (main, universe,
     restricted and multiverse) from the $release, $release-updates and
     $release-security repositories are indexed. Indexing started around mid
     June 2012. All releases before 2017 were indexed from the i386
     repositories, starting with 17.04 the amd64 repositories were used.</dd>
   </dl>
   <p>
   Only packages for a single architecture (i386 or amd64) are scanned.  To my
   knowledge, packages that come with different manuals for different
   architectures either don't exist or are extremely rare. It does happen that
   some packages are not available for all architectures.  Usually, though,
   every package is at least available for the most popular architecture, so
   hopefully we're not missing out on much.  <br /><br />
   The repositories are scanned for new packages on a daily basis.
   </p>
  _
  end;

  h2 'Database download';
  p; lit <<'  _';
   This site is backed by a PostgreSQL database containing all the man pages.
   Weekly dumps of the full database are available for download at
   <a href="http://dl.manned.org/dumps/">http://dl.manned.org/dumps/</a>.
   <br /><br />
   Be warned that the download server may not be terribly reliable, so it is
   advisable to use a client that supports resumption of partial downloads. See
   <a href="/wget">wget's -c</a> or <a href="/curl">curl's -C</a>.
   <br /><br />
   The database schema is "documented" at <a
   href="https://g.blicky.net/manned.git/tree/sql/schema.sql">schema.sql</a> in
   the git repo. Note that these dumps don't constitute a stable API and, while
   this won't happen frequently, incompatible schema changes or Postgres major
   version bumps may occur.
  _
  end;

  h2 'Other systems';
  p; lit <<'  _';
   Suggestions for new (or old) systems to index are welcome.
   <br /><br />
   It would be great to index a few more non-Linux systems such as other BSDs,
   Solaris/Illumos and Mac OS X. Unfortunately, those don't always follow a
   binary package based approach, or are otherwise less easy to properly index.
   <br /><br />
   In general, systems that follow an entirely source-based distribution
   approach can't be indexed without compiling everything. Since that is both
   very resource-heavy and open to security issues, there are no plans to
   include manuals from such systems at the moment. So unless someone comes
   with a solution I hadn't thought of yet, there won't be any Gentoo manuals
   here. :-(
  _
  end;

  h2 'Future plans';
  p; lit <<'  _';
   This site isn't nearly as awesome yet as it could be. Here's some ideas that
   would be nice to have in the future:
   <ul>
    <li>Improved, more intelligent, search,</li>
    <li><a href="/apropos.1">apropos(1)</a> emulation(?),</li>
    <li>Diffs between various versions of a man page,</li>
    <li>Anchor links within man pages, for easier linking to a section or paragraph,</li>
    <li>Alternative formats (Text, PDF, more semantic HTML, etc),</li>
    <li>A command-line client, like <a href="/man.1">man(1)</a> with manned.org as database backend.</li>
   </ul>
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

  end;
  $self->htmlFooter;
}


sub paginate {
  my($url, $count, $perpage, $p) = @_;
  return if $count <= $perpage;

  my $l = sub {
    my $c = shift;
    a href => sprintf('%s%d', $url, $c), $c if $c != $p;
    b $c if $c == $p;
  };

  my $lp = ceil($count/$perpage);
  p class => 'paginate';
   $l->(1) if $p > 1+4;
   b '...' if $p > 1+5;
   $l->($_) for (($p > 4 ? $p-4 : 1)..($p+4 > $lp ? $lp : $p+4));
   b '...' if $p < $lp-5;
   $l->($lp) if $p < $lp-4;
  end;
}


sub browsesearch {
  my $self = shift;
  my $q = $self->reqGet('q')||'';
  my $man = $self->dbSearch($q, 150);

  return $self->resRedirect("/$man->[0]{name}.$man->[0]{section}", 'temp') if @$man == 1;

  $self->htmlHeader(title => 'Search results for '.$q);
  h1 'Search results for '.$q;
  p 'Note: This is just a simple case-insensitive prefix match on the man names. In the future we\'ll have more powerful search functionality. Hopefully.';
  if(@$man) {
    ul id => 'searchres';
     for(@$man) {
       li;
        a href => "/$_->{name}.$_->{section}", $_->{name};
        i " $_->{section}";
       end;
     }
    end;
  } else {
    br; br;
    b 'No results :-(';
  }

  $self->htmlFooter;
}


sub pkg_list {
  my($self, $short) = @_;

  my $sys = $self->{sysbyshort}{$short};
  return $self->resNotFound if !$sys;

  my $f = $self->formValidate(
    { get => 'c', required => 0, enum => [ '0', 'all', 'a'..'z' ], default => 'all' },
    { get => 'p', required => 0, default => 1, template => 'uint', min => 1, max => 200 },
  );
  return $self->resNotFound if $f->{_err};

  my %opt = (hasman => 1, sysid => $sys->{id}, char => $f->{c} eq 'all' ? undef : $f->{c});
  my $pkg = $self->dbPackageGet(%opt, results => 200, page => $f->{p});
  my $count = $self->dbPackageGet(%opt, countonly => 1)->[0]{count};

  my $title = "Packages for $sys->{name}".($sys->{release}?" $sys->{release}":"");
  $self->htmlHeader(title => $title);
  div id => 'pkglist';
   h1 $title;

   p class => 'charselect';
    for('all', 0, 'a'..'z') {
      a href => "/pkg/$short?c=$_", $_?uc$_:'#' if $_ ne $f->{c};
      b $_?uc$_:'#' if $_ eq $f->{c};
    }
   end;

   p 'Note: Packages without man pages are not listed.';
   paginate "/pkg/$short?c=$f->{c};p=", $count, 200, $f->{p};
   ul id => 'packages';
    for(@$pkg) {
      li;
       a href => "/pkg/$short/$_->{category}/$_->{name}", $_->{name};
       i ' '.$_->{category};
      end;
    }
   end;
   paginate "/pkg/$short?c=$f->{c};p=", $count, 200, $f->{p};

  end;
  $self->htmlFooter;
}


sub pkg_frompath {
  my($self, $sys, $path) = @_;

  # $path should be "$category/$name" or "$category/$name/$version", since
  # $category may contain a slash, let's try both options.

  # $category/$name
  # e.g. contrib/games/alien
  if($path =~ m{^(.+)/([^/]+)$}) {
    my($category, $name) = ($1, $2);
    my $pkg = $self->dbPackageGet(sysid => $sys, category => $category, name => $name, hasman => 1)->[0];
    return ($pkg, '') if $pkg;
  }

  # $category/$name/$version
  # e.g. contrib/games/alien/10.2
  if($path =~ m{^(.+)/([^/]+)/([^/]+)$}) {
    my($category, $name, $version) = ($1, $2, $3);
    my $pkg = $self->dbPackageGet(sysid => $sys, category => $category, name => $name, hasman => 1)->[0];
    return ($pkg, $version) if $pkg;
  }

  (undef, '');
}


sub pkg_info {
  my($self, $short, $path) = @_;

  my $sys = $self->{sysbyshort}{$short};
  return $self->resNotFound if !$sys;

  my($pkg, $ver) = pkg_frompath($self, $sys->{id}, $path);
  return $self->resNotFound if !$pkg;

  my $vers = $self->dbPackageVersions($pkg->{id});

  my $sel = $ver ? (grep $_->{version} eq $ver, @$vers)[0] : $vers->[0];
  return $self->resNotFound if !$sel;

  my $f = $self->formValidate({ get => 'p', required => 0, default => 1, template => 'uint', min => 1, max => 100});
  return $self->resNotFound if $f->{_err};

  my $mans = $self->dbManInfo(package => $sel->{id}, results => 200, page => $f->{p}, sort => 'syspkgname');
  my $count = $self->dbManInfo(package => $sel->{id}, countonly => 1)->[0]{count};

  # Latest version of this package determines last modification date of the page.
  $self->setLastMod($vers->[0]{released});

  my $title = "$sys->{name}".($sys->{release}?" $sys->{release}":"")." / $pkg->{category} / $pkg->{name}";
  $self->htmlHeader(title => "$title $sel->{version}");
  h1 $title;

  div id => 'pkgversions';
   h2 'Versions';
   ul;
    for(@$vers) {
      li;
       a href => "/pkg/$sys->{short}/$pkg->{category}/$pkg->{name}/$_->{version}", $_->{version} if $_ != $sel;
       b " $_->{version}" if $_ == $sel;
       i " $_->{released}";
      end;
    }
   end;
  end;

  div id => 'pkgmans';
  h2 "Manuals for version $sel->{version}";
   paginate "/pkg/$sys->{short}/$pkg->{category}/$pkg->{name}/$sel->{version}?p=", $count, 200, $f->{p};
   ul;
    for(@$mans) {
      li;
       a href => "/$_->{name}/".substr($_->{hash},0,8), "$_->{name}($_->{section})";
       b " $_->{locale}" if $_->{locale};
       i " $_->{filename}";
      end;
    }
   end;
   paginate "/pkg/$sys->{short}/$pkg->{category}/$pkg->{name}/$sel->{version}?p=", $count, 200, $f->{p};
  end;

  $self->htmlFooter;
}


sub man_redir {
  my($self, $sys, $path) = @_;

  # Path can be:
  # 1. <name>
  # 2. <category>/<package>/<name>
  # 3. <category>/<package>/<version>/<name>

  $sys = $self->{sysbyshort}{$sys};
  return $self->resNotFound if !$sys;

  my $man;
  if($path !~ m{/}) { # (1)
    ($man) = $self->dbManPrefName($path, sysid => $sys->{id});

  } else {
    $path =~ s{/([^/]+)$}{};
    my $name = $1;

    my($pkg, $ver) = pkg_frompath($self, $sys->{id}, $path); # Handles (2) and (3)
    return $self->resNotFound if !$pkg;

    my $verid = $ver && $self->dbPackageVersions($pkg->{id}, $ver)->[0]{id};
    return $self->resNotFound if $ver && !$verid;

    ($man) = $self->dbManPrefName($name, sysid => $sys->{id}, pkgid => $pkg->{id}, pkgver => $verid);
  }
  return $self->resNotFound if !$man;

  $self->resRedirect("/$man->{name}/".substr($man->{hash}, 0, 8), 'temp');
};


sub _man_nav {
  my($self, $man, $toc) = @_;

  my @sect = $self->dbManSections($man->{name});
  my @lang = $self->dbManLanguages($man->{name}, $man->{section});
  return if !@sect && !@lang && !@$toc;

  # TODO: This is ugly, especially because clicking on a translation or
  # section, you can end up with a man page that is nowhere close to the man
  # page you're currently reading. Opening a version selector box might be a
  # better alternative.

  div id => 'nav';

   if(@sect > 1) {
     b 'Sections';
     p;
      for (@sect) {
        if($man->{section} eq $_) {
          i $_;
        } else {
          a href => "/$man->{name}.$_", $_;
        }
        txt ' ';
      }
     end;
   }

   if(@lang > 1) {
     b 'Languages';
     p;
      (my $cur = $man->{locale}||'') =~ s/\..*//;
      for (@lang) {
        if(($_||'') eq $cur) {
          i $_ || 'default';
        } else {
          a href => $_ ? "/lang/$_/$man->{name}.$man->{section}" : "/$man->{name}.$man->{section}", $_ || 'default';
        }
        txt ' ';
      }
     end;
   }

   if(@$toc > 1) {
     b 'Table of Contents';
     ul;
      for (0..$#$toc) {
        li;
         a href => sprintf('#head%d', $_+1), lc $toc->[$_];
        end;
      }
     end;
   }
  end;
}


sub _normalizename {
  local $_ = shift;
  # Firefox seems to escape [ and ] in URLs. It doesn't really have to...
  s/%5b/[/ig;
  s/%5d/]/ig;
  # Man pages with spaces in the path, eww
  s/%20/ /g;
  $_;
}


# Replace .so's in man source with the contents (if available in the same
# package) or with a reference to the other man page.
sub soelim {
  my($self, $verid, $src) = @_;

  # tix comes with[1] a custom(?) macro package. But it looks okay even without
  # loading that.
  # [1] It actually doesn't, the tcllib package appears to have that file, but
  # doesn't '.so' it.
  $src =~ s/^\.so man.macros$//mg;

  # Other .so's should be handled by html()
  $src =~ s{^\.so (.+)$}{
    my $path = $1;
    my $name = (reverse split /\//, $path)[0];
    my($man) = $verid ? $self->dbManPrefName($name, pkgver => $verid) : ();
    if($man) {
      # Recursive soelim, but the second call gets $verid=0 so we don't keep checking the database
      soelim($self, 0, $self->dbManContent($man->{hash}))
    } else {
      ".in -10\n.sp\n\[\[\[MANNEDINCLUDE$path\]\]\]"
    }
  }emg;
  return $src;
}


sub man {
  my($self, $name, $hash) = @_;

  $name = _normalizename($name);

  # Unfortunately, even in the permalink format with the hash, we don't know
  # from which package we're supposed to get the man page. This info is
  # needed in order to do .so substitution, so we can substitute files from
  # the same package as the requested man page. Use the dbManPref logic here
  # to deterministically select a good package.
  my($man, undef) = $hash
    ? $self->dbManPref(name => $name, shorthash => $hash)
    : $self->dbManPrefName($name);
  return $self->resNotFound() if !$man;

  my $fmt = ManUtils::html(ManUtils::fmt_block soelim $self, $man->{verid}, $self->dbManContent($man->{hash}));
  my @toc;
  $fmt =~ s{\n<b>(.+?)<\/b>\n}{
    push @toc, $1;
    my $c = @toc;
    qq{\n<a href="#head$c" id="head$c">$1</a>\n}
  }eg;

  $self->setLastMod($man->{released});
  $self->htmlHeader(title => $name);
  _man_nav($self, $man, \@toc);
  div id => 'manbuttons';
   h1 $man->{name};
   ul 'data-hash' => $man->{hash}, 'data-name' => $man->{name}, 'data-section' => $man->{section}, 'data-locale' => $man->{locale}||'',
      'data-hasversions' => $self->dbManHasVersions($man->{name}, $man->{section}, $man->{locale}, $man->{hash});
    li; a href => "/$man->{name}/".substr($man->{hash}, 0, 8).'/src', 'source'; end;
    li; a href => "/$man->{name}/".substr($man->{hash}, 0, 8), 'permalink'; end;
   end;
  end;
  div id => 'manres', class => 'hidden';
  end;

  div id => 'contents';
   pre; lit $fmt; end;
  end;
  $self->htmlFooter();
}


sub src {
  my($self, $name, $hash) = @_;

  $name = _normalizename($name);

  my $m = $self->dbManInfo(name => $name, shorthash => $hash);
  return $self->resNotFound if !@$m;

  $self->setLastMod($m->[0]{released});
  $self->resHeader('Content-Type', 'text/plain; charset=UTF-8');
  $self->resHeader('Content-Disposition', sprintf 'filename="%s.%s"', $m->[0]{name}, $m->[0]{section});
  my $c = $self->dbManContent($m->[0]{hash});
  lit $c;
}


sub xmlsearch {
  my $self = shift;
  my $q = $self->reqGet('q')||'';
  my $man = $self->dbSearch($q, 20);

  # The JS dropdown search expects this particular format.
  $self->resHeader('Content-Type' => 'text/xml; charset=UTF-8');
  xml;
  tag 'results';
   tag 'item', id => "$_->{name}.$_->{section}", %$_, undef for(@$man);
  end 'results';
}


sub jsontree {
  my $self = shift;

  my $f = $self->formValidate(
    { get => 'name', required => 0, maxlength => 256 },
    { get => 'section', required => 0, maxlength => 32 },
    { get => 'locale', required => 0, default => '', maxlength => 32 },
    { get => 'cur', required => 0, default => '', regex => qr/^[a-fA-F0-9]{40}$/ },
    { get => 'hash', required => 0, default => '', regex => qr/^[a-fA-F0-9]{40}$/ },
  );
  return $self->resNotFound() if $f->{_err} || (!$f->{hash} && !($f->{section} && $f->{name}));

  my $l = $self->dbManInfo(sort => 'syspkgname', $f->{hash}
    ? (hash => $f->{hash})
    : (name => $f->{name}, section => $f->{section}, locale => $f->{locale}));

  # Convert the list into a tree
  my $tree = [];
  my($sys, $sysver, $pkg, $pkgver);
  for my $m (@$l) {
    my $sysname = $self->{sysbyid}{$m->{system}}{name};
    if(!$sys || $sysname ne $sys->{name}) {
      $sys = { name => $sysname, childs => [] };
      $sysver = undef;
      push @$tree, $sys;
    }

    my $sysversion = $self->{sysbyid}{$m->{system}}{release} || '';
    if(!$sysver || $sysversion ne $sysver->{name}) {
      $sysver = { name => $sysversion, childs => [] };
      $pkg = undef;
      push @{$sys->{childs}}, $sysver;
    }

    if(!$pkg || $m->{package} ne $pkg->{name}) {
      $pkg = { name => $m->{package}, i => $m->{category}, table => [] };
      $pkgver = undef;
      push @{$sysver->{childs}}, $pkg;
    }

    push @{$pkg->{table}}, [
      $pkgver && $pkgver eq $m->{version} ? {name=>''} :
        {name => $m->{version}, href => "/pkg/$self->{sysbyid}{$m->{system}}{short}/$m->{category}/$m->{package}/$m->{version}"},
      { name => "$m->{name}($m->{section})",
        $f->{hash} || lc($m->{hash}) eq lc($f->{cur}) ? ()
        : (href => sprintf('/%s/%s', $m->{name}, substr $m->{hash}, 0, 8))
      },
      { name => substr($m->{hash}, 0, 8),
        $f->{hash} || lc($m->{hash}) eq lc($f->{cur}) ? ()
        : (href => sprintf('/%s/%s', $m->{name}, substr $m->{hash}, 0, 8))
      },
      { name => $m->{filename} }
    ];
    $pkgver = $m->{version};
  }

  # Determine which elements to show/hide by default.
  # It might make more sense to do this in JS, but since I am utterly
  # incapable of writing maintainable JS I'm doing it here in order to keep the
  # JS stupid and simple.
  # TODO: Highlight systems/packages where the 'current' man page is?
  for my $sys (@$tree) {
    $sys->{expand} = 1 if $sys->{childs}[0]{name}; # Expand all systems that have named versions
    $sys->{expand} = 1 if $f->{hash}; # Expand everything on 'location'

    my $i = 0;
    for my $sysver (@{$sys->{childs}}) {
      $i++;
      $sysver->{expand} = 1 if !$sysver->{name}; # Expand unnamed versions (since you can't click them)
      $sysver->{expand} = 1 if $f->{hash}; # Expand everything on 'location'
      $sysver->{hide} = 1 if $i > 3 && @{$sys->{childs}} > 5;    # Show only the first 3 versions

      for my $pkg (@{$sysver->{childs}}) {
        $pkg->{expand} = 1 if @{$sysver->{childs}} <= 3; # Expand everything if there's not too many things to expand
        $pkg->{expand} = 1 if $f->{hash}; # Expand everything on 'location'

        # TODO: Show/Hide duplicate hashes?
      }
    }
  }

  # Why JSON? Because TUWF::XML is pretty slow with many nodes
  $self->resHeader('Content-Type' => 'application/json; charset=UTF-8');
  lit(JSON::XS->new->ascii->encode($tree));
}



package TUWF::Object;

use TUWF ':html', 'html_escape';
use Time::Local 'timegm';

sub escape_like {
  (my $v = shift) =~ s/([_%])/\\$1/g;
  $v;
}


sub htmlHeader {
  my $self = shift;
  my %o = @_;

  html;
   head;
    Link rel => 'stylesheet', type => 'text/css', href => '/man.css?4';
    title $o{title}.' - manned.org';
   end 'head';
   body;

    div id => 'header';
     a href => '/', 'manned.org';
     form action => '/browse/search', method => 'get';
      input type => 'text', name => 'q', id => 'q', tabindex => 1;
      input type => 'submit', value => ' ';
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
       | <a href="/info/about">About manned.org</a>
       | <a href="mailto:contact@manned.org">Contact</a>
       | <a href="https://g.blicky.net/manned.git/">Source</a>';
    end;
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


# Set the last modification time from a string in yyyy-mm-dd format.
sub setLastMod {
  my($s, $d) = @_;
  return if $d !~ /^(\d{4})-(\d{2})-(\d{2})/;
  my @t = gmtime timegm 0,0,0,$3,$2-1,$1;
  $s->resHeader('Last-Modified', sprintf '%s, %02d %s %04d %02d:%02d:%02d GMT',
    (qw|Sun Mon Tue Wed Thu Fri Sat|)[$t[6]], $t[3],
    (qw|Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec|)[$t[4]],
    $t[5]+1900, $t[2], $t[1], $t[0]);
}


sub dbManContent {
  my($s, $hash) = @_;
  return $s->dbRow(q{SELECT content FROM contents WHERE hash = decode(?, 'hex')}, $hash)->{content};
}


# Options: name, section, shorthash, package, results, sort, countonly
sub dbManInfo {
  my $s = shift;
  my %o = (
      sort => '',
      page => 1,
      results => 10_000,
      @_
  );

  my %where = (
    $o{name}      ? ('m.name = ?'    => $o{name}) : (),
    $o{package}   ? ('m.package = ?' => $o{package}) : (),
    defined($o{section}) ? ('m.section = ?' => $o{section}) : (),
    $o{locale}    ? ('m.locale = ?'  => $o{locale}) : (),
    defined($o{locale}) && !$o{locale}  ? ('m.locale IS NULL' => 1) : (),
    $o{shorthash} ? (q{substring(m.hash from 1 for 4) = decode(?, 'hex')} => $o{shorthash}) : (),
    $o{hash}      ? (q{m.hash = decode(?, 'hex')} => $o{hash}) : (),
  );

  my $order =
    $o{sort} eq 'syspkgname' ? 'ORDER BY s.name, s.relorder DESC, p.name, v.released DESC, m.name, m.locale NULLS FIRST, m.filename' : '';

  my $select = $o{countonly} ? 'COUNT(*) as count'
    : "p.system, p.category, p.name AS package, v.version, v.released, v.id AS verid, m.name, m.section, m.filename, m.locale, encode(m.hash, 'hex') AS hash";

  my($r, $np) = $s->dbPage(\%o, q{
    SELECT !s
      FROM man m
      JOIN package_versions v ON v.id = m.package
      JOIN packages p ON p.id = v.package
      JOIN systems s ON s.id = p.system
        !W
        !s
  }, $select, \%where, $order);
  wantarray ? ($r, $np) : $r;
}


# Very simple (and fast) prefix match.
sub dbSearch {
  my($s, $q, $limit) = @_;

  my $sect = $q =~ s/^([0-9])\s+// || $q =~ s/\(([a-zA-Z0-9]+)\)$// ? $1 : '';
  my $name = $q =~ s/^([a-zA-Z0-9,.:_-]+)// ? $1 : '';

  return !$name ? [] : $s->dbAll(
    'SELECT name, section FROM man_index !W ORDER BY name, section LIMIT ?',
    {
      'lower(name) LIKE ?' => escape_like(lc $name).'%',
      $sect ? ('section ILIKE ?' => escape_like(lc $sect).'%') : (),
    },
    $limit
  );
}


# Get the preferred man page for the given filters. Returns a row with the same fields as dbManInfo().
sub dbManPref {
  my($s, %o) = @_;
  my %where = (
    $o{name}    ? ('m.name = ?' => $o{name}) : (),
    $o{shorthash} ? (q{substring(m.hash from 1 for 4) = decode(?, 'hex')} => $o{shorthash}) : (),
    $o{section} ? ('m.section LIKE ?' => escape_like($o{section}).'%') : (),
    $o{sysid}   ? ('p.system = ?' => $o{sysid}) : (),
    $o{package} ? ('p.id = ?' => $o{package}) : (),
    $o{pkgver}  ? ('v.id = ?' => $o{pkgver}) : (),
    $o{language}? (q{substring(locale from '^[^.]+') = ?} => $o{language}) : (),
  );

  # Criteria to determine a "preferred" man page:
  # 1. english:  English versions of a man page have preference over other locales
  # 2. pkgver:   Newer versions of the same package have preference over older versions
  # 3. stdloc:   Prefer man pages in standard locations
  # 4. secmatch: Prefer an exact section match
  # 5. arch:     Prefer Arch over other systems (because it tends to be the most up-to-date, and closest to upstreams)
  # 6. sysrel:   Prefer a later system release over an older release
  # 7. secorder: Lower sections before higher sections (because man does it this way, for some reason)
  # 8. pkgdate:  Prefer more recent packages (cross-distro)
  # 9. Fall back on hash comparison, to ensure the result is stable

  $s->dbAll(q{
    WITH unfiltered AS (
      SELECT s AS sys, p AS pkg, v AS ver, m AS man
        FROM man m
        JOIN package_versions v ON v.id = m.package
        JOIN packages p ON p.id = v.package
        JOIN systems s ON s.id = p.system
        !W
    ), f_english AS(
      SELECT * FROM unfiltered WHERE NOT EXISTS(SELECT 1 FROM unfiltered WHERE is_english_locale((man).locale)) OR is_english_locale((man).locale)
    ), f_pkgver AS(
      SELECT * FROM f_english a WHERE NOT EXISTS(SELECT 1 FROM f_english b WHERE (a.ver).package = (b.ver).package AND (a.ver).released < (b.ver).released)
    ), f_stdloc AS(
      SELECT * FROM f_pkgver WHERE NOT EXISTS(SELECT 1 FROM f_pkgver WHERE is_standard_man_location((man).filename)) OR is_standard_man_location((man).filename)
    ), f_secmatch AS(
      SELECT * FROM f_stdloc WHERE NOT EXISTS(SELECT 1 FROM f_stdloc WHERE (man).section = ?) OR (man).section = ?
    ), f_arch AS(
      SELECT * FROM f_secmatch WHERE NOT EXISTS(SELECT 1 FROM f_secmatch WHERE (sys).id = 1) OR (sys).id = 1
    ), f_sysrel AS(
      SELECT * FROM f_arch a WHERE NOT EXISTS(SELECT 1 FROM f_arch b WHERE (a.sys).name = (b.sys).name AND (a.sys).relorder < (b.sys).relorder)
    ), f_secorder AS(
      SELECT * FROM f_sysrel a WHERE NOT EXISTS(SELECT 1 FROM f_sysrel b WHERE (a.man).section > (b.man).section)
    ), f_pkgdate AS(
      SELECT * FROM f_secorder a WHERE NOT EXISTS(SELECT 1 FROM f_secorder b WHERE (a.ver).released < (b.ver).released)
    )
    SELECT (pkg).system, (pkg).category, (pkg).name AS package, (ver).version, (ver).released, (ver).id AS verid,
           (man).name, (man).section, (man).filename, (man).locale, encode((man).hash, 'hex') AS hash
     FROM f_pkgdate ORDER BY (man).hash LIMIT 1
  }, \%where, $o{section}||'', $o{section}||'')->[0];
}


# Given the name of a man page with optional section, find out the actual name
# and section prefix of the man page and the preferred version.
sub dbManPrefName {
  my($s, $name, %o) = @_;

  my $man = $s->dbManPref(%o, name => $name);
  return ($man, '') if $man;

  return (undef, '') if $name !~ s/\.([^.]+)$//;
  my $section = $1;
  $man = $s->dbManPref(%o, name => $name, section => $section);
  return ($man, $section) if $man;
  return (undef, '');
}


# Returns 1 of there are alternative versions of the given man page.
sub dbManHasVersions {
  my($s, $name, $section, $locale, $hash) = @_;
  return $s->dbRow(
    q{SELECT 1 AS ok FROM man WHERE name = ? AND section = ? AND locale IS NOT DISTINCT FROM ? AND hash <> decode(?, 'hex') LIMIT 1},
    $name, $section, $locale, $hash
  )->{ok}||0;
}


# Returns all available languages for a man page
sub dbManLanguages {
  my($s, $name, $section) = @_;
  return map $_->{lang}, @{$s->dbAll(q{SELECT DISTINCT substring(locale from '^[^.]+') AS lang
     FROM man WHERE name = ? AND section = ?
    ORDER BY substring(locale from '^[^.]+') NULLS FIRST
  }, $name, $section)};
}


# Returns all available languages for a man page
sub dbManSections {
  my($s, $name) = @_;
  return map $_->{section}, @{$s->dbAll(q{SELECT DISTINCT section FROM man WHERE name = ? ORDER BY section}, $name)};
}


sub dbSystemGet {
  return shift->dbAll('SELECT id, name, release, short, relorder FROM systems ORDER BY name, relorder');
}


# Options: sysid char hasman page results countonly
sub dbPackageGet {
  my $s = shift;
  my %o = (results => 10, page => 1, @_);

  my @where = (
    $o{sysid}    ? ('system = ?'   => $o{sysid}   ) : (),
    $o{category} ? ('category = ?' => $o{category}) : (),
    $o{name}     ? ('name = ?'     => $o{name}    ) : (),
    # This seems slow, perhaps cache?
    defined($o{hasman}) ? ('!s EXISTS(SELECT 1 FROM package_versions pv WHERE pv.package = p.id AND EXISTS(SELECT 1 FROM man m WHERE m.package = pv.id))' => $o{hasman}?'':'NOT') : (),
    $o{char} ? ( 'LOWER(SUBSTR(name, 1, 1)) = ?' => $o{char} ) : (),
    defined($o{char}) && !$o{char} ? ( '(ASCII(name) < 97 OR ASCII(name) > 122) AND (ASCII(name) < 65 OR ASCII(name) > 90)' => 1 ) : (),
  );

  my $select = $o{countonly} ? 'COUNT(*) as count' : 'id, system, name, category';
  my $order = $o{countonly} ? '' : 'ORDER BY name';

  my($r, $np) = $s->dbPage(\%o,
    'SELECT !s FROM packages p !W !s',
    $select, \@where, $order
  );
  wantarray ? ($r, $np) : $r;
}


sub dbPackageVersions {
  my($s, $id, $version) = @_;

  my %where = (
    'package = ?' => $id,
    $version ? ('version = ?' => $version) : (),
    'EXISTS(SELECT 1 FROM man m WHERE m.package = v.id)' => 1,
  );

  return $s->dbAll(q{
      SELECT id, version, released
        FROM package_versions v !W
    ORDER BY released DESC},
  \%where)
}


sub dbStats {
  return $_[0]->dbRow('SELECT * FROM stats_cache');
}

