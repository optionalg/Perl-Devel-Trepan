#!/usr/bin/env perl
use warnings; use strict;
use rlib '.'; use Helper; 

my $opts = {
    filter => sub{
	my ($got_lines, $correct_lines) = @_;
	my @result = ();
	for my $line (split("\n", $got_lines)) {
	    # Change lines like
	    #   main::(kZiu.pl:1) to 
	    #   main::(tempfile:1)
	    $line =~ s/main::\((?:.+):(\d+)\)/(tempfile.pl:$1)/;
	    push @result, $line;
	}

	$got_lines = join("\n", @result);
	return ($got_lines, $correct_lines);
    },
    run_opts => ' --basename --no-highlight -nx'
};

run_debugger("-e '\$x=1; \$y=2'", cmd_file(), undef, $opts);
done_testing();