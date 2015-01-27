#!/usr/bin/perl
use strict;
use warnings;
use autodie;

# steps for pushing a bmo update
# 1. execute this script, which
#    - updates the repository
#    - determines changes on the master branch but not on production
# 2. use the first url and text to create a push bug
# 3. merge from master --> production
#    - cd /opt/bugzilla/repo/bmo/master
#    - git checkout production
#    - git merge master  # accept the default commit message
#    - git push
#    - git checkout master
# 4. wait for someone to take the bug and follow the push steps in mana
# 5. create a blog post (paste into the "text" tab)
# 6. send an email to tools.bmo
# 7. update the WeeklyUpdates wiki page with selected and edited descriptions
#    (only include changes that are relevant to all/most of the community)
# 8. edit the RecentChanges wiki (add today's push to the top, delete the oldest)
# 9. edit the relevant month's wiki page (add today's push to the top)

use lib '/opt/bz';
use Bz;
use DateTime;
use IPC::System::Simple qw(runx capture);

chdir('/opt/bugzilla/repo/bmo/master');
info("updating repo");
runx(qw(git pull));

my $production_rev = shift;
if (!$production_rev) {
    runx(qw(git checkout production));
    runx(qw(git pull));
    $production_rev = capture(qw(git log -1 --pretty=format:%H));
    runx(qw(git checkout master));
}
my $master_rev = capture(qw(git log -1 --pretty=format:%H));
print "$production_rev -> $master_rev\n";

my @log = capture(qw(git log --oneline), "$production_rev..$master_rev");
die "nothing to commit\n" unless @log;
chomp(@log);

my @revisions;
foreach my $line (@log) {
    print "$line\n";
    unless ($line =~ /^(\S+) (.+)$/) {
        alert("skipping $line");
        next;
    }
    my ($revision, $message) = ($1, $2);

    my @bug_ids;
    if ($message =~ /\bBug (\d+)/i) {
        push @bug_ids, $1;
    }

    if (!@bug_ids) {
        alert("skipping $line (no bug)");
        next;
    }

    foreach my $bug_id (@bug_ids) {
        my $duplicate = 0;
        foreach my $revisions (@revisions) {
            if ($revisions->{bug_id} == $bug_id) {
                $duplicate = 1;
                last;
            }
        }
        next if $duplicate;

        info("loading bug $bug_id");
        my $bug = Bz->bugzilla->bug($bug_id);
        if ($bug->{status} eq 'RESOLVED' && $bug->{resolution} ne 'FIXED') {
            alert("skipping bug $bug_id " . $bug->{summary} . " RESOLVED/" . $bug->{resolution});
            next;
        }
        if ($bug->{summary} =~ /\bbackport\s+(?:upstream\s+)?bug\s+(\d+)/i) {
            my $upstream = $1;
            info("loading upstream bug $upstream");
            $bug->{summary} = Bz->bugzilla->bug($upstream)->{summary};
        }
        unshift @revisions, {
            hash    => $revision,
            bug_id  => $bug_id,
            summary => $bug->{summary},
        };
    }
}
if (!@revisions) {
    die "no new revisions.  make sure you run this script before production is updated.\n";
}

my $first_revision = $revisions[0]->{hash};
my $last_revision  = $revisions[$#revisions]->{hash};

# push bug

print "\n";
print "https://bugzilla.mozilla.org/enter_bug.cgi?product=bugzilla.mozilla.org&component=Infrastructure&short_desc=push+updated+bugzilla.mozilla.org+live\n";
print "can we please get a bmo production push.\n";
print "revisions: $first_revision - $last_revision\n";
foreach my $revision (@revisions) {
    print "bug $revision->{bug_id} : $revision->{summary}\n";
}
print "\n\n";

# blog post

print "https://globau.wordpress.com/wp-admin/post-new.php\n";
print "the following changes have been pushed to bugzilla.mozilla.org:\n<ul>\n";
foreach my $revision (@revisions) {
    printf '<li>[<a href="https://bugzilla.mozilla.org/show_bug.cgi?id=%s" target="_blank">%s</a>] %s</li>%s',
        $revision->{bug_id}, $revision->{bug_id}, html_escape($revision->{summary}), "\n";
}
print "</ul>\n";
print qq#discuss these changes on <a href="https://lists.mozilla.org/listinfo/tools-bmo" target="_blank">mozilla.tools.bmo</a>.\n#;
print "\n\n";

# tools.bmo email

print "the following changes have been pushed to bugzilla.mozilla.org:\n\n";
foreach my $revision (@revisions) {
    printf "https://bugzil.la/%s : %s\n", $revision->{bug_id}, $revision->{summary};
}
print "\n\n";

# weekly updates wiki

print "https://wiki.mozilla.org/WeeklyUpdates\n";
print "==== bugzilla.mozilla.org ====\n";
print "Notable changes to [https://bugzilla.mozilla.org/ bugzilla.mozilla.org] during the last week:\n";
foreach my $revision (@revisions) {
    printf "* {{bug|%s}} %s\n", $revision->{bug_id}, $revision->{summary};
}
print "[[BMO/Recent_Changes|All changes]].\n";
print "\n\n";

# recent changes wiki

print "https://wiki.mozilla.org/BMO/Recent_Changes\n";
print "== " . DateTime->now->set_time_zone('PST8PDT')->ymd('-') . " ==\n";
foreach my $revision (@revisions) {
    printf "* {{bug|%s}} %s\n", $revision->{bug_id}, $revision->{summary};
}
print "\n\n";

sub html_escape {
    my ($s) = @_;
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    return $s;
}
