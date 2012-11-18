# -*- coding: utf-8 -*-
# Copyright (C) 2012 Rocky Bernstein <rocky@cpan.org> 

use rlib '../..';

# A debugger BullWinkle protocol processor. This includes the debugger commands
# and ties together the debugger core and I/O interface.
package Devel::Trepan::BWProcessor;

use English qw( -no_match_vars );
use Exporter;
use warnings; no warnings 'redefine';

use vars qw(@EXPORT @ISA $eval_result);

# Showing eval results can be done using either data dump package.
use if !@ISA, Data::Dumper; 

# Eval does uses its own variables.
# FIXME: have a way to customize Data:Dumper, PerlTidy etc.
$Data::Dumper::Terse = 1; 
require Data::Dumper;

unless (@ISA) {
    require Devel::Trepan::CmdProcessor::Load;
    require Devel::Trepan::BrkptMgr;
    eval "require Devel::Trepan::DB::Display";
    require Devel::Trepan::Interface::Bullwinkle;
    require Devel::Trepan::Processor::Virtual;
    require Devel::Trepan::BWProcessor::Default;
    # require Devel::Trepan::CmdProcessor::Msg;
    # require Devel::Trepan::CmdProcessor::Help;
    # require Devel::Trepan::CmdProcessor::Hook;
    require Devel::Trepan::BWProcessor::Frame;
    require Devel::Trepan::CmdProcessor::Location;
    require Devel::Trepan::CmdProcessor::Eval;
    require Devel::Trepan::CmdProcessor::Running;
    require Devel::Trepan::CmdProcessor::Validate;
}
use strict;

use Devel::Trepan::Util qw(hash_merge uniq_abbrev parse_eval_sigil);

@ISA = qw(Exporter Devel::Trepan::Processor::Virtual);

BEGIN {
    @DB::D = ();  # Place to save eval results;
}

sub new($;$$$) {
    my ($class, $interfaces, $dbgr, $settings) = @_;
    my $intf;
    my $self = 
      Devel::Trepan::Processor::Virtual::new($class, $interfaces, $settings);
    if (defined $interfaces) {
        $intf = $interfaces->[0];
    } else {
        $intf = Devel::Trepan::Interface::Bullwinkle->new();
        $interfaces = [$intf];
    }
    $self->{actions}        = Devel::Trepan::BrkptMgr->new($dbgr);
    $self->{brkpts}         = Devel::Trepan::BrkptMgr->new($dbgr);
    $self->{displays}       = Devel::Trepan::DisplayMgr->new($dbgr);
    $self->{completions}    = [];
    $self->{dbgr}           = $dbgr;
    $self->{event}          = undef;
    $self->{cmd_queue}      = [];
    $self->{DB_running}     = $DB::running;
    $self->{DB_single}      = $DB::single;
    $self->{interfaces}     = $interfaces;
    $self->{last_command}   = undef;
    $self->{leave_cmd_loop} = undef;
    $self->{next_level}     = 30000;  # Virtually infinite;
    $self->{settings}       = hash_merge($settings, DEFAULT_SETTINGS());
    $self->{terminated}     = 0;

    # Initial watch point expr value used when a new watch point is set.
    # Set in 'watch' command, and reset here after we get the value back.
    $self->{set_wp}         = undef;

    $self->{skip_count}     = 0;
    # $self->load_cmds_initialize;
    # $self->running_initialize;
    # $self->hook_initialize;
    # $self->{unconditional_prehooks}->insert_if_new(10, 
    #                                                $self->{trace_hook}[0],
    #                                                $self->{trace_hook}[1]
    #     ) if $self->{settings}{traceprint};

    # $B::Data::Dumper::Deparse = 1;
    bless $self, $class;
    return $self;
}

sub DESTROY($)
{
    my $self = shift;
    # breakpoint_finalize
}

# Check that we meet the criteria that cmd specifies it needs
sub ok_for_running ($$$$) {
    my ($self, $cmd, $name, $nargs) = @_;
    # TODO check execution_set against execution status.
    # Check we have frame is not null
    my $min_args = eval { $cmd->MIN_ARGS } || 0;
    if ($nargs < $min_args) {
        my $msg = 
            sprintf("Command '%s' needs at least %d argument(s); " .
                    "got %d.", $name, $min_args, $nargs);
        $self->errmsg($msg);
        return;
    }
    my $max_args = eval { $cmd->MAX_ARGS } || undef;
    if (defined($max_args) && $nargs > $max_args) {
        my $mess = 
            sprintf("Command '%s' needs at most %d argument(s); " .
                    "got %d.", $name, $max_args, $nargs);
        $self->errmsg($mess);
        return;
    }

    if ($cmd->NEED_STACK && $self->{terminated}) {
        $self->errmsg("Command '$name' requires a running program.");
        return;
    }

    if ($cmd->NEED_STACK && !defined $self->{frame}) {
        $self->errmsg("Command '$name' requires a running stack frame.");
        return;
    }

    return 1;
}

# Run one debugger command. 1 is returned if we want to quit.
sub process_command_and_quit($) 
{
    my $self = shift;
    my $intf_ary = $self->{interfaces};
    my $intf = $intf_ary->[-1];
    my $intf_size = scalar @{$intf_ary};
    return 1 if !defined $intf || $intf->is_input_eof && $intf_size == 1;
    while ($intf_size > 1 || !$intf->is_input_eof) {
        # begin
        $self->{current_command} = '';
        my @cmd_queue = @{$self->{cmd_queue}};
	$self->{current_command} = shift @cmd_queue;
	$self->{cmd_queue} = \@cmd_queue;
        if ('' eq $self->{current_command}) {
            next unless $self->{last_command} && $intf->is_interactive;
            $self->{current_command} = $self->{last_command};
        }
        last;
        # rescue IOError, Errno::EPIPE => e
        # }
    }
    
    eval {
        $self->run_command($self->{current_command});
    };
    if ($EVAL_ERROR) {
        $self->errmsg("internal error: $EVAL_ERROR")
    }
}

sub skip_if_next($$) 
{
    my ($self, $event) = @_;
    return 0 if ('line' ne $event);
    return 0 if $self->{terminated};
    return 0 if eval { no warnings; $DB::tid ne $self->{last_tid} };
    # print  "+++event $event ", $self->{stack_size}, " ", 
    #        $self->{next_level}, "\n";
    return 1 if $self->{stack_size} > $self->{next_level};
}

# This is the main entry point.
sub process_commands($$$;$)
{
    my ($self, $frame, $event, $arg) = @_;

    if ($event eq 'terminated') {
        $self->{terminated} = 1;
        $self->section("Debugged program terminated.  Use 'q' to quit or 'R' to restart.");
    } elsif (!defined($event)) {
        $event = 'unknown';
    }
    
    my $next_skip = 0;
    if ($event eq 'after_eval' or $event eq 'after_nest') {
        handle_eval_result($self);
        if ($event eq 'after_nest') {
            $self->msg("Leaving nested debug level $DB::level");
            $self->{prompt} = compute_prompt($self);
            $self->frame_setup();
            $self->print_location;
        }
    } else {
        $self->{event} = $event;
        $self->frame_setup();

        if ($event eq 'watch') {
            my $msg = sprintf("Watchpoint %s: %s changed", 
                              $arg->id, $arg->expr);
            $self->section($msg);
            my $old_value = defined($arg->old_value) ? $arg->old_value 
                : 'undef';
            $msg = sprintf("old value\t%s", $old_value);
            $self->msg($msg);
            my $new_value = defined($arg->current_val) ? $arg->current_val
                : 'undef';
            $msg = sprintf("new value\t%s", $new_value);
            $self->msg($msg);
            $arg->old_value($arg->current_val);
        }

        $next_skip = skip_if_next($self, $event);
        unless ($next_skip) { 

            # prehooks include traceprint, list, and event saving.
            # $self->{unconditional_prehooks}->run;

            if (index($self->{event}, 'brkpt') < 0 && !$self->{terminated}) {
                # Not a breakpoint and not terminated.

                if ($event eq 'line') {

                    # We may want to not stop because of "step n"; step different, or 
                    # "next"
                    # use Enbugger; Enbugger->stop if 2 == $self->{next_level};
                    if ($self->is_stepping_skip()) {
                        # || $self->{stack_size} <= $self->{hide_level};
                        $self->{dbgr}->step;
                        return;
                    }
                    # trace print sets stepping even when though otherwise
                    # we may be are continuing, nexting, finishing, or
                    # returning.
                    if ($self->{settings}{traceprint}) {
                        $self->{dbgr}->step;
                        return unless 0 == $self->{skip_count};
                    }
                }
            }
        
            $self->{prompt} = compute_prompt($self);
            $self->print_location unless $self->{settings}{traceprint} ||
                $self->{terminated};

            ## $self->{eventbuf}->add_mark if $self->{settings}{tracebuffer};
            
            $self->{cmdloop_prehooks}->run;
        }
    }
    unless ($next_skip) {
        $self->{leave_cmd_loop} = 0;
        while (!$self->{leave_cmd_loop}) {
            $self->process_command_and_quit;
        }
    }
    unless ($self->{terminated}) {
        $self->{cmdloop_posthooks}->run;
        $self->{last_tid} = $DB::tid;
        $DB::single       = $self->{DB_single};
    }
    $DB::running = $self->{DB_running};
}

# run current_command, a string. @last_command is set after the
# command is run if it is a command.
sub run_command($$) 
{
    my ($self, $current_command) = @_;
    my $eval_command = undef;
    my $cmd_name = undef;
    my @cmd_queue = @{$self->{cmd_queue}};
    unless ($eval_command) {
        my @commands = split(';;', $current_command);
        if (scalar(@commands) > 1) {
            $current_command = shift @commands;
            $self->{cmd_queue} = \(@cmd_queue, @commands);
        }

        # Split on space trimming leading space. Note ' ' rather than say \s+
        # which splits on leading spaces among others.
        my @args = split(' ', $current_command);

        # Expand macros. FIXME: put in a procedure
        while (1) {
            return if scalar(@args) == 0;
            my $macro_cmd_name = $args[0];
            last unless $self->{macros}{$macro_cmd_name};
            my $debugging = $self->{settings}{debugmacro};
            # if ($debugging) {
            #   require Enbugger; Enbugger->stop();
            # }
            shift @args;
            my $macro_expanded = 
                $self->{macros}{$macro_cmd_name}[0]->(@args);
            if (ref $macro_expanded eq 'ARRAY' #  && 
#               current_command.all? {|val| val.is_a?(String)}
                ) {
                my @new_commands = @{$macro_expanded};
                $self->msg(join(' ', @new_commands)) if $debugging;
                if (scalar @new_commands > 0) {
                    push @cmd_queue, @new_commands;
                    $current_command = shift @cmd_queue;
                    @args = split(' ', $current_command);
                } else {
                    $current_command = '#';
                    @args = ();
                }
            } else {
                $self->msg($macro_expanded) if $debugging;
                $current_command = $macro_expanded;
                @args = split(/\s+/, $current_command);
            # } else {
            #   $self->errmsg("macro ${macro_cmd_name} should return a list " .
            #                 "of strings " .
            #                 # or a String
            #                 ". Got ${current_command.inspect}");
            #   return;
            }
        }

        my %commands = %{$self->{commands}};
        $cmd_name = $self->{cmd_name} = $args[0];
        my $run_cmd_name = $cmd_name;

        my %aliases = %{$self->{aliases}};
        if (exists $aliases{$cmd_name}) {
          my @alias_expand = split(/\s+/, $aliases{$cmd_name});
          $run_cmd_name = shift @alias_expand;
          splice(@args, 1, 0, @alias_expand);
        }

        $run_cmd_name = uniq_abbrev([keys %commands], $run_cmd_name) if
            !$commands{$run_cmd_name} && $self->{settings}{abbrev};

        if ($commands{$run_cmd_name}) {
            my $cmd = $commands{$run_cmd_name};
            if ($self->ok_for_running($cmd, $run_cmd_name, scalar(@args)-1)) {
                # Get part of string after command name
                my $cmd_argstr = substr($current_command, length($cmd_name));
                $self->{cmd_argstr} = $cmd_argstr;
                $cmd->run(\@args);
                $self->{last_command} = $current_command;
            }
            return;
        }
    }

    # Eval anything that's not a command or has been
    # requested to be eval'd
    $self->undefined_command($cmd_name);
    return;
}

# Error message when a command doesn't exist
sub undefined_command($$) {
    my ($self, $cmd_name) = @_;
    my $msg = sprintf 'Undefined command: "%s". Try "help".', $cmd_name;
    eval { $self->errmsg($msg); };
    print STDERR $msg  if $EVAL_ERROR;
}

unless (caller) {
    my $proc  = Devel::Trepan::BWProcessor->new;
    print $proc->{class}, "\n";
    print join(', ', @{$proc->{interfaces}}), "\n";
#     $proc->msg("Hi, there!");
#     $proc->errmsg(['Two', 'lines']);
#     $proc->errmsg("Something wrong?");
#     for my $fn (qw(errmsg msg section)) { 
#         $proc->$fn('testing');
#     }
#     $DB::level = 1;
#     my $prompt = $proc->{prompt} = compute_prompt($proc);
#     eval <<'EOE';
#     sub foo() {
#         my @call_values = caller(0);
#         return @call_values;
#     }
# EOE
#     $DB::level = 2;
#     print "prompt setting 2: $prompt\n";
#     my @call_values = foo();
#     ## $proc->frame_setup(\@call_values, 0);
#     my $sep = '=' x 40 . "\n";
#     $proc->undefined_command("foo");
#     print $sep;
#     $proc->run_command("help *");
#     print $sep;
#     $proc->run_command("help help;; kill 100");
#     # Note kill 100 is in queue - not run yet.
#     if (scalar(@ARGV) > 0 && $proc->{interfaces}[-1]->is_interactive) {
#         $proc->process_command_and_quit; # Handle's queued command
#         $proc->process_command_and_quit;
#         print $sep;
#         $proc->process_commands([@call_values], 0, 'debugger-call');
#     }
}

1;