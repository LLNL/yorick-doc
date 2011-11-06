# Yorick-doc

Yorick-doc generates the [http://dhmunro.github.com/yorick-doc]
website.  Yorick plugins and packages with git repositories can use
yorick-doc to generate and maintain their own html documentation in a
format consistent with this main yorick website.  Such branch websites
can be connected to the main yorick-doc website by issuing a pull
request at [http://github.com/dhmunro/yorick-doc] to add their URL to
the main pages.

## Getting yorick-doc

Begin by cloning the yorick-doc github repo:

    git clone git://github.com/dhmunro/yorick-doc.git

(or you can fork your own yorick-doc repo at github.com).  This repo
contains the yorick-doc perl scripts for generating yorick
documentation.

The yorick-doc.git repo also contains the main yorick web pages, if
you want to make a local copy of the main website.  According to the
github web pages convention, the [gh-pages](http://pages.github.com/)
repo branch contains the main website.  For yorick-doc itself, the
master and gh-pages branches are identical.

If all you want is a copy of the main yorick website, get it from
[http://github.com/ghmunro/yorick-doc/tarball/gh-pages].  (Or
substitute zipball for tarball if you prefer zip format.)

### Dependencies

* git
* perl
* texi2html (tested with v1.82) to build the yorick manual,
  required for building the yorick user manual only

## Running yorick-doc

With the current working directory the top-level of `yorick-doc/`
created by git clone (master branch), the command line is:

    perl ydoc.pl [-u] [-n pkgname] [-i ghpath] [srcpath [title]]

The `srcpath` is the path to the yorick plugin or package for which
you want to create a website.  The automatically generated site will
comprise all of the DOCUMENT comments in the .i files therein.

The `-u` option tells `ydoc.pl` to update (or create) a *gh-pages*
branch for the yorick package or plugin source at `srcpath`, which
must be the working directory of a git repo for that option to make
sense.

By default, the plugin or package name will be the final component of
`srcpath`.  You can override this by supplying `-n pkgname`, which
would be necessary if, for example, the final component of you
`srcpath` contained a version number (unusual if it is a git repo).  This
option is unnecessary if a *gh-pages* branch already exists, unless you
want to change the existing `pkgname`.

The `title` parameter will appear as the title of your website,
prefixed by the word "Yorick" (in the banner).  You need to supply
`title` only if `srcpath` has no *gh-pages* branch, or if you want to
change the title in *gh-pages*.

The result will be written to a `gh-pages/` directory where you ran
`ydoc.pl`, that is, in the top level of `yorick-doc`. If `srcpath` is
a git repo with a *gh-pages* branch, this output directory is
initialized to the *gh-pages* branch.  Therefore, you can modify files
which are not automatically generated and your modifications will be
preserved, if you commit them to the *gh-pages* branch in `srcpath`.
If your `srcpath` is not a git repo or has no *gh-pages* branch,
`ydoc.pl` creates a simple default containing all the required files.

Alternatively, you can use the `-i` option to specify a `ghpath` in
lieu of a *gh-pages* branch in `srcpath`.  This permits you to save
and manage your modifications to the `gh-pages/` directory, even if
`srcpath` is not a git repo, or if you simply do not wish to add a
*gh-pages* branch.  Be sure you copy the `gh-pages/` directory to some
permanent source-code-managed location (`ghpath`).

Additionally, `ydoc.pl` writes a file `gh-pages.src` containing the
`srcpath` argument used to generate `gh-pages/`.  This permits you to
omit the `srcpath` argument in subsequent invocations of `ydoc.pl`.
The rule is: If you supply `srcpath`, any existing `gh-pages/` and
`gh-pages.src` will be clobbered and replaced, while if you omit
`srcpath`, they must be present and will remain unchanged.

Without the `srcpath` argument, `ydoc.pl` will operate on the
`gh-pages/` directory it created in a previous invocation.  The
contents of `gh-pages/` are not the final web pages.  Github runs the
static site generator [jekyll](http://jekyllrb.com/) to build the
actual html pages.  Yorick-doc includes a simple perl script
implementing the tiny subset of jekyll it needs, which allows you to
generate the html files whether or not you have jekyll on your
platform.  Without any arguments,

    perl ydoc.pl

will generate the actual html pages from `gh-pages/`, placing them in
the sibling `_site/` directory.  This allows you to preview your
website locally with your browser.  You may wish to do that before
you update your *gh-pages* branch.

Running

    perl ydoc.pl -u

updates the *gh-pages* branch (in `srcpath`, as saved in
`gh-pages.src`) from the contents of the `gh-pages/` directory,
without regenerating it.  If no *gh-pages* branch exists (but
`srcpath` is a git repo), `ydoc.pl` creates one, and intializes it
with the contents of the `gh-pages/` directory.

## Customizing yorick-doc

The `ydoc.pl` script produces one html file per .i file in your source
tree containing any yorick DOCUMENT comments (a "documented .i file").
If you have more than one .i file, it also produces an html index file
with links to all the individual files, and an alphabetized index of
all the documented symbols.  If you have only one documented .i file,
the index will be combined with it.  At the top of each page is an
alphabetized list of links to the symbols documented on that page.

You can split a large .i file into several pages by inserting comment
lines in the .i file of the form:

    /*= SECTION(name) brief description ==========================/

The brief description will show up in the section index, next to the
page name.  You can leave out name, `SECTION()` and put the divider
comment line near the top of the file to get a brief description into
the index file, even when you do not want to split the page.  The page
name for `file.i` will be `file`; if the file is divided into multiple
sections, the page name for section `sect` will be `file-sect`.

You can also edit the files in `gh-pages/` which are not automatically
generated, in order to add more information about your plugin or
package, or to (slightly) modify the style, for example, by creating a
custom left sidebar.  Read the [jekyll](http://jekyllrb.com/) docs for
more information.

In particular, you are strongly encouraged to edit the file
`gh-pages/_includes/package.html`, which by default contains only the
briefest description of what your package does -- in fact, just its
title.  Don't forget that this is a part of an xhtml file, so put
`<p>` and `</p>` markup around your paragraph(s).  You can add a link
to a separate html jekyll template file if you want to add more
extensive descriptions.

## Credits

The yorick-doc pages use a very clean left sidebar page layout
designed by [Matthew James Taylor](http://matthewjamestaylor.com/blog/perfect-multi-column-liquid-layouts).
