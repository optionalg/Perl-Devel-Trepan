# -*- coding: utf-8 -*-
# Copyright (C) 2012-2015 Rocky Bernstein <rocky@cpan.org>
use strict; use warnings; use utf8;
use rlib '../../..';
use Devel::Trepan::DB::LineCache; # for map_file
use Devel::Trepan::Complete;

package Devel::Trepan::Processor;

use vars qw(@EXPORT @ISA);
@EXPORT    = qw( adjust_frame );
@ISA = qw(Exporter);

use English qw( -no_match_vars );

sub adjust_frame($$$)
{
    my ($self, $frame_num, $absolute_pos) = @_;
    my $frame;
    ($frame, $frame_num) = $self->get_frame($frame_num, $absolute_pos);
    if ($frame) {
        $self->{frame} = $frame;
        $self->{frame_index} = $frame_num;
        unless ($self->{settings}{traceprint}) {
            my $opts = {
                basename    => $self->{settings}{basename},
                current_pos => $frame_num,
                maxwidth    => $self->{settings}{maxwidth},
                displayop   => $self->{settings}{displayop},
            };
            $self->print_stack_trace_from_to($frame_num, $frame_num, $self->{frames}, $opts);
            $self->print_location ;
        }
        $self->{list_line} = $self->line();
        $self->{list_filename} = $self->filename();
        $self->{frame};
    } else {
        undef
    }
}

sub frame_low_high($;$)
{
    my ($self, $direction) = @_;
    $direction = 1 unless defined $direction;
    my $stack_size = $self->{stack_size};
    my ($low, $high) = (-$stack_size, $stack_size-1);
    ($low, $high) = ($high, $low) if ($direction < 0);
    return ($low, $high);
}

sub frame_setup($$)
{
    my ($self, $frame_aref) = @_;

    if (defined $frame_aref) {
        $self->{frames} = $frame_aref;
        $self->{stack_size}    = $#{$self->{frames}}+1;
    } else {
        ### FIXME: look go over this code.
	# $stack_size contains the stack ignoring frames
	# of this debugger.
        my $stack_size = $DB::stack_depth;
        my @frames = $self->{dbgr}->tbacktrace(0);
        @frames = splice(@frames, 2) if $self->{dbgr}{caught_signal};

        if ($self->{event} eq 'post-mortem') {
            $stack_size = 0;
            for my $frame (@frames) {
                next unless defined($frame) && exists($frame->{file});
                $stack_size ++;
            }
        } else {

	    # Figure out how many frames this debugger put in.
	    my $debugger_frames_to_skip=0;
            while (my ($pkg, $file, $line, $fn) =
		   caller($debugger_frames_to_skip++)) {
                last if 'DB::DB' eq $fn or ('DB' eq $pkg && 'DB' eq $fn);
            }

	    # Dynamic debugging might not have set $DB::stack_depth
	    # correctly. So we'll doublecheck it here.
	    # $stack_size_with_debugger contains the stack depth
	    # *including* frames added by this debugger.
	    my $stack_size_with_debugger = $debugger_frames_to_skip;
	    $stack_size_with_debugger++ while defined caller($stack_size_with_debugger);

	    # Adjust for the fact that caller starts at 0;
	    $stack_size_with_debugger++;

	    my $computed_stack_depth =
		$stack_size_with_debugger - $debugger_frames_to_skip;

	    # printf("+++ debugger_frames_to_skip: %d, stack_size_with_debugger %d\n",
	    # 	   $debugger_frames_to_skip, $stack_size_with_debugger);
	    # printf("+++ computed_stack_depth: %d DB::stack_depth\n", $computed_stack_depth, $DB::stack_depth);
	    # use Carp qw(cluck); cluck('testing');

	    if ((!defined $DB::stack_depth
		 or $DB::stack_depth < $computed_stack_depth)
		and !$self->{gave_stack_trunc_warning}) {
		$self->errmsg(
		    "Call stack depth recorded in DB module is short. We've adjusted it.");
		$self->{gave_stack_trunc_warning} = 1;
	    }
	    $stack_size = $computed_stack_depth;
	    $stack_size++ if $self->{event} eq 'call';
        }
        $self->{frames} = \@frames;
        $self->{stack_size}    = $stack_size;
    }

    $self->{frame_index}   = 0;
    $self->{hide_level}    = 0;
    $self->{frame}         = $self->{frames}[0];
    $self->{list_line}     = $self->line();
    $self->{list_filename} = $self->filename();
}

sub filename($)
{
    my $self = shift;
    my $filename = $self->{frame}{file};
    if (filename_is_eval($filename)) {
	return $filename;
    } else {
	return map_file($filename);
    }
}

sub funcname($)
{
    my $self = shift;
    $self->{frame}{fn};
}

sub get_frame($$$)
{
    my ($self, $frame_num, $absolute_pos) = @_;
    my $stack_size = $self->{stack_size};

    if ($absolute_pos) {
        $frame_num += $stack_size if $frame_num < 0;
    } else {
        $frame_num += $self->{frame_index};
    }

    if ($frame_num < 0) {
        $self->errmsg('Adjusting would put us beyond the newest frame.');
        return (undef, undef);
    } elsif ($frame_num >= $stack_size) {
        $self->errmsg('Adjusting would put us beyond the oldest frame.');
        return (undef, undef);
    }

    my $frames = $self->{frames};
    unless ($frames->[$frame_num]) {
        my @new_frames = $self->{dbgr}->tbacktrace(0);
        $self->{frames}[$frame_num] = $new_frames[$frame_num];
    }
    $self->{frame} = $frames->[$frame_num];
    return ($self->{frame}, $frame_num);
}

sub line($)
{
    my $self = shift;
    $self->{frame}{line};
}

sub print_stack_entry()
{
    die "This should have been implemented somewhere else"
}

sub print_stack_trace_from_to($$$$$)
{
    die "This should have been implemented somewhere else"
}

# Print `count' frame entries
sub print_stack_trace($$$)
{
    die "This should have been implemented somewhere else"
}

1;
