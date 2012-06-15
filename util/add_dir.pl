#!/usr/bin/perl

# Usage: ./add_dir.pl <dir> <pkgid>
# Prints the path names of the found man pages on stdout.
# May throw errors or warnings on stderr.
# Returns 0 if it has added something, 1 on error or if nothing has been found.

use strict;
use warnings;
no warnings 'once';
use Encode 'decode', 'find_encoding', 'decode_utf8';
use Digest::SHA 'sha1_hex';
use File::Find;
use DBI;

die "Not enough arguments\n" if @ARGV < 2;
my($dir, $pkgid) = @ARGV;


my $db = DBI->connect('dbi:Pg:dbname=manned', 'manned', '', {
  pg_enable_utf8 => 1, PrintError => 0, RaiseError => 1, AutoCommit => 0
});


sub readman {
  my $ofn = shift;
  local $/;
  open my $F, '<', $ofn or die "Unable to open '$ofn': $!\n";
  my $dat = <$F>;
  close $F;

  # Note: Don't forget to update 'section_from_filename()' in SQL when a new
  # compression file extension is recognized.
  my $fn = $ofn;
  while(1) {
    if($fn =~ s/\.gz$//) {
      require Compress::Zlib;
      $dat = Compress::Zlib::memGunzip($dat);
      die "Error decompressing '$ofn': $Compress::Zlib::gzerrno\n" if !defined $dat;
      next;
    }
    if($fn =~ s/\.bz2$//) {
      # Don't try to use Compress::Bzip2::memBunzip() here. It's been terribly
      # broken for at least 3 years:
      # https://rt.cpan.org/Public/Bug/Display.html?id=48128
      require Compress::Raw::Bzip2;
      my($b, $s) = Compress::Raw::Bunzip2->new();
      my $r;
      die "Error decompressing '$ofn': Opening bzip2 decompressor: $s\n" if $s != Compress::Raw::Bzip2::BZ_OK();
      die "Error decompressing '$ofn': $s\n" if ($s = $b->bzinflate($dat, $r)) != Compress::Raw::Bzip2::BZ_STREAM_END();
      $dat = $r;
      next;
    }
    if($fn =~ s/\.lzma$//) {
      require Compress::Raw::Lzma;
      my($l, $s) = Compress::Raw::Lzma::AutoDecoder->new();
      my $r;
      die "Error decompressing '$ofn': Opening lzma decompressor: $s\n" if $s != Compress::Raw::Lzma::LZMA_OK();
      die "Error decompressing '$ofn': $s\n" if ($s = $l->code($dat, $r)) != Compress::Raw::Lzma::LZMA_STREAM_END();
      $dat = $r;
      next;
    }
    last;
  }

  return $dat;
}


sub decodeman {
  my($data, $locale) = @_;

  my @enc = ('utf-8'); # No harm in trying utf-8 first.

  # Check for 'coding:' indications in the file header.
  # According to preconv.1, only the first two lines are checked. I've not seen
  # any man page where this coding information was on the second line, though.
  # Note that that man page also mentions some aliasses that Perl's
  # find_encoding doesn't have. Again, I've not found any man page using those.
  my $re = qr/[\.']?\\["#].+-\*-.*coding: *([^ ;]+).+-\*-/;
  if($data =~ /^$re/ || $data =~ /^.*\n$re/) {
    (my $c = $1) =~ s/-(?:dos|unix|mac)$//;
    $c = find_encoding $c;
    $c = $c->name if $c;
    push @enc, $c if $c && $c ne 'ascii' && $c ne 'utf8' && $c ne 'utf-8-strict';
  }

  # Get encoding from the locale part of the path
  my $locenc = $locale && find_encoding $locale;
  unshift @enc, $locenc->name if $locenc;

  # Some language-specific fallbacks
  # TODO: Handle zh_* locales
  $locale && push @enc,
    $locale =~ /^(pl|cs|sk)/i ? 'iso-8859-2'
  : $locale =~ /^tr/i ? 'iso-8859-9'
  : $locale =~ /^ru/i ? 'koi8-r' # TODO: Or iso-8859-5, probably want to autodetect that?
  : $locale =~ /^ja/i ? 'euc-jp' # TODO: Works for everything I've found yet, but Japanese isn't that simple. Probably want to detect Shift-JIS as well?
  : $locale =~ /^ko/i ? 'euc-kr'
  #: $locale =~ /^el/i ? 'iso-8859-7' # So far, all el mans I've seen were UTF-8.
  : ();

  # If all else fails.
  push @enc, 'iso-8859-1';

  # Now try decoding
  my($dec, $enc);
  for(@enc) {
    $enc = $_;
    $dec = eval { my $tmp = $data; decode($enc, $tmp, 1) };
    last if $dec;
  }

  return $dec ? ($enc, $dec) : ();
}


sub addman {
  my($pkg, $path, $fn, $locale) = @_;
  my $dat = readman $fn;
  my $hash = sha1_hex $dat;

  my($enc, $dec) = decodeman($dat, $locale);
  print "Invalid encoding or empty file: $path\n" and return if !$enc;

  $db->do(q{INSERT INTO contents (hash, content) VALUES(decode(?, 'hex'),?)}, {}, $hash, $dec)
    if !$db->selectrow_arrayref(q{SELECT 1 FROM contents WHERE hash = decode(?, 'hex')}, {}, $hash);

  $db->do(q{
    INSERT INTO man (package, name, section, filename, locale, hash)
        VALUES(?,name_from_filename(?),section_from_filename(?),?,?,decode(?, 'hex'))}, {},
    $pkg, $path, $path, $path, $locale, $hash);

  printf "$path ($enc)\n";
}



my $found = 0;

find sub {
  return if !-f $_;
  (my $path = $File::Find::name) =~ s/^\Q$dir\E//;
  # Note: fltk also creates pre-formatted pages in /cat$sectre/, but those are ignored.
  # TODO: Also ignore html and INDEX sections
  return warn "Ignoring $path\n" if $path !~ m{man(?:/([^/]+))?/man[0-9n]/([^/]+)$};
  addman $pkgid, $path, $2, $1;
  $found++;
}, $dir;


if($found) {
  $db->commit;
} else {
  warn "No man pages found.\n";
  $db->rollback;
  exit 1;
}

