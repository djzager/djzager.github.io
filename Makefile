deploy:
	git diff --exit-code
	git diff --cached --exit-code
	docker run --rm -it -v $(shell pwd):/src:z -u hugo jguyomard/hugo-builder hugo
	cd public; git add *; git commit -m "Site rebuild $(shell date)"

