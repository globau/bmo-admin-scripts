#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use 5.10.0;
$| = 1;

# automatically generate "action required" emails from the moco-ldap-check
# emails.
#
# copy the relevant section from the email, then run this script with the
# relevant parameter (run without parameters for help).

use URI::Escape;
use LWP::Simple;
use JSON;

my %modes = (
    deleted => {
        alts    => [qw( del delete )],
        desc    => 'deleted ldap accounts',
        regex   => qr/^(\S+)\s+(.+?) \((\S+)\)$/,
        action  => sub {
            my ($moco_mail, $name, $login) = @_;
            eval {
                my $data = decode_json(get("https://bugzilla.mozilla.org/rest/user/" . uri_escape($login)));
                return "https://bugzilla.mozilla.org/editusers.cgi?action=edit&userid=" . $data->{users}->[0]->{id};
            };
            if ($@) {
                say "failed to find $login";
            }
        },
    },
    wrong   => {
        desc    => 'ldap accounts with wrong bugmail',
        regex   => qr/^(\S+)\s+(.+?) \((\S+) -> (\S+)\)$/,
        action  => sub {
            my ($moco_mail, $name, $bad_login, $good_login) = @_;

            my $subject = 'please update your mozilla phonebook entry';
            my $body_bad_good = <<EOF;
hello %s,

it appears that your "bugzilla email" entry on your phonebook is incorrect.
it has: %s
it probably should be: %s

would it be possible for you to visit https://phonebook.mozilla.org/edit.php and updated your phonebook entry please?

thanks!

-glob
EOF
            chomp($body_bad_good);
            say "$moco_mail ($name) '$bad_login' -> '$good_login'";
            return
                "mailto:$moco_mail" .
                "?subject=" . uri_escape($subject) .
                "&body=" . uri_escape(sprintf($body_bad_good, lc($name), $bad_login, $good_login));
        },
    },
    invalid   => {
        desc    => 'ldap accounts with invalid bugmail',
        regex   => qr/^(\S+)\s+(.+?) \(([^\)]+)\)$/,
        action  => sub {
            my ($moco_mail, $name, $bad_login) = @_;

            my $subject = 'please update your mozilla phonebook entry';
            my $body_bad_good = <<EOF;
hello %s,

it appears that your "bugzilla email" entry on your phonebook is incorrect.
it has "%s" which doesn't appear to exist on bugzilla.mozilla.org.

would it be possible for you to visit https://phonebook.mozilla.org/edit.php and updated your phonebook entry please?

thanks!

-glob
EOF
            chomp($body_bad_good);
            say "$moco_mail ($name) '$bad_login'";
            return
                "mailto:$moco_mail" .
                "?subject=" . uri_escape($subject) .
                "&body=" . uri_escape(sprintf($body_bad_good, lc($name), $bad_login));
        },
    },
);

my $mode = lc(shift || '');
foreach my $m (keys %modes) {
    if (grep { $_ eq $mode } @{ $modes{$m}->{alts} }) {
        $mode = $m;
        last;
    }
}
if (!exists $modes{$mode}) {
    my $syntax = "syntax: moco-ldap-check-email/pl <mode>\n\n";
    foreach my $m (sort keys %modes) {
        $syntax .= sprintf("%7s: %s\n", $m, $modes{$m}->{desc});
    }
    die $syntax;
}

print "paste the '" . $modes{$mode}->{desc} . "' list (end with ^D):\n";
my @lines;
while (1) {
    my $line = <>;
    last unless defined $line;
    chomp($line);
    next unless $line =~ $modes{$mode}->{regex};
    push @lines, $line;
}

foreach my $line (@lines) {
    say "\n$line";
    $line =~ $modes{$mode}->{regex};
    my $url = $modes{$mode}->{action}->($1, $2, $3, $4) // next;
    #say "$url";
    system qq#ssh byron\@mac "open '$url'"#;
}
