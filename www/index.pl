#!/usr/bin/perl

use strict;
use warnings;
use TUWF ':html', 'html_escape', ':xml';
use JSON::XS;

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

  qr{xml/search\.xml} => \&xmlsearch,
  qr{([^/]+)/([0-9a-f]{8})} => \&man,
  qr{([^/]+)/([0-9a-f]{8})/src} => \&src,
  qr{([^/]+)} => \&man,
);

TUWF::run();


sub home {
  my $self = shift;
  my $stats = $self->dbStats;
  my $fn = sub { local $_=shift; 1 while(s/(\d)(\d{3})($|,)/$1,$2/); $_ };
  $self->htmlHeader(title => 'Man Pages Archive');
  h1 'Man Pages Archive';
  p; lit sprintf <<'  _', map $fn->($stats->{$_}), qw|hashes mans files packages|;
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
   li; a href => 'http://man.cx/', 'Man.cx'; end;
   li; a href => 'http://man.he.net/', 'Man.he.net'; end;
   li; a href => 'http://linux.die.net/man/', 'Die.net'; end;
   li; a href => 'http://www.freebsd.org/cgi/man.cgi', 'FreeBSD.org Man Pages'; end;
   li; a href => 'http://www.openbsd.org/cgi-bin/man.cgi', 'OpenBSD Man Pages'; end;
   li; a href => 'http://manpages.ubuntu.com/', 'Ubuntu Manuals'; end;
   li; a href => 'http://www.manpagez.com/', 'Manpagez.com'; txt ' (Mac OS X, has some texinfo documentation as well)'; end;
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

  h2 'URL format';
  lit <<'  _';
   <p>You can link to specific packages and man pages with several URL formats.
   These URLs will keep working in the future, so you should not have to worry
   about eventual dead links.</p>
   <h3>Man pages</h3>
   <p>The following URLs are available to refer to an individual man page:</p>
   <dl>
    <dt><code>/&lt;name>/&lt;8-hex-digit-hex></code></dt><dd>
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
     Arch mirror. Indexing started around begin June 2012.</dd>
    <dt>Debian</dt><dd>
     Historical releases were fetched from <a
     href="http://archive.debian.org/debian/">http://archive.debian.org/debian/</a>
     and <a href="http://snapshot.debian.org/">http://snapshot.debian.org/</a>.
     For buzz, rex and bo, only the 'main' component has been indexed, and
     we're missing a few man pages because some packages were missing from the
     repository archives. For the other releases, all components (main, contrib
     and non-free) from the $release and $release-updates (where available)
     repositories are indexed.</dd>
    <dt>FreeBSD</dt><dd>
     Historical releases were fetched from <a
     href="http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/">http://ftp-archive.freebsd.org/mirror/FreeBSD-Archive/</a>.
     The base installation tarballs are included in the database as packages
     prefixed with <i>core-</i>. The package repositories have also been
     indexed, except for 2.0.5 - 2.2.7 and 3.0 - 3.3 because those were not
     available on the ftp archive. Only the -RELEASE repositories have been
     included, which is generally a snapshot of the ports directory around the
     time of the release. A few packages are missing because the indexing
     script was unable to determine the package name and version for
     everything. Additionally, the dates indicated for many packages is a bit
     off, and the site doesn't handle this very well yet. :-(</dd>
    <dt>Ubuntu</dt><dd>
     Historical releases were fetched from <a
     href="http://old-releases.ubuntu.com/ubuntu/">http://old-releases.ubuntu.com/ubuntu/</a>,
     supported releases from a local mirror.  All components (main, universe,
     restricted and multiverse) from the $release, $release-updates and
     $release-security repositories are indexed.  Backports are not included at
     the moment. Indexing started around mid June 2012.</dd>
   </dl>
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
   Although further development of this site is a bit stalled at the moment,
   I'd love to index the manuals of most major Linux distributions in the
   future. Fedora and OpenSUSE, in particular, are interesting targets to
   index.
   <br /><br />
   It would also be great to index a few more non-Linux systems such as other
   BSDs, Solaris/Illumos and Mac OS X. Unfortunately, those don't always follow
   a binary package based approach, or are otherwise less easy to properly
   index.
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
    <li>Table of Contents for each man page,</li>
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
    { get => 's', required => 0, regex => qr/^[a-zA-Z0-9_+.-]+$/i },
  );
  return $self->resNotFound if $f->{_err};

  my $pkg = $self->dbPackageGet(
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
    if($more) {
      p class => 'pagination';
       a href => "/pkg/$short?c=$f->{c};s=$pkg->[199]{name}", 'next »';
      end;
    }
  };

  my $title = "Packages for $sys->{name}".($sys->{release}?" $sys->{release}":"");
  $self->htmlHeader(title => $title);
  h1 $title;

  p id => 'charselect';
   for('all', 0, 'a'..'z') {
     a href => "/pkg/$short?c=$_", $_?uc$_:'#' if $_ ne $f->{c};
     b $_?uc$_:'#' if $_ eq $f->{c};
   }
  end;

  p 'Note: Packages without man pages are not listed.';
  $next->();
  ul id => 'packages';
   for(@$pkg) {
     li;
      a href => "/pkg/$short/$_->{category}/$_->{name}", $_->{name};
      i ' '.$_->{category};
     end;
   }
  end;
  $next->();
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

  my $f = $self->formValidate({ get => 's', required => 0});
  return $self->resNotFound if $f->{_err};

  my $mans = $self->dbManInfo(package => $sel->{id}, results => 201, start => $f->{s}, sort => 'name');
  my $more = @$mans > 200 && pop @$mans;

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
   ul;
    for(@$mans) {
      li;
       a href => "/$_->{name}/".substr($_->{hash},0,8), "$_->{name}($_->{section})";
       b " $_->{locale}" if $_->{locale};
       i " $_->{filename}";
      end;
    }
   end;
   if($more) {
     use utf8;
     p class => 'pagination';
      a href => "/pkg/$sys->{short}/$pkg->{category}/$pkg->{name}/$sel->{version}?s=$mans->[199]{name}", 'next »';
     end;
   }
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


sub manjslist {
  my($self, $m) = @_;

  # The structure we generate is described in the JS code.
  my %sys;
  push @{$sys{$_->{system}}}, $_ for (@$m);
  [
    map [ $self->{sysbyid}{$_}{name}, $self->{sysbyid}{$_}{full}, $self->{sysbyid}{$_}{short},
      do {
        my %pkgs;
        for(@{$sys{$_}}) {
          my $pn = "$_->{category}-$_->{package}-$_->{version}";
          $pkgs{$pn} = [ $_->{category}, $_->{package}, $_->{version}, [], $_->{released} ] if !$pkgs{$pn};
          push @{$pkgs{$pn}[3]}, [ $_->{section}, $_->{locale}, substr $_->{hash}, 0, 8 ];
        }
        [ grep
          delete($_->[4]) && ($_->[3] = [sort { $a->[0] cmp $b->[0] || ($a->[1]||'') cmp ($b->[1]||'') } @{$_->[3]}]),
          sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] || $b->[4] cmp $a->[4] } values %pkgs ];
      }
    ],
    sort { my $x=$self->{sysbyid}{$a}; my $y=$self->{sysbyid}{$b}; $x->{name} cmp $y->{name} or $y->{relorder} <=> $x->{relorder} } keys %sys
  ]
}


sub man {
  my($self, $name, $hash) = @_;

  # Firefox seems to escape [ and ] in URLs. It doesn't really have to...
  $name =~ s/%5b/[/ig;
  $name =~ s/%5d/]/ig;

  my $man;
  if($hash) {
    $man = $self->dbManInfo(name => $name, shorthash => $hash)->[0];
  } else {
    ($man, undef) = $self->dbManPrefName($name);
  }
  return $self->resNotFound() if !$man;

  my $view = $self->formValidate({get => 'v', regex => qr/^[a-z2-7]+$/});
  $view = $view->{_err} ? '' : $view->{v};

  # To be really correct, the last modification time of this page should be the
  # release date of the latest version of the man page, as that is displayed in
  # the menu. But let's just consider the content of the page as more
  # important, and use release date of the man page as last modification date.
  $self->setLastMod($man->{released});

  $self->htmlHeader(title => $name);
  div id => 'nav', 'Sorry, this navigation menu won\'t display without Javascript. :-(';

  h1;
   txt $man->{name}.' ';
   a href => "/$man->{name}/".substr($man->{hash}, 0, 8).'/src', 'source';
  end;

  div id => 'contents';
   my $c = $self->dbManContent($man->{hash});
   # TODO: Store/cache the result of fmt() in the database.
   pre; lit ManUtils::html(ManUtils::fmt_block $c); end;
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

  my $m = $self->dbManInfo(name => $man->{name});
  $self->htmlFooter(js => { hash => substr($man->{hash}, 0, 8), name => $man->{name}, view => $view, mans => manjslist($self, $m) });
}


sub src {
  my($self, $name, $hash) = @_;

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
    Link rel => 'stylesheet', type => 'text/css', href => '/man.css?2';
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


# Options: name, section, shorthash, package, start, results, sort
sub dbManInfo {
  my $s = shift;
  my %o = @_;

  my %where = (
    $o{name}      ? ('m.name = ?'    => $o{name}) : (),
    $o{package}   ? ('m.package = ?' => $o{package}) : (),
    $o{section}   ? ('m.section = ?' => $o{section}) : (),
    $o{shorthash} ? (q{substring(m.hash from 1 for 4) = decode(?, 'hex')} => $o{shorthash}) : (),
    $o{hash}      ? (q{m.hash = decode(?, 'hex')} => $o{hash}) : (),
    $o{start}     ? ('m.name > ?' => $o{start}) : (),
  );

  # TODO: Flags to indicate what to information to fetch
  return $s->dbAll(q{
    SELECT p.system, p.category, p.name AS package, pv.version, pv.released, m.name, m.section, m.filename, m.locale, encode(m.hash, 'hex') AS hash
      FROM packages p
      JOIN package_versions pv ON p.id = pv.package
      JOIN man m ON m.package = pv.id
        !W
        !s
     LIMIT ?
  },
    \%where,
    $o{sort} ? 'ORDER BY name' : '',
    $o{results}||10000
  );
}


# Very simple (and fast) prefix match.
sub dbSearch {
  my($s, $q, $limit) = @_;

  my $sect = $q =~ s/^([0-9])\s+// || $q =~ s/\(([a-zA-Z0-9]+)\)$// ? $1 : '';
  my $name = $q =~ s/^([a-zA-Z0-9,.:_-]+)// ? $1 : '';

  return !$name ? [] : $s->dbAll(
    'SELECT name, section FROM man_index !W ORDER BY name, section LIMIT ?',
    { # Don't use wildcards in this query, prevents index usage.
      "lower(name) LIKE '\L$name\E%'" => 1,
      $sect ? ("section ILIKE '\L$sect\E%'" => 1) : ()
    },
    $limit
  );
}


# Get the preferred man page for the given filters. Returns a row with the same fields as dbManInfo().
sub dbManPref {
  my($s, $name, $section, %o) = @_;
  my %where = (
    'm.name = ?' => $name,
    $section    ? ('m.section LIKE ?' => escape_like($section).'%') : (),
    $o{sysid}   ? ('p.system = ?' => $o{sysid}) : (),
    $o{package} ? ('p.id = ?' => $o{package}) : (),
    $o{pkgver}  ? ('v.id = ?' => $o{pkgver}) : (),
  );

  # Criteria to determine a "preferred" man page:
  # 1. english:  English versions of a man page have preference over other locales
  # 2. pkgver:   Newer versions of the same package have preference over older versions
  # 3. stdloc:   Prefer man pages in standard locations
  # 4. secmatch: Prefer an exact section match
  # 5. arch:     Prefer Arch over other systems (because it tends to be the most up-to-date, and closest to upstreams)
  # 6. sysrel:   Prefer a later system release over an older release
  # 7. secorder: Lower sections before higher sections (because man does it this way, for some reason)
  # 8. Fall back on hash comparison, to ensure the result is stable

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
    )
    SELECT (pkg).system, (pkg).category, (pkg).name AS package, (ver).version, (ver).released,
           (man).name, (man).section, (man).filename, (man).locale, encode((man).hash, 'hex') AS hash
     FROM f_secorder ORDER BY (man).hash LIMIT 1
  }, \%where, $section, $section)->[0];
}


# Given the name of a man page with optional section, find out the actual name
# and section prefix of the man page and the preferred version.
sub dbManPrefName {
  my($s, $name, %o) = @_;

  my $man = $s->dbManPref($name, '', %o);
  return ($man, '') if $man;

  return (undef, '') if $name !~ s/\.([^.]+)$//;
  my $section = $1;
  $man = $s->dbManPref($name, $section, %o);
  return ($man, $section) if $man;
  return (undef, '');
}


sub dbSystemGet {
  return shift->dbAll('SELECT id, name, release, short, relorder FROM systems ORDER BY name, relorder');
}


# Options: sysid char hasman start results
sub dbPackageGet {
  my $s = shift;
  my %o = (results => 10, @_);

  my @where = (
    $o{sysid} ? ('system = ?' => $o{sysid}) : (),
    $o{category} ? ('category = ?' => $o{category}) : (),
    $o{name} ? ('name = ?' => $o{name}) : (),
    $o{start} ? ('name > ?' => $o{start}) : (),
    # This seems slow, perhaps cache?
    defined($o{hasman}) ? ('!s EXISTS(SELECT 1 FROM package_versions pv WHERE pv.package = p.id AND EXISTS(SELECT 1 FROM man m WHERE m.package = pv.id))' => $o{hasman}?'':'NOT') : (),
    $o{char} ? ( 'LOWER(SUBSTR(name, 1, 1)) = ?' => $o{char} ) : (),
    defined($o{char}) && !$o{char} ? ( '(ASCII(name) < 97 OR ASCII(name) > 122) AND (ASCII(name) < 65 OR ASCII(name) > 90)' => 1 ) : (),
  );

  return $s->dbAll(q{
      SELECT id, system, name, category
        FROM packages p
          !W
    ORDER BY name
       LIMIT ?},
  \@where, $o{results})
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

