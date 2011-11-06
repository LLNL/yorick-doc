#!/usr/bin/env perl
use strict;
use warnings;
sub VERSION_MESSAGE { my $fh = shift; print $fh "ydoc.pl version 1.0\n"; }
sub HELP_MESSAGE {
    my $fh = shift;
    print $fh <<EOF;
Usage: perl ydoc.pl [-u] [-n pkgname] [-d ghpath] [srcpath [title]]
  Must run in yorick-doc/ working directory, output to gh-pages/.
    srcpath  path to yorick package source to be documented
    title    title of generated web pages, "Yorick " prepended
    -n pkgname   if pkgname differs from last component of srcpath
    -u       update (or create) gh-pages git branch in srcpath
    -i ghpath  path to substitute for gh-pages git branch
  If srcpath omitted, works from gh-pages/ directory created in a
  previous invocation.  With -u, updates (or creates) gh-pages
  branch in srcpath.  Otherwise, generates html in _site/ from the
  github jekyll source in gh-pages/.
  The -i option allows you to save customizations in an ordinary
  directory (ghpath) instead of in a git gh-pages branch.
EOF
}

BEGIN { die "ydoc.pl: current working directory is not yorick-doc/"
            unless -r "_manual.init"; }

# core modules:  http://perldoc.perl.org/index-modules-A.html
use Getopt::Std qw(getopts);
$Getopt::Std::STANDARD_HELP_VERSION = 1;
use File::Basename qw(basename);
use File::Path qw(remove_tree);
use File::Copy qw(copy);
use File::Find qw(find);
use Cwd;

sub slurp_file($) { local( @ARGV, $/ ) = $_[0]; return <>; }
sub burp_file($$) { open(my $f, '>', $_[0]); print $f $_[1]; close($f); }

my %opts;
my $ok = getopts('un:i:', \%opts);
my $srcpath = shift;
my $pkgtitle = shift;
unless ($ok && not shift) { HELP_MESSAGE(*STDERR); die ""; };
my $pkgname = $opts{'n'};
my $ghpath = $opts{'i'};
my $do_update = $opts{'u'};
my $do_generate = $srcpath;
unless ($srcpath) {
    $srcpath = slurp_file("gh-pages.src") if (-f "gh-pages.src");
    die "ydoc.pl: no srcpath argument and no gh-pages.src" unless ($srcpath);
    $srcpath =~ s/\n//g;
}
$pkgname = basename($srcpath) unless $pkgname;
die "ydoc.pl: $srcpath is not a directory" unless -d $srcpath;
my $destdir = ($pkgname ne "yorick")? "gh-pages" : "stdlib";
my $pkgdesc = "";
my $rterr;

sub make_gh_pages();
sub make_doc_comments();
sub make_manual();
sub make_qref();
sub jekyll();
if ($do_generate) {
    # initialize gh-pages.src, gh-pages/
    # note that if this is yorick itself, there is no gh-pages/
    make_gh_pages();
    # create the pages containing DOCUMENT comments
    make_doc_comments();
    if ($pkgname eq "yorick") {
        # create the user manual
        make_manual();
        # create the quick reference
        make_qref();
    }
} elsif (not $do_update) {
    # run jekyll emulator
    jekyll();
}
sub git_update();
git_update() if ($do_update);

sub make_clean {
    my $fname = $_;
    return if (-d $fname);
    foreach ('~$', '^#', '^core$', '\.core$', '\.dSYM$') {
        if ($fname =~ qr{$_}) {
            unlink $fname;
            last;
        }
    }
}

my $srctop;
my $dsttop;
sub git_cp;

sub make_gh_pages() {
    remove_tree "_site", {error => \$rterr} if (-d "_site");
    unlink "gh-pages.src" if (-f "gh-pages.src");
    remove_tree $destdir, {error => \$rterr} if (-d $destdir);
    mkdir $destdir;
    burp_file "gh-pages.src", "$srcpath\n";

    my $ghinit = 0;
    if ($destdir eq "gh-pages") {
        my $prefix = "http://dhmunro.github.com/yorick-doc";  # default prefix
        # initialize gh-pages from git branch
        if ($ghpath) {
            $dsttop = getcwd() . "/gh-pages";
            $srctop = undef;
            find \&git_cp, $ghpath;
            $ghinit = 1;
        } else {
            chdir "gh-pages";
            for my $nm ("gh-pages", "origin/gh-pages") {
                # see also git show for retrieving single files
                system "git archive --remote=../$srcpath $nm 2>/dev/null | tar xf - >/dev/null 2>&1";
                # GNU tar bug does not return proper exit status before 1.19
                # $ghinit = 1 unless ($?);
                $ghinit = 1 if (-d "_layouts");
                last if ($ghinit);
            }
            chdir "..";
        }
        unless ($ghinit) {
            # create default gh-pages now
            my $cfg = slurp_file("_config.yml");
            $cfg =~ s/^prefix: .*$/prefix: "$prefix"/m;
            $cfg =~ s/^pkgname: .*$/pkgname: "$pkgname"/m;
            $pkgtitle = "$pkgname package" unless ($pkgtitle);
            $cfg =~ s/^pkgtitle: .*$/pkgtitle: "$pkgtitle"/m;
            burp_file "gh-pages/_config.yml", $cfg;

            copy ".gitignore", "gh-pages/.gitignore";
            mkdir "gh-pages/_layouts";
            copy "_layouts/default.html", "gh-pages/_layouts";

            mkdir "gh-pages/_includes";
            for my $nm (<_includes/*>) {
                next if ($nm !~ /\.html$/);
                next if ($nm =~ /\/sideqr.\.html$/);
                unless ($nm =~ /package\.html$/) {
                    copy $nm, "gh-pages/_includes";
                } else {
                    burp_file "gh-pages/_includes/package.html", <<"EOF";
<p>${pkgname}: $pkgtitle</p>
EOF
                }
            }
        } else {
            # take prefix, pkgname, pkgtitle from _config.yml
            my $cfg = slurp_file("gh-pages/_config.yml");
            ($prefix) = $cfg =~ /^prefix: (.*)$/m;
            ($pkgname) = $cfg =~ /^pkgname: (.*)$/m;
            ($pkgtitle) = $cfg =~ /^pkgtitle: (.*)$/m;
            
        }
        $pkgdesc = slurp_file("gh-pages/_includes/package.html")
            if (-r "gh-pages/_includes/package.html");
    } else {
        $pkgtitle = "Standard Library";  # for make_doc_comments
        $pkgdesc = slurp_file("_includes/package.html");
    }
}

sub git_cp {
    my $fname = $_;
    if ($fname eq '_site') {
        $File::Find::prune = 1;
        return;
    }
    $srctop = $File::Find::dir unless ($srctop);
    (my $dir) = $File::Find::dir =~ /^$srctop(.*)/;
    $dir = $dir? "/$dir" : "";
    $dir = $dsttop.$dir;
    if (-d $fname) {
        mkdir "$dir/$fname" unless (-d "$dir/$fname");
    } else {
        unlink "$dir/$fname" if (-f "$dir/$fname");
        copy $fname, "$dir/$fname";
    }
}

sub require_clean_work_tree() {
    # recent git function of this name, implemented in perl
    my $bad = 0;
    system "git update-index -q --ignore-submodules --refresh";
    system "git diff-files --quiet --ignore-submodules --";
    $bad += 1 if ($?);
    system "git diff-index --cached --quiet HEAD --ignore-submodules --";
    $bad += 2 if ($?);
    return 0 unless $bad;
    print "git found unstaged changes in $srcpath\n" if ($bad & 1);
    print "git found uncommitted changes in $srcpath\n" if ($bad & 2);
    die "----- stash or commit before running ydoc.pl -u";
}

sub git_update() {
    if ($destdir ne "gh-pages") {
        # for main yorick distro, update simply does "make clean"
        remove_tree "_site", {error => \$rterr} if (-d "_site");
        unlink "gh-pages.src" if (-f "gh-pages.src");
        remove_tree "gh-pages", {error => \$rterr} if (-d "gh-pages");
        find \&make_clean, ".";  # clean out unwanted files
        return;
    }
    find \&make_clean, "gh-pages";  # clean out unwanted files

    my $wd = getcwd();
    chdir $srcpath;
    $dsttop = getcwd();
    require_clean_work_tree();
    my $ready = 0;
    if (system("git show gh-pages: >/dev/null 2>&1")) {
        if (system("git show origin/gh-pages: >/dev/null 2>&1")) {
            # create new disconnected, empty gh-pages branch
            unless (system("git symbolic-ref HEAD refs/heads/gh-pages >/dev/null")) {
                unlink ".git/index";
                $ready = 1 unless (system("git clean -fdx >/dev/null"));
            }
            die "git failed to create gh-pages branch in $srcpath"
                unless ($ready);
        } else {
            # create local gh-pages branch from remote gh-pages
            system "git branch --track gh-pages origin/gh-pages >/dev/null";
            die "git failed to create tracking branch from origin/gh-pages"
                if ($?);
        }
    }
    unless ($ready) {
        system "git checkout gh-pages >/dev/null";
        die "git failed to checkout gh-pages in $srcpath" if ($?);
    }
    $srctop = undef;
    find \&git_cp, "$wd/gh-pages";
    system "git add -A >/dev/null";
    die "git failed to stage gh-pages branch in $srcpath" if ($?);
    chdir $wd;

    print "$srcpath git repo now on gh-pages branch with staged changes\n";
    print "  - now run git commit there to save gh-pages changes\n";
    print "    then git checkout master to return to master branch\n";
}

#   generated by File::Find wanted function scan through .i files
# $secdata{$sec}->{'ifile'}     .i file
# $secdata{$sec}->{'desc'}      brief description of section
# $symdata{$sym}                primary associated with this symbol
# $docdata{$pri}->{'section'}   section name
# $docdata{$pri}->{'body'}      raw document body, see also removed
# $docdata{$pri}->{'seealso'}   space delimited see also list
#   generated in loop over symbols
# $secdata{$sec}->{'html'}->{$sym}    html for sym
#
my %secdata;
my %symdata;
my %docdata;
my $n_sections;

sub make_docbod($$$)
{
    my $pri = $_[0];
    my $sa = $_[1];
    my $bod = $_[2];
    return <<"EOF";
<div class=\"docblock\"><a name=\"$pri\"></a><h3>$pri</h3>
  <pre>$bod</pre>
  $sa
</div>
EOF
}
sub sec_filename($)
{
    return ($n_sections<=1)? "index.html" : "$_[0].html";
}
sub make_salink($)
{
    my $sym = $_[0];
    my $pri = $symdata{$sym};
    return $sym unless ($pri);
    my $fil = sec_filename($docdata{$pri}->{'section'});
    return "<a href=\"$fil#$pri\">$sym</a>";
}
sub make_docsee($$)
{
    my $sym = $_[0];
    my $pri = $_[1];
    return <<"EOF";
<div class=\"docsee\">
  <h3>$sym</h3><p>SEE: <a href=\"#$pri\">$pri</a></p>
</div>
EOF
}
sub readme_files($)
{
    my $fil = $_[0];
    (my $sec) = $fil =~ /^(.+)\.i$/;
    return $fil unless $secdata{$sec};
    $secdata{$sec}->{'readme'} = 1;
    return "<a href=\"$sec.html\">$fil</a>";
}
sub readme_funcs($)
{
    my $flist = $_[0];
    $flist =~ s/(\w+|\(.*?\))/make_salink($1)/sge;
    return $flist;
}

# workhorse, scans each .i file, extracting DOCUMENT comments
sub extract_dot_i {
    my $fname = $_;
    if (-d $fname) {
        $File::Find::prune = 1
            if ($fname =~ /^relocate/
                || $fname eq "i-start");
        return;
    }
    return unless (/\.i$/ && (-f $fname));
    if ($destdir eq "stdlib") {
        return if ($File::Find::name=~/i(0\/(hex|drat)|\/ylmdec)\.i$/);
        return if ($fname eq "cerfc.i" || $fname eq "ferfc.i"
                   || $fname eq "dratt.i" || $fname eq "htmldoc.i"
                   || $fname eq "collec.i" || $fname eq "show.i"
                   || $fname eq "readn.i");
    }
    my $file = slurp_file($fname);
    $fname = substr($fname, 0, -2);
    my $sname = $fname;

    # put \a markers around document comments,
    # prefixed by the extern, local, or func lines they document
    # - this is not quite what either the help function or the mkdoc function
    #   does, but those are neither consistent with each other, nor
    #   semantically sensible
    $file =~ s/\a//g;  # paranoia -- make sure no preexisting markers
#    $file =~ s/^[ \t]*((extern|local|func)\b[^\n]*(\n[ \t]*(extern|local|func)\b[^\n]*)*\n([^\n]*\S[^\n]*\n)*?[ \t]*\/\* DOCUMENT\b.*?\*\/)/\a$1\a/msg;
    $file =~ s/^[ \t]*func[ \t]+(\w+)(\s*\(.*?\))?(\s*\{([^\n]*\})?)?/func $1/msg;
    $file =~ s/^[ \t]*((extern|local|func)\b[^\n]*(\n[ \t]*(extern|local|func)\b[^\n]*)*\n[ \t]*\/\* DOCUMENT\b.*?\*\/)/\a$1\a/msg;
    # make sections into pseudo-blocks
    $file =~ s/(\/\*= SECTION\(.*?\).*?=+\*\/)/\a$1\a/sg;
    # remove everything except \a blocks
    $file =~ s/.*?\a(.*)\a.*/$1/ms;      # zap thru first, last onward
    $file =~ s/\a.*?\a/\a/msg;        # zap between markers
    $file =~ s/([ \t]*\/\* DOCUMENT\b)/\a$1/msg;  # separate comments
    $file =~ s/\/\*= SECTION(\(.*?\).*?)=+\*\//S\a$1/sg;
    my @docblks = split(/\a/, $file);       # split at markers
    if ($#docblks < 1) { $#docblks = -1; }
    my($syms, $sec, $desc, $newsec, $secount) = ("", "", "", 0, 0);
    for my $i (0 .. $#docblks) {
        my $db = $docblks[$i];
        my $sa = undef;
        $docblks[$i] = undef;
        if ($db eq "S") {
            $newsec = 1;
            $secount = 0;
        } elsif ($newsec) {
            $newsec = 0;
            ($sec, $desc) = $db =~ /\(\s*(.*?)\s*\)\s*(.*)\s*/s;
        } elsif (($i & 1) == 0) {
            # reduce symbol names to single space delimited string
            $db =~ s/\/\*.*?\*\///sg;        # remove C comments
            $db =~ s/\/\/.*?\n/\n/sg;        # remove C++ comments
            $db =~ s/;.*?\n/\n/sg;           # remove semi-colon
            $db =~ s/\b(extern|local|func)\b//g; # remove yorick keyword
            $db =~ s/[ \t\n,]+/ /g;          # remove excess punctuation
            $db =~ s/^[ \t]+|[ \t]+$//g;     # trim whitespace
            $syms = $db;
        } else {
            # format document body
            $db =~ s/\/\*/  /;            # replace /* by two spaces
            $db =~ s/^([ \t]*?)\*([ \t\n])/$1 $2/mg; # leading *->blank
            $db =~ s/[ \t\n]*\*\///;      # remove [whitespace]*/
            # would like to remove leading spaces from each line
            $db =~ /^[ \t]*/;
            my $ns = $+[0];               # count leading spaces
            $db =~ s/^[ \t]{0,$ns}//mg;   # quick and dirty de-indent
            if ($db =~ /^[ \t*]*SEE ALSO:?/m) {
                $sa = substr($db, $+[0]);
                $db = substr($db, 0, $-[0]-1);
                $sa =~ s/\(.*?\)//sg;     # remove parenthetic remarks
                $sa =~ s/[ \t\n,;]+/ /g;  # remove excess punctuation
                $sa =~ s/[ \t]*(.*)[ \t]*/$1/;  # trim whitespace
            }

            # db = document body, sa = seealso symbols, syms = aliases
            # sec = section name, desc = section description
            # secount = number of previous docblocks in this section
            my @ss = split /\s+/, $syms;
            my $pri = $ss[0];
            unless ($secount++) {
                $sname = $fname;
                if (length($sec) > 0) { $sname .= "-$sec"; }
                $secdata{$sname} = {
                    'ifile' => $fname,
                    'desc' => $desc,
                    'html' => {}
                };
            }
            foreach (@ss) {
                $symdata{$_} = $pri;
            }
            $docdata{$pri} = {
                'section' => $sname,
                'body' => $db,
                'seealso' => $sa
            };
        }
    }
}

sub make_index($@)
{
    my $ncols_index = 3;   # 4 may be tight in a narrow browser window
    my $class = (shift)? '"ndex0s"' : '"ndex0"';
    my @syms = @_; # assume sorted by sort {uc($a) cmp uc($b)}
    my $first = "";
    my @lines = map {
        my $sym = $_;
        my $fc = uc(substr($sym,0,1));
        my @ll = ();
        if ($fc ne $first) {
            push @ll, "    <h3>$fc</h3>";
            $first = $fc;
        }
        push @ll, "    <p>".make_salink($sym)."</p>";
        @ll;
    } @syms;
    use integer;
    my $ntot = scalar(@lines);
    my $nmin = $ntot / $ncols_index;
    my $nx = $ntot % $ncols_index;
    my $result = "<div class=$class>\n";
    my $m = -1;
    for my $i (1 .. $ncols_index) {
        my $len = $nmin + (($i <= $nx)?1:0);
        last unless ($len);
        $result .= "  <div class=\"ndex$i\">\n" .
            join("\n", @lines[$m+1 .. $m+$len]) . "\n  </div>\n";
        $m += $len;
    }
    return $result . "</div>\n";
}

sub remove_desc($$)
{
    my $fil = $_[0];
    my $descall = $_[1];
    (my $lines) = $descall =~ /((.*\(in $fil\.i\).*\n)+)/;
    $descall =~ s/.*\(in $fil\.i\).*//g;
    return ($lines, $descall);
}

# Idea: if $descall and $pkgdesc were written into _includes/ they
# could be inserted into the page layout by the liquid template engine
# which would permit more extensive custom reformatting, since
# ydoc.pl would not clobber the include or layout file that inserted them
sub make_doc_comments() {
    no warnings 'File::Find';
    find \&extract_dot_i, $srcpath;  # build the hash tables

    # html file name is section name, or "index" if only one section
    my @secs = sort {uc($a) cmp uc($b)} keys %secdata;
    $n_sections = scalar(@secs);

    # construct lists of all symbols in each section, and
    # build the html for each symbol
    for my $sym (keys %symdata) {
        my $pri = $symdata{$sym};
        my $doc = $docdata{$pri};
        my $sec = $doc->{'section'};
        if ($sym eq $pri) {
            # build docblock html for primary (note that empty stays empty)
            my $sa = $doc->{'seealso'};
            $sa = "" unless ($sa);
            $sa =~ s/\s+/, /g;
            $sa =~ s/(\w+)/make_salink($1)/eg;
            $sa =~ s/(.+)/<p>SEE ALSO: $1<\/p>/s;
            my $html = $doc->{'body'};
            $html =~ s/(.+)/make_docbod($pri,$sa,$1)/es;
            $secdata{$sec}->{'html'}->{$sym} = $html;
        } else {
            # build docsee html for alias
            $secdata{$sec}->{'html'}->{$sym} = make_docsee($sym,$pri);
        }
    }

    # create the individual html files
    my $uplevel;
    if ($n_sections <= 1) {
        $uplevel = $pkgdesc;
    } else {
        $uplevel = <<"EOF";
<p class="sectop">Back to <a href="index.html">library index</a>.</p>
EOF
    }
    my @descs = ();
    for my $sec (@secs) {  # loop on sections (html files) in alphabetic order
        my $ifile = $secdata{$sec}->{'ifile'};
        my $desc = $secdata{$sec}->{'desc'};
        my $fname = sec_filename($sec);
        my $htmlref = $secdata{$sec}->{'html'};
        open my $fh, '>', "$destdir/$fname";
        print $fh <<"EOF";
---
layout: default
headline: $pkgtitle
---
${uplevel}<p class="sectop">Package $sec (in $ifile.i) - $desc</p>
<p class="sectop">Index of documented functions or symbols:</p>
EOF
        my @syms = sort {uc($a) cmp uc($b)} keys %$htmlref;
        print $fh make_index(1, @syms);
        for my $sym (@syms) { print $fh $htmlref->{$sym}; }
        close $fh;
        push @descs,
          "<p class=\"seclist\"><a href=\"$fname\">$sec</a> (in $ifile.i) - $desc</p>";
    }
    my $descall = join("\n", @descs);

    # construct index file
    unless ($n_sections <= 1) {
        my $fname;
        my $frstline;
        unless ($destdir eq "stdlib") {
            $fname = "$destdir/index.html";
            $frstline = <<"EOF";
<p class="sectop">Skip to <a href="#skip-funs">function index</a>.</p>
$pkgdesc
<p class="sectop"><a name="skip-secs"></a>Documentation sections:</p>
$descall
<p class="sectop">Back to <a href="#skip-secs">section index</a>.<br />
<a name="skip-funs"></a>Function or symbol index:</p>
EOF
        } else {
            $fname = "$destdir/index-f.html";
            $frstline = <<"EOF";
<p class="sectop">Back to <a href="index.html">standard library sections</a>.<br />
Standard library functions or symbols:</p>
EOF
        }
        open my $fh, '>', "$fname";
        print $fh <<"EOF";
---
layout: default
headline: $pkgtitle
---
$frstline
EOF
        my @syms = sort {uc($a) cmp uc($b)} keys %symdata;
        print $fh make_index(0, @syms);
        close $fh;
    }

    # construct standard library section index from i/README
    if ($destdir eq "stdlib") {
        die "missing $srcpath/i/README" unless (-r "$srcpath/i/README");
        my $rdme = slurp_file("$srcpath/i/README");
        $rdme =~ s/^[ \t]+|[ \t]+$//mg;   # remove leading and trailing blanks
        $rdme =~ s/^(.+)\n-+$/\<h3\>$1\<\/h3\>/mg; # underline -> h3
        # mark up first paragraph
        $rdme = "<p>" . $rdme;
        $rdme =~ s/\n\n/\n<\/p>\n/;
        $rdme =~ s/Y_SITE/<a href="paths.html#Y_SITE">Y_SITE<\/a>/;
        # replace last paragraph by temporary h3 marker
        $rdme =~ s/Additional functions may be.*/<h3>/s;
        # insert dl between h3 blocks
        $rdme =~ s/<\/h3>(.+?)\n<h3/<\/h3>\n<dl class="docdef">$1\n<\/dl>\n<h3/sg;
        $rdme =~ s/<h3>$//;  # remove temporary h3 marker
        # insert markup for dl items
        $rdme =~ s/^(\w+?)\.i\s+/<dt>$1.i<\/dt><dd>/msg;
        $rdme =~ s/<dd>(.*?)\n<(dt|\/dl)>/<dd>$1<\/dd>\n<$2>/msg;
        # insert line breaks before function lists
        $rdme =~ s/^(Functions?:)/<br \/>$1/mg;
        # insert file links
        $rdme =~ s/(<dt>)(.*?)(<\/dt>)/$1.readme_files($2).$3/mge;
        # insert function links
        $rdme =~ s/(Functions?:)(.*?)(<\/dd>)/$1.readme_funcs($2).$3/msge;
        for my $sec (@secs) {
            my $fil = $secdata{$sec}->{'ifile'};
            $descall =~ s/.*\(in $fil.i\).*//g
                if $secdata{$sec}->{'readme'};
        }

        (my $bltn, $descall) = remove_desc("std", $descall);
        (my $gbltn, $descall) = remove_desc("graph", $descall);
        (my $pathsd, $descall) = remove_desc("paths", $descall);
        (my $fftd, $descall) = remove_desc("fft", $descall);
        (my $matrixd, $descall) = remove_desc("matrix", $descall);

        open my $fh, '>', "$destdir/index.html";
        print $fh <<"EOF";
---
layout: default
headline: $pkgtitle
---
<p>Go to <a href="index-f.html">index of all functions or symbols</a>.</p>
$pkgdesc
<h2>Built-in functions</h2>
$bltn
$pathsd
$fftd
$matrixd
<h2>Basic graphic functions</h2>
$gbltn
<h2>Interpreted library packages</h2>
$rdme
<h2>Other distribution packages</h2>
$descall
EOF
    }
}

sub manual_file;

sub make_manual() {
    my $mansrc = "$srcpath/doc/yorick.tex";
    die "$mansrc missing" unless (-r $mansrc);
    remove_tree "manual", {error => \$rterr};
    mkdir "manual";
    system("texi2html --init-file=_manual.init $mansrc -o manual");

    # _manual.init only prints body of page, add jekyll header now
    no warnings 'File::Find';
    find \&manual_file, "manual";
}

sub manual_file {
    my $fname = $_;
    return unless ($fname =~ /\.html$/);
    open(my $fh, $fname);
    my $anchor = <$fh>;                     # first line is anchor
    $anchor = substr($anchor, 0, -1);       # - strip trailing newline
    my $contents = do { local $/; <$fh> };  # slurp the rest
    close($fh);
    burp_file $fname, <<"EOF";      # rewrite with proper header
---
layout: default
headline: User Manual
anchor: '$anchor'
---
$contents
EOF
}

my %qrheadlines;
my %qrlayouts;
my %qrbars;
sub qref_file;

sub make_qref() {
    %qrheadlines = (
        'l' => "Language Reference",  # matches qrlangXX.html
        'f' => "Function Reference",  # matches qrfuncXX.html
        'i' => "I/O Reference",       # matches qrioXX.html
        'd' => "Quick Reference"      # matches index.html
        );
    %qrlayouts = (
        'l' => "qrlang",
        'f' => "qrfunc",
        'i' => "qrio",
        'd' => "default"
        );

    my $qrsrc = "$srcpath/doc/refs-html";
    die "$qrsrc missing" unless (-d $qrsrc);
    remove_tree "qref", {error => \$rterr};
    mkdir "qref";
    $dsttop = getcwd() . "/qref";

    no warnings 'File::Find';
    find \&qref_file, $qrsrc;

    # regenerate quick reference layouts and sidebars
    my $layout = slurp_file("_layouts/default.html");
    my $sidebar = slurp_file("_includes/sideqref.html");
    for my $key ('l', 'f', 'i') {
        my $c = "$layout";
        $c =~ s/\{\{page\.headline\}\}/$qrheadlines{$key}/g;
        $c =~ s/sidebar\.html/sideqr${key}.html/g;
        burp_file "_layouts/$qrlayouts{$key}.html", $c;
        $c = "$sidebar";
        $c =~ s/%QRSIDE%/$qrbars{$key}/g;
        burp_file "_includes/sideqr${key}.html", $c;
    }
}

sub qref_file {
    my $fname = $_;
    return unless ($fname =~ /\.html$/);
    my $key = substr($fname,2,1);  # third character of filename is hash key
    my $layout = $qrlayouts{$key};
    my $contents;
    my $pg = slurp_file($fname);
    if ($key eq 'd') {
        $pg =~ m|^\s*<p.+</table>\s$|ms;
        $contents = substr($pg, $-[0], $+[0] - $-[0]);
    } else {
        $pg =~ m|(^\s*<ul.+</ul>\s*$).+(^\s*<h2.+)^\s*</td>|ms;
        my @ll = @-;
        my @rr = @+;
        $qrbars{$key} = substr($pg, $ll[1], $rr[1] - $ll[1])
            unless ($qrbars{$key});
        $contents = substr($pg, $ll[2], $rr[2] - $ll[2]);
    }
    burp_file "$dsttop/$fname", <<"EOF";      # rewrite with proper header
---
layout: $layout
headline: Quick Reference
---
$contents
EOF
}

my $site;
my %siteconfig;
sub jekyll_file;

sub jekyll() {
    chdir "gh-pages" if ($destdir eq "gh-pages");

    remove_tree "_site", {error => \$rterr} if (-d "_site");
    mkdir "_site";
    $site = getcwd() . "/_site";
    my $content = slurp_file("_config.yml");
    %siteconfig = $content =~ /^(.*?):[ \t]*["']?(.*?)["']?[ \t]*$/mg;

    no warnings 'File::Find';
    $srctop = undef;
    find \&jekyll_file, ".";  # build the result files

    chdir ".." if ($destdir eq "gh-pages");
}

sub dotmpl($@)
{
    my $arg = shift;
    my %cfg = @_;
    $arg = $cfg{$arg};
    return $arg? $arg : "";
}

sub jekyll_file {
    my $fname = $_;
    if ($fname =~ /^_/ || $fname =~ /^\.git.*/ || $fname =~ /~$/) {
        $File::Find::prune = 1 if (-d $fname);
        return;
    }
    for ("ydoc.pl", "README.md", "gh-pages.src", "gh-pages") {
        next unless ($fname eq $_);
        $File::Find::prune = 1 if (-d $fname);
        return;
    }

    $srctop = $File::Find::dir unless ($srctop);
    (my $delta) = $File::Find::dir =~ /^$srctop(.*)/;
    my $sname = ($delta? $site.$delta : $site)."/".$fname;

    if (-d $fname) {
        mkdir $sname if ($fname ne ".");
        return;
    }

    my $content = slurp_file($fname);
    if ($content =~ /^---\n.*?\n---\n/s) {
        my $yaml = substr($content, 0, $+[0]);
        $content = substr($content, $+[0]);

        # convert yaml front matter to hash
        my %config = $yaml =~ /^(.*?):[ \t]*["']?(.*?)["']?[ \t]*$/mg;
        %config = map { ("page.$_", $config{$_}) } keys %config;
        $config{'content'} = $content;
        if ($config{'page.prefix'}) {
            $config{'prefix'} = $config{'page.prefix'};
        } else {
            $config{'prefix'} = $siteconfig{'prefix'};
        }

        # retrieve layout template
        my $dir = "$site/../_layouts";
        $content = slurp_file("$dir/$config{'page.layout'}.html");
        # expand includes until no more includes
        $dir = "$site/../_includes";
        while ($content =~ /\{%\s*include (.*?)\s*%\}/) {
            $content =~ s/\{%\s*include (.*?)\s*%\}/slurp_file("$dir\/$1")/ge;
        }
        # get rid of if/else/endif used to set prefix variable in default.html
        $content =~ s/\{%\s*if .*?\{%\s*endif\s*%\}//sg;
        # substitute values from yaml front matter and siteconfig
        $content =~ s/\{\{\s*site\.(.*?)\s*\}\}/dotmpl($1,%siteconfig)/ge;
        $content =~ s/\{\{\s*(.*?)\s*\}\}/dotmpl($1,%config)/ge;
    }
    burp_file $sname, $content;
}
