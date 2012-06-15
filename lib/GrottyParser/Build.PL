#!/usr/bin/perl

use Module::Build;

Module::Build->new(
  dist_name => 'GrottyParser',
  dist_version_from => 'GrottyParser.pm',
  pm_files => {
    'GrottyParser.pm' => 'lib/GrottyParser.pm',
  },
  xs_files => {
    'GrottyParser.xs' => 'lib/GrottyParser.xs',
  },
)->create_build_script;

