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
