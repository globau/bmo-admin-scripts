#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use 5.10.0;
$| = 1;

# opens editusers.cgi for the specified email addresses.  this avoids the need
# to search for the email address to find the user_id, then click to edit, and
# is most useful when editing multiple users.
#
# syntax:
#   bulk-user-edit
#       without args, you'll be prompted to paste lines which contain the user
#       to edit.
#   bulk-user-edit [dev|stage]
#       if you specify "dev" or "stage" as an arg, the development or staging
#       servers will be used instead of production.
#   bulk-user-edit login@example.com
#       passing one or more address on the command line will work on just those
#       addresses.

use JSON;
use List::MoreUtils 'uniq';
use LWP::Simple;
use URI::Escape;
use Sys::Hostname;

my $url_base = 'https://bugzilla.mozilla.org';
$url_base = 'https://bugzilla-dev.allizom.org' if grep { /\bdev\b/ } @ARGV;
$url_base = 'https://bugzilla.allizom.org' if grep { /\bstage\b/ } @ARGV;

my @list;
foreach my $arg (@ARGV) {
    push @list, $arg if $arg =~ /\@/;
}
if (!@list) {
    undef @ARGV;
    print "paste lines with email addresses, ^D to finish\n";
    @list = <>;
    chomp(@list);
}

my @logins;
foreach (@list) {
    s/(^\s+|\s+$)//g;
    next if $_ eq '';
    my $login;

    if (!/\@/) {
        print "skipping: $_\n";
        next;
    } elsif (/<([^>]+)>/ && $1 =~ /^(.+\@.+\..+)$/) {
        $login = $1;
    } elsif (/\s(\S+\@.+\..+)$/) {
        $login = $1;
        $login =~ s/(^[\(<\[]|[\)>\]]$)//g;
    } elsif (/^.*\(([^\)]+)\)/) {
        $login = $1;
    } elsif (/^([^\@]+\@.+\..+)$/) {
        $login = $1;
    } else {
        print "skipping: $_\n";
        next;
    }
    $login =~ s/^(\S+)\s.*/$1/;
    $login =~ s/^mailto://i;
    $login =~ s/[,\.\)\]\>]+$//;
    push @logins, $login;
}
@logins = uniq sort @logins;

print "\nchecking " . scalar(@logins) . " user" . (scalar(@logins) == 1 ? '' : 's') . "\n";
my @urls;
foreach my $login (@logins) {
    eval {
        my $data = decode_json(get("$url_base/rest/user/" . uri_escape($login)));
        my $id = $data->{users}->[0]->{id};
        push @urls, "$url_base/editusers.cgi?action=edit&userid=$id";
        print "found $login $urls[$#urls]\n";
    };
    if ($@) {
        print "failed to find $login\n";
    }
}
exit unless @urls;

print "\nopening url" . (scalar(@urls) == 1 ? '' : 's') . "..\n";
while (my $url = pop @urls) {
    if (hostname() eq 'bz.glob.com.au') {
        system qq#ssh byron\@mac "open '$url'"#;
    } else {
        system "open '$url'";
    }
    sleep(1) if @urls;
}
