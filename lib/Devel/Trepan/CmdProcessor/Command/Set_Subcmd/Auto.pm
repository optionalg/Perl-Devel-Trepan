# -*- coding: utf-8 -*-
# Copyright (C) 2011-2012, 2014-2015 Rocky Bernstein <rocky@cpan.org>
use warnings; no warnings 'redefine'; no warnings 'once';
use rlib '../../../../..';
use strict;
use vars qw(@ISA @SUBCMD_VARS);

package Devel::Trepan::CmdProcessor::Command::Set::Auto;

use Devel::Trepan::CmdProcessor::Command::Subcmd::Core;
use Devel::Trepan::CmdProcessor::Command::Subcmd::SubsubMgr;
use vars qw(@ISA @SUBCMD_VARS);
our $MIN_ABBREV = length('au');
=pod

=head2 Synopsis:

=cut

our $HELP   = <<'HELP';
=pod

B<set auto> [I<set auto subcommand>]

Set controls for things with some sort of automatic default behavior.

Run C<help set auto *> for a list of subcommands or C<help set auto> I<name>
for help on a particular trace subcommand.

=head2 See also:

L<C<show auto>|Devel::Trepan::CmdProcessor::Command::Show::Auto>

=cut
HELP

our $SHORT_HELP =
"Set controls for some \"automatic\" default behaviors";

@ISA = qw(Devel::Trepan::CmdProcessor::Command::SubsubcmdMgr);


# sub run($$)
# {
#     my ($self, $args) = @_;
#     $self->SUPER;
# }

unless (caller) {
    # Demo it.
    # FIXME: DRY with other subcommand manager demo code.
    require Devel::Trepan::CmdProcessor::Mock;
    my ($proc, $cmd) =
	Devel::Trepan::CmdProcessor::Mock::subcmd_setup();
    Devel::Trepan::CmdProcessor::Mock::subcmd_demo_info($proc, $cmd);
    for my $arg ('e', 'lis', 'foo') {
        my @aref = $cmd->complete_token_with_next($arg);
        printf "%s\n", @aref ? $aref[0]->[0]: 'undef';
    }

    print join(' ', @{$cmd->{prefix}}), "\n";
    $cmd->run($cmd->{prefix});

}

1;
