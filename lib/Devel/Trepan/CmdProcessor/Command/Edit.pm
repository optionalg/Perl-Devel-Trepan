# Copyright (C) 2011-2012 Rocky Bernstein <rocky@cpan.org>
use warnings; no warnings 'redefine';
use rlib '../../../..';

use Devel::Trepan::DB::LineCache;
use Devel::Trepan::DB::Sub;

package Devel::Trepan::CmdProcessor::Command::Edit;
use if !@ISA, Devel::Trepan::CmdProcessor::Command ;
unless (@ISA) {
    eval <<"EOE";
use constant ALIASES    => ('e');
use constant CATEGORY   => 'files';
use constant SHORT_HELP => 'Invoke an editor on some source code';
use constant NEED_STACK => 0;
use constant MIN_ARGS   => 0;  # Need at least this many
use constant MAX_ARGS   => 2;  # Need at most this many - undef -> unlimited.
EOE
}

use strict;
our @ISA = @CMD_ISA;  # value inherited from parent
use vars @CMD_VARS;   # value inherited from parent

our $NAME = set_name();
=pod

=head2 Synopsis:

=cut
our $HELP = <<"HELP";
=pod

B<edit> [[I<file>] [I<line>]]

With no argument, edits file containing most recent line listed.
The value of the environment variable I<EDITOR> is used for the
editor to run. If no I<EDITOR> environment variable is set /bin/ex
is used. The editor should support line and file positioning via

   editor-name +line file-name

(Most editors do.)

=head2 Examples:

   edit            # Edit current location
   edit 7          # Edit current file at line 7
   edit test.rb    # Edit test.rb, line 1
   edit test.rb 10 # Edit test.rb  line 10
=cut
HELP

# FIXME: include line numbers. Should we include all files?
# Combine with BREAK completion.
sub complete($$)
{
    my ($self, $prefix) = @_;
    my @completions = sort ('.', DB::LineCache::file_list());
    Devel::Trepan::Complete::complete_token(\@completions, $prefix);
}

# This method runs the command
sub run($$)
{
    my ($self, $args) = @_;
    my $proc = $self->{proc};
    my ($filename, $line_number);
    my $count = scalar @$args;
    if (1 == $count) {
        if ($proc->{terminated}) {
            $proc->msg_need_running("implicit edit file and line");
            return;
        }
        $filename     = $self->{proc}->filename;
        $line_number  = $self->{proc}->line;
    } elsif (2 == $count) {
        $line_number = $self->{proc}->get_int_noerr($args->[1]);
        if (defined $line_number) {
            if ($proc->{terminated}) {
                $proc->msg_need_running("implicit edit file");
                return;
            }
            $filename = $self->{proc}->filename;
        } else {
            $filename = $args->[1];
            $line_number = 1;
        }
    } elsif (3 == $count) {
        ($line_number, $filename) =  ($args->[2], $args->[1]);
    } else {
        $self->errmsg("edit needs at most 2 args.");
        return;
    }
    my $editor = $ENV{'EDITOR'} || '/bin/ex';
    if ( -r $filename ) {
        use File::Basename;
        $filename = basename($filename) if $self->{proc}{settings}{basename};
        my @edit_cmd = ($editor, "+$line_number", $filename);
        $self->{proc}->msg(sprintf "Running: %s...", join(' ', @edit_cmd));
        system(@edit_cmd);
        $self->{proc}->msg("Warning: return code was $?") if $? != 0;
    } else {
        $self->errmsg("File \"${filename}\" is not readable.");
    }
}

unless (caller) {
    require Devel::Trepan::CmdProcessor::Mock;
    my $proc = Devel::Trepan::CmdProcessor->new(undef, 'bogus');
    my $cmd = __PACKAGE__->new($proc);
    my $frame_ary = Devel::Trepan::CmdProcessor::Mock::create_frame();
    $proc->frame_setup($frame_ary);

    $cmd->run([$NAME]);
    $cmd->run([$NAME, '7']);
    $cmd->run([$NAME, __FILE__, '10']);
}

1;
