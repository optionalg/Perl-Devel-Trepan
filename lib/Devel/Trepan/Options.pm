# Copyright (C) 2011-2013 Rocky Bernstein <rocky@cpan.org>
use strict;
use warnings;
package Devel::Trepan::Options;
use Getopt::Long qw(GetOptionsFromArray);
use Pod::Usage;
use Pod::Find qw(pod_where);
use File::Spec;
use File::HomeDir;

use vars qw(@EXPORT $DEFAULT_OPTIONS $PROGRAM_NAME);
@EXPORT = qw( process_options whence_file $DEFAULT_OPTIONS $PROGRAM_NAME);
our @ISA;

BEGIN {
    $PROGRAM_NAME = 'trepan.pl';
    my @OLD_INC = @INC;
    use rlib '../..';
    use Devel::Trepan::Version;
    @INC = @OLD_INC;
}

use constant PROGRAM_NAME => $PROGRAM_NAME;

@ISA    = qw(Exporter);

# Return whether we want Terminal highlighting by default
sub default_term() {
    ($ENV{'TERM'} && ($ENV{'TERM'} ne 'dumb' ||
                     (exists($ENV{'EMACS'}) && $ENV{'EMACS'} eq 't')))
        ?  'term' : 0
}

my $HOME = File::HomeDir->my_home;
my $initfile = File::Spec->catfile($HOME, '.treplrc');
$DEFAULT_OPTIONS = {
    basename     => 0,
    batchfile    => undef,
    cmddir       => [],      # Additional directories of debugger commands
    cmdfiles     => [],      # Files containing debugger commands to 'source'
    exec_strs    => [],      # Perl strings to evaluate
    fall_off_end => 0,       # Don't go into debugger on termination?
    highlight    => default_term(),
                           # Default values used only when 'server' or 'client'                            # (out-of-process debugging)
    host         => 'localhost',
    initfile     => $initfile,
    initial_dir  => undef, # If --cd option was given, we save it here.
    nx           => 0,     # Don't run user startup file (e.g. .treplrc)
    port         => 1954,
    post_mortem  => 0,       # Go into debugger on die?
    readline     => 1,       # Try to use GNU Readline?
    testing      => undef,
    traceprint   => 0,       # set -x tracing?

};

sub show_version()
{
    printf "$PROGRAM_NAME, version %s\n", $Devel::Trepan::Version::VERSION;
    exit 10;
}

sub check_tcp_opts($$) {
    my ($server_client, $opts) = @_;
    $opts->{port} ||= $DEFAULT_OPTIONS->{port};
    $opts->{host} ||= $DEFAULT_OPTIONS->{host};
}

sub check_tty_opts($$) {
    my ($server_client, $opts) = @_;
}

sub check_protocol($)
{
    my ($opts) = @_;
    if ($opts->[0] ne 'tcp' && $opts->[0] ne 'tty') {
	print STDERR
	    "Protocol should be either 'tcp' or 'tty': got '$opts->[0]'\n";
	$opts->[0] = 'tcp';
    }
}

sub parse_client_server_opts($$)
{
    my ($server_client, $opts) = @_;
    if (scalar @$opts == 1) {
	if (!$opts->[0]) {
	    $opts->[0] = 'tcp';
	}
	check_protocol($opts);
    } elsif (scalar @$opts == 2) {
	check_protocol($opts);
	if ($opts->[0] == 'tcp'){
	    check_tcp_opts($server_client, $opts);
	} else {
	    check_tty_opts($server_client, $opts);
	}
    }
}

sub process_options($)
{
    $Getopt::Long::autoabbrev = 1;
    my ($argv) = @_;
    my ($show_version, $help, $man);
    my $opts = $DEFAULT_OPTIONS;

    my $result = &GetOptionsFromArray($argv,
         'basename'      => \$opts->{basename},
         'batch:s'       => \$opts->{batchfile},
         'bw'            => \$opts->{bw},
         'cd:s'          => \$opts->{initial_dir},
         'client=s@{0,3}' => \$opts->{client},
         'cmddir=s@'      => \$opts->{cmddir},
         'command=s@'     => \$opts->{cmdfiles},
         'e|exec=s@'      => \$opts->{exec_strs},
         'fall-off-end'   => \$opts->{fall_off_end},
         'help'           => \$help,
         'highlight'      => \$opts->{highlight},
         'man'            => \$man,
         'no-highlight'   => sub { $opts->{highlight} = 0},
         'no-readline'    => sub { $opts->{readline} = 0},
         'nx'             => \$opts->{nx},
         'post-mortem'    => \$opts->{post_mortem},
         'readline'       => \$opts->{readline},
         'server=s@{0,3}' => \$opts->{server},
         'testing:s'      => \$opts->{testing},
         'version'        => \$show_version,
         'x|trace'        => \$opts->{traceprint},
        );

    pod2usage(-input => pod_where({-inc => 1}, __PACKAGE__),
              -exitstatus => 1) if $help;
    pod2usage(-exitstatus => 10, -verbose => 2,
              -input => pod_where({-inc => 1}, __PACKAGE__)) if $man;
    show_version() if $show_version;
    chdir $opts->{initial_dir} || die "Can't chdir to $opts->{initial_dir}" if
        defined($opts->{initial_dir});
    my $batch_filename = $opts->{testing};
    $batch_filename = $opts->{batchfile} unless defined $batch_filename;
    if ($batch_filename) {
        if (scalar(@{$opts->{cmdfiles}}) != 0) {
            printf(STDERR "--batch option disables command files: %s\n",
                   join(', ', @{$opts->{cmdfiles}}));
            $opts->{cmdfiles} = [];
        }
        $opts->{nx} = 1;
    }
    if ($opts->{server} and $opts->{client}) {
        printf STDERR
            "Pick only on from of the --server or --client options\n";
    } else {
	# use Enbugger 'trepan'; Enbugger->stop;
	# $opts->{server} = ['tcp'];
	if ($opts->{server}) {
	    parse_client_server_opts('server', $opts->{server});
	} elsif ($opts->{client}) {
	    parse_client_server_opts('client', $opts->{client})
	}
    }

    $opts;
}

# Do a shell-like path lookup for prog_script and return the results.
# If we can't find anything return the string given.
sub whence_file($)
{
    my $prog_script = shift;

    # If we have an relative or absolute file name, don't do anything.
    return $prog_script if
        File::Spec->file_name_is_absolute($prog_script);
    my $first_char = substr($prog_script, 0, 1);
    return $prog_script if index('./', $first_char) != -1;

    for my $dirname (File::Spec->path()) {
        my $prog_script_try = File::Spec->catfile($dirname, $prog_script);
        return $prog_script_try if -r $prog_script_try;
    }
    # Failure
    return $prog_script;
}

unless (caller) {
    my $argv = \@ARGV;
    my $opts = process_options($argv);
    printf "whence file for perl: %s\n", whence_file('perl');
    require Data::Dumper;
    import Data::Dumper;
    # print Dumper($opts), "\n";
    my $pid = fork();
    # if ($pid == 0) {
    #     my @argv = qw(--version);
    #     my $opts = process_options(\@argv);
    #     exit 0;
    # } else {
    #     waitpid($pid, 0);
    #     print "exit code: ", $?>>8, "\n";
    # }
    # $pid = fork();
    # if ($pid == 0) {
    #     my @argv = qw(--cd /tmp --cmddir /tmp);
    #     my $opts = process_options(\@argv);
    #     print Dumper($opts), "\n";
    #     exit 0;
    # } else {
    #     waitpid($pid, 0);
    #     print "exit code: ", $?>>8, "\n";
    # }
    # exit;
    # $pid = fork();
    # if ($pid == 0) {
    #     my @argv = qw(--cd /bogus);
    #     my $opts = process_options(\@argv);
    #     exit 0
    # } else {
    #     waitpid($pid, 0);
    #     print "exit code: ", $?>>8, "\n";
    # }
    # $pid = fork();
    # if ($pid == 0) {
    #     my @argv = ('--batch', __FILE__);
    #     my $opts = process_options(\@argv);
    #     print Dumper($opts), "\n";
    #     exit 0
    # } else {
    #     waitpid($pid, 0);
    #     print "exit code: ", $?>>8, "\n";
    # }

    # $pid = fork();
    if ($pid == 0) {
        my @argv = ('--server', '--', __FILE__);
        my $opts = process_options(\@argv);
        print Dumper($opts), "\n";
        exit 0
    } else {
        waitpid($pid, 0);
        print "exit code: ", $?>>8, "\n";
    }

}

1;

__END__

=head1 TrepanPl

trepan.pl - Perl "Trepanning" Debugger

=head1 SYNOPSIS

   trepan.pl [options] [[--] perl-program [perl-program-options ...]]

   Options:
      --help               brief help message
      --man                full documentation
      --basename           Show basename only on source file listings.
                           (Needed in regression tests)
      --bw                 Use Bullwinkle Processor (for front-ends) rather
                           that the command-line processor
      -c| --command FILE   Run or 'source' debugger command file FILE
      --cmddir DIR         Read DIR for additional debugger commands
      --batch FILE         Like --command, but quit after reading FILE.
                           This option has precidence over --command and
                           will also set --nx
      --cd DIR             Change current directory to DIR
      -e| --exec STRING    eval STRING. Multiple -e's can be given.
                           Works like Perl's -e switch
      --nx                 Don't run user startup file (e.g. .treplrc)

      --client {'tcp' host port} | {'tty', input-slave output-slave}
                           Set for out-of-process debugging.
                           The client runs outside of this process.
                           'tcp' uses TCP/IP
                           'tty' uses pseudo tty.

      --server {'tcp' host port} | {'tty'}
                           Set for out-of-process debugging. The server
                           rus the Perl program to be debugged runs.

      --fall-off-end       Don't stay in debugger when program terminates

      --host NAME          Set DNS name or IP address to communicate on.
                           The default is 127.0.0.1

      --post-mortem        Enter debugger on die
      --readline  | --no-readline
                           Try or don't try to use Term::Readline
      -x|--trace           Simulate line tracing (think POSIX shell set -x)
      --highlight | --no-highlight
                           Use or don't use ANSI terminal sequences for syntax
                           highlight

=head1 DESCRIPTION

B<trepan.pl> is a gdb-like debugger. Much of the interface and code has
been adapted from the trepanning debuggers of Ruby.

=cut
