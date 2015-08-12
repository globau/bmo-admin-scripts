#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

# adds milestones and versions for the rapid-release merge-day.

use HTTP::Cookies;
use LWP::Simple qw($ua get);
use URI::Escape;
use XMLRPC::Lite;
$| = 1;

use Data::Dumper;
$Data::Dumper::Terse = 1;
$Data::Dumper::Sortkeys = 1;

use constant URL_BASE   => 'https://bugzilla.mozilla.org/';

use constant MILESTONES => (
    'Add-on SDK',
    'Android Background Services',
    'Core',
    'Firefox',
    'Firefox for Android',
    'Firefox Health Report',
    'Loop',
    'MailNews Core',
    'Mozilla QA',
    'Mozilla Localizations',
    'Mozilla Services',
    'Other Applications',
    'Taskcluster',
    'Testing',
    'Thunderbird',
    'Toolkit',
);

use constant VERSIONS => (
    'Android Background Services',
    'Core',
    'Firefox',
    'Firefox for Android',
    'Firefox Health Report',
    'MailNews Core',
    'Mozilla QA',
    'Tech Evangelism',
    'Testing',
    'Thunderbird',
    'Toolkit',
);

#
# confirmation
#

my $train = shift
    or die "syntax: $0 (version) [username] [password]\neg. $0 24\n";
$train =~ /\D/
    and die "invalid version '$train'\n";

printf <<EOF, ($train + 2);
About to add milestones and versions for version '$train'.
  Milestones: %s
  Versions  : $train
Press <return> to continue, or ctrl+c to cancel
EOF
<STDIN>;

#
# login
#

my $username = shift || 'glob@mozilla.com';
my $password = shift;
if (!$password) {
    printf "password for %s: ", $username;
    $password = <>;
    chomp($password);
}

print "Logging in to " . URL_BASE . "..\n";
rpc(
    'User.login', {
        login       => $username,
        password    => $password,
        remember    => 1,
    });

#
# milestones
#

sub _milestone {
    my ($milestones, $value) = @_;
    foreach my $ms (@$milestones) {
        return $ms if $ms->{milestone} eq $value;
    }
    return undef;
}

print "\nMILESTONES\n\n";

foreach my $product (MILESTONES) {
    my $milestones = [];

    print "$product\n";
    my $html = web(URL_BASE . 'editmilestones.cgi?product=' . uri_escape($product));

    # add $train + 2
    # move --- between $train-1 and $train

    # scrape from admin html
    while ($html =~
        m#
            <tr>[^<]+
            <td\s>[^<]+
            <a\shref="editmilestones\.cgi\?action=edit[^"]+">([^<]+)</a>[^<]+
            </td>[^<]+
            <td\s>([^<]+)</td>[^<]+
            <td\s>([^<]+)</td>[^<]+
        #gx)
    {
        my ($milestone, $sortkey, $active) = (trim($1), trim($2), trim($3));
        next unless $active eq 'Yes';
        push @$milestones, {
            milestone   => $milestone,
            sortkey     => $sortkey,
        };
    }
    if (!@$milestones) {
        print "failed to find any milestones for '$product'\n";
        next;
    }

    # determine scheme
    my $scheme;
    foreach my $template ('mozilla%s', 'Firefox %s', 'Thunderbird %s.0', '%s') {
        my $check = sprintf($template, $train + 1);
        foreach my $rh (@$milestones) {
            next unless $rh->{milestone} eq $check;
            $scheme = $template;
            last;
        }
        last if $scheme;
    }
    die "failed to determine milestone scheme\n"
        unless $scheme;

    # determine sort increment
    my $current = _milestone($milestones, sprintf($scheme, $train - 1))
        or die "failed to find '" . ($train - 1) . "' milestone (scheme $scheme)\n";
    my $prior = _milestone($milestones, sprintf($scheme, $train - 2))
        or die "failed to find '" . ($train - 2) . "' milestone (scheme $scheme)\n";
    my $inc = $current->{sortkey} - $prior->{sortkey};

    my $new = sprintf($scheme, $train + 2);

    # check for existing
    my $exists;
    foreach my $rh (grep { $_->{milestone} eq $new } @$milestones) {
        $exists = 1;
        last;
    }
    if ($exists) {
        print "  '$new' exists\n";
    }

    # find --- marker
    my $default;
    foreach my $rh (grep { $_->{milestone} eq '---' } @$milestones) {
        $default = $rh;
        last;
    }

    if (!$exists) {
        my $sortkey = _milestone($milestones, sprintf($scheme, $train))->{sortkey} + ($inc * 2);
        add_milestone($product, $new, $sortkey);
    }

    if ($default->{sortkey}) {
        printf "  YOU NEED TO move --- to %s\n", $default->{sortkey} + $inc;
        printf "  https://bugzilla.mozilla.org/editmilestones.cgi?action=edit&product=%s&milestone=---\n",
            uri_escape($product);
        # TODO
    }
}

sub add_milestone {
    my ($product, $milestone, $sortkey) = @_;
    print "  adding '$milestone' ($sortkey)\n";

    my $html = web(URL_BASE . 'editmilestones.cgi?action=add&product=' . uri_escape($product));
    my ($token) = $html =~ /name="token" value="([^"]+)"/;
    $token
        or die "failed to find token for editmilestones.cgi?action=add\n";

    my $res = $ua->post(
        URL_BASE . 'editmilestones.cgi',
        [
            milestone   => $milestone,
            sortkey     => $sortkey,
            action      => 'new',
            product     => $product,
            token       => $token,
        ]
    );
    die "milestone creation failed\n" . $res->as_string
        unless $res->content =~ /<title>Milestone Created<\/title>/;
}

sub edit_milestone {
    # load edit page, grab token, post
die "not implemented";
    my ($product, $current_milestone, $new_milestone, $sortkey) = @_;
    print "  editing '$current_milestone' ($sortkey)\n";

    my $html = web(URL_BASE . 'editmilestones.cgi?action=add&product=' . uri_escape($product));
    my ($token) = $html =~ /name="token" value="([^"]+)"/;
    $token
        or die "failed to find token for editmilestones.cgi?action=add\n";

    my $res = $ua->post(
        URL_BASE . 'editmilestones.cgi',
        [
            milestone   => $current_milestone,
            sortkey     => $sortkey,
            action      => 'new',
            product     => $product,
            token       => $token,
        ]
    );
    die "milestone creation failed\n" . $res->as_string
        unless $res->content =~ /<title>Milestone Created<\/title>/;
}

#
# versions
#

print "\nVERSIONS\n\n";

foreach my $product (VERSIONS) {
    my $versions = [];

    print "$product\n";
    my $html = web(URL_BASE . 'editversions.cgi?product=' . uri_escape($product));

    # add $train

    # scrape from admin html
    while ($html =~
        m#
            <tr>[^<]+
            <td\s>[^<]+
            <a\shref="editversions\.cgi\?action=edit[^"]+">([^<]+)</a>[^<]+
            </td>[^<]+
            <td\s>([^<]+)</td>[^<]+
        #gx)
    {
        my ($version, $active) = (trim($1), trim($2));
        next unless $active eq 'Yes';
        push @$versions, $version;
    }
    if (!@$versions) {
        print "failed to find any versions for '$product'\n";
        next;
    }

    # determine scheme
    my $scheme;
    foreach my $template ('%s Branch', 'Firefox %s', '%s') {
        my $check = sprintf($template, $train - 1);
        foreach my $version (@$versions) {
            next unless $version eq $check;
            $scheme = $template;
            last;
        }
        last if $scheme;
    }
    die "failed to determine version scheme\n"
        unless $scheme;

    my $new = sprintf($scheme, $train);

    # check for existing
    if (grep { $_ eq $new } @$versions) {
        print "  '$new' exists\n";
        next;
    }

    add_version($product, $new);
}

sub add_version {
    my ($product, $version) = @_;
    print "  adding '$version'\n";

    my $html = web(URL_BASE . 'editversions.cgi?action=add&product=' . uri_escape($product));
    my ($token) = $html =~ /name="token" value="([^"]+)"/;
    $token
        or die "failed to find token for editversions.cgi?action=add\n";

    my $res = $ua->post(
        URL_BASE . 'editversions.cgi',
        [
            version     => $version,
            action      => 'new',
            product     => $product,
            token       => $token,
        ]
    );
    die "version creation failed\n" . $res->as_string
        unless $res->content =~ /<title>Version Created<\/title>/;
}

#
# helpers
#

my ($_rpc, $_cookies);

sub rpc {
    my ($method, $params) = @_;
    my $soapresult;
    eval {
        $_cookies ||= HTTP::Cookies->new();
        $_rpc ||= XMLRPC::Lite->proxy(URL_BASE . 'xmlrpc.cgi', cookie_jar => $_cookies);
        $soapresult = $_rpc->call($method, $params);
        if ($soapresult->fault) {
            my ($package, $filename, $line) = caller;
            die $soapresult->faultcode . ' ' . $soapresult->faultstring .
                " in SOAP call near $filename line $line.\n";
        }
        $ua->cookie_jar($_cookies);
    };
    if ($@) {
        print $@;
        exit;
    }
    return $soapresult->result;
}

sub web {
    my ($url) = @_;
    my $html;
    my $count = 0;
    $ua->timeout(15);
    while (!$html && $count <= 5) {
        $count++;
        print "\r$url ($count)\033[K";
        $html = get($url);
    }
    $html or die "\n$url failed: $!\n";
    print "\r\033[K";
    $ua->timeout(3 * 60);
    return $html;
}

sub trim {
    my ($value) = @_;
    $value =~ s/(^\s+|\s+$)//g;
    return $value;
}
