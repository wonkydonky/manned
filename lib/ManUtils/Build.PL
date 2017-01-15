#!/usr/bin/perl

use Module::Build;

Module::Build->new(
  dist_name => 'ManUtils',
  dist_version_from => 'ManUtils.pm',
  dist_abstract => 'Utils for manned.org',
  license => 'MIT',
  extra_linker_flags => '../../web/target/release/libweb.a',
  pm_files => {
    'ManUtils.pm' => 'lib/ManUtils.pm',
  },
  xs_files => {
    'ManUtils.xs' => 'lib/ManUtils.xs',
  },
)->create_build_script;

