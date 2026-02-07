# mcp-vision

MCP server providing snapshot vision + mic transcription with explicit arming.

## Goals
- First milestone
- Second milestone

## Quickstart

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -U pip
python -m pip install -e ".[dev]"
make lint test
```

## Development

```bash
make fmt
make lint
make test
```

## Repository hygiene
- Work happens on branches / PRs
- CI runs format + lint + tests on each push/PR
- Default layout is `src/` for packages and `tests/` for pytest
- Commits to `main` are blocked by default (local hook)

## License
MIT
