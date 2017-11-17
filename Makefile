build:
	docker run --rm -it -v $(shell pwd):/src:z -u hugo jguyomard/hugo-builder hugo

deploy: build
	git diff --exit-code
	git diff --cached --exit-code
	cd public; git add *; git commit -m "Site rebuild $(shell date)"; git push origin master

run:
	-docker run --rm -it -v $(shell pwd):/src -p 1313:1313 -u hugo jguyomard/hugo-builder hugo server --buildDrafts -w --bind=0.0.0.0

