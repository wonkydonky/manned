#!/usr/bin/perl

use Module::Build;

Module::Build->new(
  dist_name => 'ManUtils',
  dist_version_from => 'ManUtils.pm',
  pm_files => {
    'ManUtils.pm' => 'lib/ManUtils.pm',
  },
  xs_files => {
    'ManUtils.xs' => 'lib/ManUtils.xs',
  },
)->create_build_script;

