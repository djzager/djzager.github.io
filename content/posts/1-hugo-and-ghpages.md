---
title: "Personal GitHub Pages with Hugo's Website Generator"
description: "Starting a blog with Hugo and Personal GitHub Pages"
tags: ["Hugo", "GitHub", "Git"]
cover: https://example.com/img/1/image.jpg
date: 2017-11-20
draft: true
---

I am excited to maintain a blog and there seems no better way to
get things rolling than to document the start. When I started playing with
[Hugo](https://gohugo.io) and thinking about how I would integrate it with
Personal GitHub Pages, I assumed it would be a trivial operation. Turns out
there are a few gotchas worth documenting. So, if you are looking to create a
static website using Hugo's Website Generator and want it to work with [Personal
GitHub Pages](https://pages.github.com/), then you have found the right place.

## Background

If you have not seen Jente Hidskes' [original article](https://hjdskes.github.io/blog/deploying-hugo-on-personal-gh-pages/)
on deploying personal GitHub Pages or [his follow-up](https://hjdskes.github.io/blog/update-deploying-hugo-on-personal-gh-pages/)
then you should totally check those out first. When I originally ventured down
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

### Creating the Source Branch

```
$ hugo new site $GITHUB_USERNAME.github.io
```

### Map Publish Directory to Master Branch

## Deployment

## Automation

```Makefile
run:
	-docker run --rm -it -v $(shell pwd):/src:z \
		-p 1313:1313 -u hugo jguyomard/hugo-builder \
		hugo server --buildDrafts -w --bind=0.0.0.0

build:
	docker run --rm -it -v $(shell pwd):/src:z \
		-u hugo jguyomard/hugo-builder hugo

# https://stackoverflow.com/questions/5139290
publish: build
	# Fail if local unstaged changes
	git diff --exit-code
	# Fail if staged but not committed changes
	git diff --cached --exit-code
	cd public; \
	git add *; \
	git commit -m "Site rebuild $(shell date)"; \
	git push origin master
```
