package ManUtils;

use strict;
use warnings;
use AE;
use AnyEvent::Util;
use Encode 'decode_utf8', 'encode_utf8';


our $VERSION = '0.01';

require XSLoader;
XSLoader::load('ManUtils', $VERSION);


# Usage: $cv = fmt($input, \$output, \@errors)
# $cv = AnyEvent condition variable, fired when done.
# $input = UTF-8 encoded manual page source
# $output = variable that will hold the output when done
# @errors = list of warnings/errors while running groff
sub fmt {
  my($input, $output, $errors) = @_;
  my $cv = AE::cv;
  $$output = '';
  @$errors = ();

  $input =
    # Disable hyphenation, since that screws up man page references. :-(
     ".hy 0\n.de hy\n..\n"
    # Emulate man-db's --nj option
    .".na\n.de ad\n..\n"
    .$input;

  $input = encode_utf8($input);

  # Call grog to figure out which preprocessors to use.
  # $MANWIDTH works by using the following groff options: -rLL=100n -rLT=100n
  my $grog = run_cmd [qw|grog -Tutf8 -P-c -DUTF-8 -rLL=80n -rLT=80n -|],
    '<' => \$input,
    '>' => \my $cmd,
    '2>' => sub { $_[0] && push @$errors, "grog: $_[0]" };

  $grog->cb(sub {
    chomp($cmd);
    if(!$cmd || $cmd =~ /\n/) {
      push @$errors, !$cmd ? 'grog failed to produce output' : "Excessive grog output: $cmd";
      $cv->send;
      return;
    }

    my $double;
    @$errors = grep {
      chomp;
      s/^grog: grog: /grog: /;
      !$double && /there are several macro packages: (.+)$/ ? ($double = $1) && 0 : 1;
    } @$errors;

    my @cmd = split / /, $cmd;
    if($double) {
      my %double = map +($_,1), split / /, $double;
      # Use the first macro package in ASCIIbetical order. (This is somewhat
      # arbitrary, need to find a better conflict resolution method).
      my $macros = (sort keys %double)[0];
      # Replace macro arguments with our selected one.
      @cmd = grep !$double{$_}, @cmd;
      @cmd = (@cmd[0..$#cmd-1], $macros, $cmd[$#cmd]);
      push @$errors, "grog detected several macro packages: $double. Using $macros. (@cmd)";
    }

    my $groff = run_cmd \@cmd,
      '<' => \$input,
      '>' => \my $fmt,
      '2>' => sub { if($_[0]) { chomp(my $e = $_[0]); push @$errors, "groff: $e" } };

    $groff->cb(sub {
      $$output = $fmt ? decode_utf8($fmt) : '';
      $$output =~ s/[\t\s\r\n]+$//;
      $cv->send;
    });
  });

  $cv;
}


# Blocking version of fmt(). Returns the formatted man page, errors are
# forwarded to warn().
sub fmt_block {
  my $c = shift;
  my $cv = fmt $c, \my $out, \my @err;
  $cv->recv;
  #warn "$_\n" for @err;
  $out;
}

1;
