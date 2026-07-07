PYTHON ?= python3
VENV ?= .venv

.PHONY: install-dev validate

install-dev:
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/python -m pip install --upgrade pip
	$(VENV)/bin/python -m pip install -r requirements-dev.txt

validate:
	PATH="$(CURDIR)/$(VENV)/bin:$$PATH" ./scripts/validate.sh
