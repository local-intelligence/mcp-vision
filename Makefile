.PHONY: help venv install fmt lint test clean

help:
	@echo "Targets:"
	@echo "  venv     - create .venv"
	@echo "  install  - install dev deps"
	@echo "  fmt      - format (ruff)"
	@echo "  lint     - lint (ruff)"
	@echo "  test     - run tests (pytest)"
	@echo "  clean    - remove build artifacts"

venv:
	python3 -m venv .venv
	. .venv/bin/activate && python -m pip install -U pip

install:
	. .venv/bin/activate && python -m pip install -U pip
	. .venv/bin/activate && python -m pip install -e ".[dev]"

fmt:
	. .venv/bin/activate && ruff format .

lint:
	. .venv/bin/activate && ruff check .

test:
	. .venv/bin/activate && pytest

clean:
	rm -rf dist build .pytest_cache .ruff_cache __pycache__ htmlcov .coverage *.egg-info
