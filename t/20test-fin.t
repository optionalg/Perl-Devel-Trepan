#!/usr/bin/env perl
use warnings; use strict;
use rlib '.'; use Helper;

no warnings 'redefine';

my $test_prog = prog_file('TCPPack.pm');
run_debugger("$test_prog");

$test_prog = prog_file('gcd.pl');
run_debugger("$test_prog 3 5", 'fin2.cmd');

$test_prog = prog_file('gcd.pl');
run_debugger("$test_prog 3 5", 'fin3.cmd');

done_testing();
