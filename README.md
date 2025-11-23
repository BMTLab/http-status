# http-status

A fast, zero-dependency CLI tool to look up HTTP status codes from your terminal.

`http-status` ships with an embedded database of common, extended, and a few unofficial HTTP status codes. It lets you:

* search by code (`404`), class/mask (`4xx`, `50x`), or free-text (`"teapot"`, `"too large"`),
* see concise descriptions, typical HTTP methods, and flags (e.g. `DEPRECATED`, `UNOFFICIAL`),
* output machine-friendly lists of codes or names for use in scripts and tools.

---

## Features

1. **Flexible lookup**

   * Exact numeric code: `404`, `200`, `503`
   * Class/mask with wildcards: `4xx`, `50x`, `20x`
   * Free-text search across name, aliases, and description.

2. **Embedded HTTP status database**

   * Includes standard 1xx–5xx codes.
   * Annotated with

     * common **HTTP methods** (e.g. `GET`, `POST`, `DAV`),
     * **aliases** (e.g. `Payload Too Large` for `413`),
     * **flags** like `DEPRECATED` or `UNOFFICIAL`.

3. **Readable, color-coded output**

   * Colors by status class: informational, success, redirect, client error, server error.
   * Aligns code + name on the first line, then shows methods and description on the next.

4. **Machine-readable modes**

   * `-k` — print **codes only** (one per line).
   * `-n` — print **names only** (one per line).
   * Designed to be easy to consume in scripts.

5. **Zero external dependencies**

   * Pure Bash + standard utilities (`printf`, `tput`).
   * No `curl`, no network calls, no external JSON/YAML.

> [!TIP]
> `http-status` is ideal for quick lookups while debugging APIs, writing docs,
> or building tests — without alt-tabbing to a browser.

---

## Requirements

* Bash (uses `[[ ... ]]`, arrays, etc.)
* Standard Unix coreutils (`printf`, `cat`, `tput`, `base` shell tools)

The script is otherwise self-contained and ships its own database.
No network access is required!

---

## Installation

### 1. Place the script somewhere permanent

```bash
chmod +x http-status
ln -s <path-to-http-status>/http-status.sh <path-to-local-bin>/http-status
```

Ensure `~/.local/bin` is on your `PATH`.

### 2. Optionally, source it for function-style use

You can also source the script in your shell profile if you prefer the `http-status` function to be available
without starting a new process:

Add this snippet to your `~/.bashrc`, `~/.bash_profile`, or similar startup file:

```bash
# ~/.bashrc or ~/.profile

if [[ -f "<path-to-http-status>/http-status.sh" ]]; then
  # Source to make `frsync` function available in the current shell
  # (the script auto-detects whether it was sourced or executed).
  source "<path-to-http-status>/frsync.sh"
fi
```

Reload your shell configuration:

```bash
source ~/.bashrc
```

When executed as a script, it runs `http-status "$@"` and exits with an appropriate status code.

---

## Quick start

### List all known statuses

```bash
http-status
# or
http-status -a
```

### Look up by exact code

```bash
http-status 404
http-status 503
```

### Look up by class/mask

Masks use `x` or `X` as a wildcard digit:

```bash
http-status 2xx    # all success codes (200–299)
http-status 20x    # 200–209
http-status 4xx    # all client errors
http-status 50x    # 500–509
```

### Fuzzy search by name or description

Free-text queries match case-insensitively against the code name, aliases and part of the description:

```bash
http-status 'too large'      # finds 413 (Content Too Large / Payload Too Large)
http-status teapot           # finds 418 (I'm a teapot)
http-status connection       # finds codes with "connection" in description
```

You can also pass multiple queries; a row matches if it satisfies **any** of them (logical OR).

### Exact phrase match

For more precise lookups, use `-x` to require exact equality with the status name or one of its aliases:

```bash
http-status -x 'Not Found'     # match exactly 404 name
http-status -x 'Payload Too Large'  # match 413 via alias
```

> [!IMPORTANT]
> `-x` requires at least one query string. Without a query, it is treated as invalid usage and the tool exits with a usage error.

---

## Color modes

The `-C` option controls how colors are used:

```bash
http-status -C auto  404   # default: color if stdout is a TTY
http-status -C always 404  # force colors even when piping/redirecting
http-status -C never  404  # disable colors completely
```

Classes are colored as follows (when color is enabled):

* `1xx` — informational (cyan)
* `2xx` — success (green)
* `3xx` — redirection (yellow)
* `4xx` — client error (red)
* `5xx` — server error (magenta)

This makes it easier to visually scan lists of statuses.

---

## Command-line usage

```bash
http-status [-h] [-a] [-C mode] [-k | -n] [-x] [query...]
```

### Options

| Option     | Type       | Default | Description                                                              |
| ---------- | ---------- | ------- | ------------------------------------------------------------------------ |
| `-h`       | flag       | —       | Show help and exit.                                                      |
| `-a`       | flag       | `false` | List all statuses (also the default if no queries are provided).         |
| `-C MODE`  | string     | `auto`  | Color mode: `auto`, `always`, or `never`.                                |
| `-k`       | flag       | `false` | Print **codes only** (one per line).                                     |
| `-n`       | flag       | `false` | Print **names only** (one per line).                                     |
| `-x`       | flag       | `false` | Exact phrase match on name/aliases instead of fuzzy substring search.    |
| `query...` | positional | —       | One or more codes, masks, or text queries to match against the database. |

Behavior summary:

* With **no queries** and no `-a`, the tool prints **all** statuses.
* With queries, it prints only matching rows (by code, mask, or text).
* With `-a`, it prints all statuses regardless of queries (useful with `-k`/`-n`).

---

## Exit codes

* `0` — success; at least one match printed
* `1` (`HS_ERR_GENERAL`) — general error or internal failure
* `2` (`HS_ERR_USAGE`) — invalid usage or arguments (bad options, etc.)
* `3` (`HS_ERR_NO_MATCH`) — status database loaded, but no rows matched the query

When the script is sourced, `http-status` **returns** these codes; when the script is executed,
it calls `exit` with the same codes.

This makes it easy to use in other shell scripts, for example:

```bash
if ! http-status -k 599 >/dev/null 2>&1; then
  echo 'Custom code 599 not found in db' >&2
fi
```
---

## License & disclaimer

This project is licensed under the [MIT License](./LICENSE).

> [!IMPORTANT]
> The embedded database is meant as a practical reference, including some unofficial/extension codes (e.g. 418, 444, 599).
> Always consult the authoritative HTTP specifications and your platform documentation for protocol-critical decisions.

---

## Contributing

Issues and pull requests are welcome!
If you propose new codes or changes to descriptions, please include references (or short notes)
so the database stays consistent and maintainable :innocent:
