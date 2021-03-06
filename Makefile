SRC = allennlp

MD_DOCS_ROOT = docs/
MD_DOCS_API_ROOT = $(MD_DOCS_ROOT)api/
MD_DOCS_SRC = $(filter-out $(SRC)/__main__.py %/__init__.py $(SRC)/version.py,$(shell find $(SRC) -type f -name '*.py' | grep -v -E 'tests/'))
MD_DOCS = $(subst .py,.md,$(subst $(SRC)/,$(MD_DOCS_API_ROOT),$(MD_DOCS_SRC)))
MD_DOCS_CMD = python scripts/py2md.py
MD_DOCS_CONF = mkdocs.yml
MD_DOCS_CONF_SRC = mkdocs-skeleton.yml
MD_DOCS_TGT = site/
MD_DOCS_EXTRAS = $(addprefix $(MD_DOCS_ROOT),README.md LICENSE.md ROADMAP.md CONTRIBUTING.md)

DOCKER_TAG = allennlp/allennlp

ifeq ($(shell uname),Darwin)
	ifeq ($(shell which gsed),)
		$(error Please install GNU sed with 'brew install gnu-sed')
	else
		SED = gsed
	endif
else
	SED = sed
endif

.PHONY : version
version :
	@python -c 'from allennlp.version import VERSION; print(f"AllenNLP v{VERSION}")'

#
# Testing helpers.
#

.PHONY : lint
lint :
	flake8 -v ./scripts $(SRC)
	black -v --check ./scripts $(SRC)

.PHONY : typecheck
typecheck :
	mypy $(SRC) \
		--ignore-missing-imports \
		--no-strict-optional \
		--no-site-packages \
		--cache-dir=/dev/null

.PHONY : test
test :
	pytest --color=yes -rf --durations=40 -k "not sniff_test" $(SRC)

.PHONY : test-with-cov
test-with-cov :
	pytest --color=yes -rf --cov-config=.coveragerc --cov=$(SRC) --durations=40 -k "not sniff_test" $(SRC)

#
# Setup helpers
#

.PHONY : install
install :
	# Making sure the typing backport isn't installed.
	pip uninstall -y typing
	# Ensure pip, setuptools, and wheel are up-to-date.
	pip install --upgrade pip setuptools wheel
	# Due to a weird thing with pip, we may need egg-info before running `pip install -e`.
	# See https://github.com/pypa/pip/issues/4537.
	python setup.py install_egg_info
	# Install allennlp as editable and all dependencies except apex since that requires torch to already be installed.
	grep -Ev 'NVIDIA/apex\.git' dev-requirements.txt | pip install --upgrade --upgrade-strategy eager -e . -r /dev/stdin
	# The above command will probably install the typing backport because of pydoc-markdown,
	# so we have to uninstall it again.
	pip uninstall -y typing
	# Now install apex.
	grep -E 'NVIDIA/apex\.git' dev-requirements.txt | pip install --upgrade -r /dev/stdin

#
# Documention helpers.
#

.PHONY : build-all-api-docs
build-all-api-docs :
	@$(MD_DOCS_CMD) $(subst /,.,$(subst .py,,$(MD_DOCS_SRC))) -o $(MD_DOCS)

.PHONY : build-docs
build-docs : build-all-api-docs $(MD_DOCS_CONF) $(MD_DOCS) $(MD_DOCS_EXTRAS)
	mkdocs build

.PHONY : serve-docs
serve-docs : build-all-api-docs $(MD_DOCS_CONF) $(MD_DOCS) $(MD_DOCS_EXTRAS)
	mkdocs serve --dirtyreload

.PHONY : update-docs
update-docs : $(MD_DOCS) $(MD_DOCS_EXTRAS)

$(MD_DOCS_ROOT)README.md : README.md
	cp $< $@
	# Alter the relative path of the README image for the docs.
	$(SED) -i '1s/docs/./' $@

$(MD_DOCS_ROOT)LICENSE.md : LICENSE
	cp $< $@

$(MD_DOCS_ROOT)%.md : %.md
	cp $< $@

$(MD_DOCS_CONF) : $(MD_DOCS_CONF_SRC) $(MD_DOCS)
	python scripts/build_docs_config.py $@ $(MD_DOCS_CONF_SRC) $(MD_DOCS_ROOT) $(MD_DOCS_API_ROOT)

$(MD_DOCS_API_ROOT)%.md : $(SRC)/%.py scripts/py2md.py
	mkdir -p $(shell dirname $@)
	$(MD_DOCS_CMD) $(subst /,.,$(subst .py,,$<)) --out $@

.PHONY : clean
clean :
	rm -rf $(MD_DOCS_TGT)
	rm -rf $(MD_DOCS_API_ROOT)
	rm -f $(MD_DOCS_ROOT)*.md

#
# Docker helpers.
#

.PHONY : docker-image
docker-image :
	# Create a small context for the Docker image with only the files that we need.
	tar -czvf context.tar.gz \
			Dockerfile \
			scripts/ai2_internal/resumable_train.sh \
			dist/*.whl
	docker build \
			--pull \
			-f Dockerfile \
			-t $(DOCKER_TAG) - < context.tar.gz
