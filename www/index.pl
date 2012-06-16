#!/usr/bin/perl

use strict;
use warnings;
use TUWF ':html', 'html_escape';
use IPC::Open2;
use IO::Select;
use Encode 'encode_utf8', 'decode_utf8';
use Time::HiRes 'tv_interval', 'gettimeofday';

use Cwd 'abs_path';
our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/www/index\.pl$}{}; }


use lib "$ROOT/lib/GrottyParser/inst/lib/perl5";
use GrottyParser;


TUWF::set(
  logfile => $ENV{TUWF_LOG},
  db_login => [undef, undef, undef],
  debug => 1,
  xml_pretty => 2,
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
  p 'Welcome blah mission etc.';
  h2 'What do you index?';
  p 'System and repos etc.';

  h2 'Browse!';
  ul;
   for(@{$self->{systems}}) {
     li;
      a href => "/browse/$_->{short}", $_->{full};
     end;
   }
  end;

  h2 'Will you do ...?';
  p 'This page looks more like FAQ than a front page... hmmm.';
  h2 'Stats?';
  p 'Stats are always nice!';
  h2 'Other sites';
  p '<insert some links here>';
  $self->htmlFooter;
}


sub browsesys {
  my($self, $short) = @_;

  my $sys = $self->{sysbyshort}{$short};
  return $self->resNotFound if !$sys;

  my $chr = $ENV{QUERY_STRING} ? $ENV{QUERY_STRING} : $ENV{QUERY_STRING} eq '' ? 'a' : '0';
  return $self->resNotFound if $chr !~ /^[0a-z]$/;
  my $pkg = $self->dbPackageList($sys->{id}, $chr);

  my $title = "Packages for $sys->{name}".($sys->{release}?" $sys->{release}":"");
  $self->htmlHeader(title => $title);
  h1 $title;

  p;
   for(0, 'a'..'z') {
     a href => "/browse/$short?$_", $_?$_:'#' if $_ ne $chr;
     b $_?$_:'#' if $_ eq $chr;
   }
  end;

  p 'Note: Packages without man pages are not listed.';
  ul;
   for(@$pkg) {
     li;
      a href => "/browse/$short/$_->{name}", $_->{name};
      i $_->{category};
     end;
   }
  end;
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
    ul;
     # TODO: Put this sort in the SQL query
     for(sort { $a->{name}."\x09".($a->{locale}||'') cmp $b->{name}."\x09".($b->{locale}||'') } @$mans) {
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


sub manselect {
  my($self, $lst, $selhash) = @_;
  return if !@$lst;

  $selhash ||= '';

  my %sys;
  push @{$sys{$_->{system}}}, $_ for (@$lst);

  dl id => 'nav';
   for my $sys (sort { my $x=$self->{sysbyid}{$a}; my $y=$self->{sysbyid}{$b}; $x->{name} cmp $y->{name} or $y->{relorder} <=> $x->{relorder} } keys %sys) {
     my %pkgs;
     push @{$pkgs{"$_->{package}-$_->{version}"}}, $_ for @{$sys{$sys}};
     dt $self->{sysbyid}{$sys}{full};
     dd;
      # TODO: This package sorting sucks. Versions should be date-sorted, in descending order.
      for my $pkg (sort keys %pkgs) {
        dl;
         dt $pkg;
         dd;
          for my $man (sort { $a->{section} cmp $b->{section} } @{$pkgs{$pkg}}) {
            my $t = $man->{locale} ? "$man->{section}.$man->{locale}" : $man->{section};
            a href => sprintf('/%s/%s', $man->{name}, substr $man->{hash}, 0, 8), $t if $selhash ne $man->{hash};
            b $t if $selhash eq $man->{hash};
            txt ' ';
          }
         end;
        end;
      }
     end 'dd';
   }
  end 'dl';
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
  return $ret;
}


sub manhtml {
  my $t0 = [gettimeofday];
  my $d = GrottyParser::html(shift);
  warn sprintf "manhtml took %fms\n", tv_interval($t0)*1000;
  return $d;
}


# Given the name and optionally the section or hash of a man page, check with a
# list of man pages with the same name to select the right hash for display.
sub gethash {
  my($self, $name, $sect, $hash, $list) = @_;

  # If we already have a shorthash, just get the full hash
  if($hash) {
    $_->{hash} =~ /^$hash/ && return $_->{hash} for (@$list);
  }

  # If that failed, sort the list based on some heuristics.
  my @l = sort {
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
  } @$list;

  return $l[0]{hash};
}


sub man {
  my($self, $name, $hash) = @_;

  my $sect = $name =~ s/\.([0-9n])$// ? $1 : undef;
  my $m = $self->dbManInfo(name => $name);
  return $self->resNotFound() if !@$m;
  $hash = gethash($self, $name, $sect, $hash, $m);

  $self->htmlHeader(title => $name);
  manselect $self, $m, $hash;

  h1 $name;
  p;
   txt $hash;
   txt ' - ';
   a href => "/$name/".substr($hash, 0, 8), 'permalink';
   txt ' - ';
   a href => "/$name/".substr($hash, 0, 8).'/src', 'source';
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
    my $l = $self->dbManInfo(hash => $hash);
    for(@$l) {
      Tr;
       td $self->{sysbyid}{$_->{system}}{full};
       td "$_->{category}/$_->{package}";
       td $_->{version};
       td;
        a href => "/$_->{name}", $_->{name} if $_->{name} ne $name;
        txt $_->{name} if $_->{name} eq $name;
        txt ".$_->{section}";
       end;
       td $_->{filename};
      end;
    }
   end;
  end;

  div id => 'contents';
   h2 'Contents';
   my $c = $self->dbManContent($hash);
   pre; lit manhtml manfmt $c; end;
  end;
  $self->htmlFooter;
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
    style type => 'text/css';
     lit 'thead tr { font-weight: bold; border-bottom: 1px solid #ccc }';
     lit 'table td { border-left: 1px solid #ccc; padding: 0 3px }';
     lit 'table { border-collapse: collapse }';
    end;
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
}


sub htmlFooter {
  my $self = shift;

     div id => 'footer';
       lit '2012 manned.org';
     end;
   end 'body';
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

  my %where = (
    $o{name}      ? ('m.name = ?' => $o{name}) : (),
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
sub dbPackageList {
  my($s, $sysid, $char) = @_;

  my @where = (
    'system = ?' => $sysid,
    'EXISTS(SELECT 1 FROM man m WHERE m.package = p.id)' => 1,
    $char ? ( 'LOWER(SUBSTR(name, 1, 1)) = ?' => $char ) : (),
    defined($char) && !$char ? ( '(ASCII(name) < 97 OR ASCII(name) > 122) AND (ASCII(name) < 65 OR ASCII(name) > 90)' => 1 ) : (),
  );

  return $s->dbAll(q{
      SELECT DISTINCT name, category
        FROM package p
          !W
    ORDER BY name},
  \@where)
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

