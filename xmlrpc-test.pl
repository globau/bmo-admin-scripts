#!/usr/bin/perl -w
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

use strict;
use warnings;
use 5.10.1;

use Cwd qw(abs_path);
use File::Basename;
use FindBin qw($RealBin);
use Getopt::Lucid qw(:all);
use HTTP::Cookies;
use SOAP::Lite;
use Sys::Hostname qw(hostname);
use XMLRPC::Lite;

use Data::Dumper;
$Data::Dumper::Terse = 1;
$Data::Dumper::Sortkeys = 1;

my $opt = Getopt::Lucid->getopt([
    Param('username|user|u')->default('glob@example.com'),
    Param('password|pass|p')->default('secret'),
    Param('api_key|key|k'),
    Param('token|t'),
    Param('url')->default('http://' . hostname() . '/%s/xmlrpc.cgi'),
    Switch('pretty_xml|pretty-xml|x'),
])->validate;

if ($opt->get_api_key) {
    bugzilla('api_key', $opt->get_api_key);
} elsif ($opt->get_token) {
    bugzilla('token', $opt->get_token);
} else {
    bugzilla(
        'User.login', {
            login    => $opt->get_username,
            password => $opt->get_password,
            remember => 1,
        }
    );
}

bugzilla(
    'Bug.get', {
        ids => [ 999 ],
    }
);

#
# helpers
#

sub _debug_transport {
    my $r = shift;
    (my $content = $r->as_string) =~ s/\n*$/\n/;
    if ($opt->get_pretty_xml) {
        my ($header, $body) = $content =~ /^(.+\n\n)(.+)$/s;
        eval {
            eval 'use XML::LibXML';
            $content = $header . XML::LibXML->new->load_xml(string => $body)->toString(1);
        };
    }
    if ($r->isa('HTTP::Request')) {
        print ">>>\n$content>>>\n";
    } elsif ($r->isa('HTTP::Response')) {
        print "<<<\n$content<<<\n";
    } else {
        die;
    }
    return undef;
}

sub bugzilla {
    my ($method, $params, $token) = @_;
    state $rpc;
    my @auth_fields = qw(api_key token);

    if (grep { $_ eq $method } @auth_fields) {
        $rpc->{$method} = $params;
        return;
    }

    $rpc->{cookie_jar} //= HTTP::Cookies->new( ignore_discard => 1 );
    if (!$rpc->{proxy}) {
        my $dir = _find_base_directory('.')
            or _find_base_directory($RealBin)
            or die "failed to find working environment\n";
        $rpc->{proxy} = XMLRPC::Lite->proxy(
            sprintf($opt->get_url, $dir),
            cookie_jar => $rpc->{cookie_jar},
        );
        foreach my $handler (qw( request_send response_done )) {
            $rpc->{proxy}->transport->set_my_handler( $handler => \&_debug_transport );
        }
    }
    foreach my $field (@auth_fields) {
        $params->{$field} = $rpc->{$field} if $rpc->{$field};
    }

    my $soapresult;
    eval {
        $soapresult = $rpc->{proxy}->call($method, $params);
        if ($soapresult->fault) {
            my ($package, $filename, $line) = caller;
            die $soapresult->faultcode . ' ' . $soapresult->faultstring .
                " in SOAP call near $filename line $line.\n";
        }
    };
    if ($@) {
        print $@;
        exit;
    }
    $rpc->{token} = $soapresult->result->{token}
        if $method eq 'User.login';
    return $soapresult->result;
}

sub _find_base_directory {
    my ($path) = @_;
    $path = abs_path($path);
    while (1) {
        return '' if $path eq '' || $path eq '/';
        return basename($path) if -e "$path/localconfig";
        $path = abs_path("$path/..");
    }
}
