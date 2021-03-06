# -*- coding: utf-8 -*-
# Copyright (C) 2011-2012, 2014-2015 Rocky Bernstein <rocky@cpan.org>
use warnings; no warnings 'redefine'; no warnings 'once';
use rlib '../../../../..';

package Devel::Trepan::CmdProcessor::Command::Set::Timer;

use Devel::Trepan::CmdProcessor::Command::Subcmd::Core;

@ISA = qw(Devel::Trepan::CmdProcessor::Command::SetBoolSubcmd);
# Values inherited from parent
use vars @Devel::Trepan::CmdProcessor::Command::Subcmd::SUBCMD_VARS;

our $IN_LIST      = 1;
=pod

=head2 Synopsis:

=cut

our $HELP         = <<"HELP";
=pod

B<set timer> [B<on>|B<off>]

Tracks and shows elapsed time between debugger events. If "on" or
"off" is not given, "on" is assumed.

Since debugger overhead can be large depending on what you are doing,
there are many ways to customize the debugger to take less time (and
do less).

Stepping is slow, running to a breakpoint without stepping is
relatively fast compared to previous versions of the debugger and
compared to stepping.

Stopping at fewer events can also speed things up. Trace event
buffering slows things down.

Buy turning this setting on, you may be able to get a feel for what
how expensive the various settings.

=head2 See also:

L<C<set events>|Devel::Trepan::CmdProcessor::Command::Set::Events>,
L<C<set trace buffer>|Devel::Trepan::CmdProcessor::Command::Set::Trace::Buffer>,
L<C<step>|Devel::Trepan::CmdProcessor::Command::Step>, and
L<C<break>|Devel::Trepan::CmdProcessor::Command::Break>,

=cut
HELP

our $SHORT_HELP = "Set to show elapsed time between debugger events";
our $MIN_ABBREV = length('ti');

sub run($$)
{
    my ($self, $args) = @_;
    $self->SUPER::run($args);
    my $proc = $self->{proc};
    if ( $proc->{settings}{timer} ) {
        $proc->{cmdloop_posthooks}->insert_if_new(-1, $proc->{timer_hook}[0],
                                                  $proc->{timer_hook}[1]);
        $proc->{cmdloop_prehooks}->insert_if_new(-1, $proc->{timer_hook}[0],
                                                 $proc->{timer_hook}[1]);
    } else {
        $proc->{cmdloop_posthooks}->delete_by_name('timer');
        $proc->{cmdloop_posthooks}->delete_by_name('timer');
    }
}

unless (caller) {
  # Demo it.
    # FIXME: DRY with other subcommand manager demo code.
    require Devel::Trepan::CmdProcessor::Mock;
    my ($proc, $cmd) =
	Devel::Trepan::CmdProcessor::Mock::subcmd_setup();
    Devel::Trepan::CmdProcessor::Mock::subcmd_demo_info($proc, $cmd);
    $cmd->run($cmd->{prefix});
    my @args = (@{$cmd->{prefix}}, 'off');
    $cmd->run(\@args);
}

1;
