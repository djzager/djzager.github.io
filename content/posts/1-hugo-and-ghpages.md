---
title: "Personal GitHub Pages with Hugo's Website Generator"
description: "Starting a blog with Hugo and Personal GitHub Pages"
tags: ["Hugo", "GitHub", "Git"]
cover: https://example.com/img/1/image.jpg
date: 2017-11-25
---

I am excited to maintain a blog and there seems no better way to
get things rolling than to document the start. When I started playing with
[Hugo](https://gohugo.io) and thinking about how I would integrate it with
Personal GitHub Pages, I assumed it would be a trivial operation. Turns out
there are a few gotchas worth documenting. This post will simply cover
creating a static website using Hugo's Website Generator and making it work
with [Personal GitHub Pages](https://pages.github.com/).

## Background

If you have not seen Jente Hidskes' [original article](https://hjdskes.github.io/blog/deploying-hugo-on-personal-gh-pages/)
on deploying personal GitHub Pages or [his follow-up](https://hjdskes.github.io/blog/update-deploying-hugo-on-personal-gh-pages/)
then you should check those out first. When I originally ventured down
this path I found [Hugo's hosting on GitHub](https://gohugo.io/hosting-and-deployment/hosting-on-github/)
article, changed the `publishDir` value in `config.toml`, and was very
dissappointed when it did not work. Unfortunately, that method only works for project pages.
Personal GitHub pages (built with Hugo), like this, must start with a valid
`index.html` file at the master branch's root.

## Configuration

In the case that you are starting off fresh, like I was, then this part is
fairly simple. If not, I recommend you use Jente Hidskes' [updated guide](https://hjdskes.github.io/blog/update-deploying-hugo-on-personal-gh-pages/),
keeping in mind that you must change the "default" branch away from master at
`https://github.com/$GITHUB_USERNAME/$GITHUB_USERNAME.github.io/settings/branches`
before trying to delete it; I did not and I was
properly punished for not reading his [original article](https://hjdskes.github.io/blog/deploying-hugo-on-personal-gh-pages/)
first. Our goals are:

1. Have a `$SOURCE` branch for all source files, I think of this as my Hugo workspace.
1. Publish the contents of our `publishDir` (`public/` by default) to the
   master branch.

**Note:** I did not install the hugo binary on my system. I instead used a
[hugo-builder docker image](https://hub.docker.com/r/jguyomard/hugo-builder/).
You can see the two ways I run the image below but for the remainder of the
post I will simply use `hugo` as it would look if I had installed the binary.

```bash
# When running a hugo command
$ docker run --rm -it -v $PWD:/src:Z -u hugo \
    jguyomard/hugo-builder hugo ${ARGS}

# When starting the hugo server
$ docker run --rm -it -v $PWD:/src -p 1313:1313 -u hugo \
    jguyomard/hugo-builder hugo server -v --buildDrafts -w --bind=0.0.0.0
```

### Initial Setup

Looking at the `setup.sh`
[gist](https://gist.github.com/djzager/b80a131acb4cabf33fac4f385c1987d7/raw/28e860cc3445ad81756eb028f7c6c154d8bf0097/setup.sh)
below, you will see that it covers the steps necessary to create my Hugo
workspace **and** use the `public/` directory as my `publishDir` using
[git worktree](https://git-scm.com/docs/git-worktree). This was my first
experience using worktree's and I found it a clever way to make this workflow
possible.

{{< gist djzager b80a131acb4cabf33fac4f385c1987d7 "setup.sh" >}}

### Add Content and Styling

The two primary tasks that remain are to add content and styling to our
website. Adding new content is as simple as `hugo new posts/$POST_NAME.md`
(assuming you are using [Hugo's
Markdown](https://gohugo.io/content-management/formats/)) and start writing.
Once you have content, but before you publish, you'll want to have a look at
[Hugo's Theme List](https://themes.gohugo.io/) and install one. When I
installed the [KISS theme](https://themes.gohugo.io/kiss/) I just added it
as a submodule (see below) and update my `config.toml` with the name of the
theme ("kiss").

```
git submodule add https://github.com/ribice/kiss.git themes/kiss
```

## Publish

All that is left now is to "publish" our contents by running `hugo` and pushing
the modified contents of our `publishDir` to our master branch.

First we build the site:

```
hugo
```

Then, move into the `publishDir` (`public/` for me), and push our changes to
master:

```
cd $PUBLISH_DIR
git add *
git commit -m "Site build $(date)"
git push origin master
```

You should see all green from Github at
`https://github.com/$GITHUB_USERNAME/$SITE_NAME/settings`, letting you know
that you site has successfully been published.

### Automation

Once you get over the initial hurdle of starting, it is important to find a
workflow that works best for you. Where some people like to write shell
scripts, I prefer to write a simple `Makefile` that covers everything from
running `hugo server` for when I'm writing, to building, and
publishing the content of the site. Feel free to copy, take inspiration from
the gist below, or go straight to
[the source](https://github.com/djzager/djzager.github.io).

{{< gist djzager b80a131acb4cabf33fac4f385c1987d7 "Makefile" >}}

## Conclusion

In this post we covered getting started with personal
[GitHub Pages](https://pages.github.com/) using
[Hugo's static web site generator](https://gohugo.io/),
publishing our content on the master branch using
[git working tree's](https://git-scm.com/docs/git-worktree),
maintaining the source files on a separate branch
to keep our sanity, and automating our workflow using a `Makefile`. Starting a
blog was the goal and Hugo + GitHub Pages have allowed that to happen.

:thumbsup:
