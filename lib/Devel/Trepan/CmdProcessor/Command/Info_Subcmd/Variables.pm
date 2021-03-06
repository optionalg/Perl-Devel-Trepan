# -*- coding: utf-8 -*-
# Copyright (C) 2011-2012, 2014 Rocky Bernstein <rocky@cpan.org>
use warnings;
use rlib '../../../../..';
use strict;
use vars qw(@ISA @SUBCMD_VARS);

package Devel::Trepan::CmdProcessor::Command::Info::Variables;

use Devel::Trepan::CmdProcessor::Command;
use Devel::Trepan::CmdProcessor::Command::Subcmd::Core;
use Devel::Trepan::CmdProcessor::Command::Subcmd::SubsubMgr;
use vars qw(@ISA @SUBCMD_VARS);
our $MIN_ABBREV = length('va');
=pod

=head2 Synopsis:

=cut
our $HELP   = <<'HELP';
=pod

B<info variables> [B<lexicals>|B<my>|B<our> ...]

Information on I<our>, I<my>, or I<lexical> variables.
=cut
HELP
our $SHORT_HELP   = "List 'our' or 'my' variables.";

@ISA = qw(Devel::Trepan::CmdProcessor::Command::SubsubcmdMgr);

unless (caller) {
    # Demo it.
    # FIXME: DRY with other subcommand manager demo code.
    require Devel::Trepan::CmdProcessor;
    my $proc = Devel::Trepan::CmdProcessor->new;
    my $parent = Devel::Trepan::CmdProcessor::Command::Info->new($proc, 'info');
    my $cmd = __PACKAGE__->new($parent, 'variables');
    print $cmd->{help}, "\n";
    print "min args: ", $cmd->MIN_ARGS, "\n";
    for my $arg ('le', 'my', 'foo') {
        my @aref = $cmd->complete_token_with_next($arg);
        printf "%s\n", @aref ? $aref[0]->[0]: 'undef';
    }

    print join(' ', @{$cmd->{prefix}}), "\n";
    print '-' x 30, "\n";
    $cmd->run($cmd->{prefix});
}

1;
