#!/usr/bin/env perl
#===============================================================================
#
#         FILE: post_new_versions.pl
#
#        USAGE: ./post_new_versions.pl
#
#  DESCRIPTION: Uses HTTP POST to add new versions to Bugzilla
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: David Lawrence (dkl@mozilla.com),
# ORGANIZATION: Mozilla, Inc.
#      VERSION: 1.0
#      CREATED: 01/07/2015 01:58:02 PM
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use utf8;

use LWP::UserAgent;
my $lwp = LWP::UserAgent->new;

my $username = shift;
my $password = shift;

use constant URL     => "https://bugzilla.mozilla.org/editversions.cgi";
use constant PRODUCT => 'Community Tools';

if (!$username || !$password) {
    die "Please provide username and password as arguments";
}

foreach my $version (<DATA>) {
    $version =~ s/^\s+//;
    $version =~ s/\s+$//;
    next if !$version;

    print "Adding $version...";

    my $form_data = {
        Bugzilla_login    => $username,
        Bugzilla_password => $password,
        action            => 'add',
        product           => PRODUCT,
    };

    # First we need to get a valid token
    my $response = $lwp->post(URL, $form_data);
    if (!$response->is_success) {
        die $response->status_line;
    }

    my $content = $response->decoded_content;
    my ($token) = $content =~ /name="token" value="([^"]+)"/;

    # Now submit the new data
    $form_data->{token}   = $token;
    $form_data->{action}  = 'new';
    $form_data->{version} = $version;
    $response = $lwp->post(URL, $form_data);
    if (!$response->is_success) {
        die $response->status_line;
    }

    print "done.\n";
}

exit(0);

__DATA__
2015-1.1
2015-1.2
2015-1.3
2015-1.4
2015-1.5
2015-1.6
2015-2.1
2015-2.2
2015-2.3
2015-2.4
2015-2.5
2015-2.6
2015-3.1
2015-3.2
2015-3.3
2015-3.4
2015-3.5
2015-3.6
2015-4.1
2015-4.2
2015-4.3
2015-4.4
2015-4.5
2015-4.6
2015-5.1
2015-5.2
2015-5.3
2015-5.4
2015-5.5
2015-5.6
2015-6.1
2015-6.2
2015-6.3
2015-6.4
2015-6.5
2015-6.6
2015-7.1
2015-7.2
2015-7.3
2015-7.4
2015-7.5
2015-7.6
2015-8.1
2015-8.2
2015-8.3
2015-8.4
2015-8.5
2015-8.6
2015-9.1
2015-9.2
2015-9.3
2015-9.4
2015-9.5
2015-9.6
2015-10.1
2015-10.2
2015-10.3
2015-10.4
2015-10.5
2015-10.6
2015-11.1
2015-11.2
2015-11.3
2015-11.4
2015-11.5
2015-11.6
2015-12.1
2015-12.2
2015-12.3
2015-12.4
2015-12.5
2015-12.6
