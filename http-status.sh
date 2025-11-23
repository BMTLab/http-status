#!/bin/bash

# Name: http-status.sh
# Author: Nikita Neverov (BMTLab)
# Version: 2.6.1
# Date: 2025-11-20
# License: MIT
#
# Description:
#   Query and print HTTP status codes via CLI using an embedded database.
#   This script is designed to be a fast, zero-dependency lookup tool.
#
#   Features:
#     - Lookup by exact code (404) or mask (4xx, 50x).
#     - Fuzzy search by name, alias, or description.
#     - Rich database including HTTP methods and usage descriptions.
#     - Color-coded output based on status class (1xx-5xx).
#     - Machine-readable output modes (-k, -n).
#
# Usage:
#   http-status [-h] [-a] [-C mode] [-k | -n] [-x] [query...]
#
# Examples:
#   http-status                  # List all statuses
#   http-status 404              # Lookup by code
#   http-status 4xx              # Lookup by class mask
#   http-status 'too large'      # Lookup by phrase
#   http-status -n 5xx           # Print only names of 5xx errors
#
# Options:
#   -h          Show this help and exit.
#   -a          List all statuses (default if no query provided).
#   -C MODE     Color output: 'auto' (default) | 'always' | 'never'.
#   -k          Print codes only (machine-readable).
#   -n          Print names only (machine-readable).
#   -x          Exact phrase match (requires full name/alias equality).
#
# Exit Codes:
#   0: Success (matches found).
#   1: HS_ERR_GENERAL
#      Generic error or internal failure.
#   2: HS_ERR_USAGE
#      Invalid usage or arguments.
#   3: HS_ERR_NO_MATCH
#      No results found for the given query.
#
# Disclaimer:
#   This script is provided "as is", without warranty of any kind.

# Detect whether script is sourced or executed.
# If executed, enable strict error handling immediately.
# bashsupport disable=BP5001
if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
  readonly HS_SCRIPT_SOURCED=true
else
  readonly HS_SCRIPT_SOURCED=false
  set -o errexit -o nounset -o pipefail
fi

# Error codes (readonly constants)
if [[ -z ${HS_ERR_GENERAL+x} ]]; then
  readonly HS_ERR_GENERAL=1
fi
if [[ -z ${HS_ERR_USAGE+x} ]]; then
  readonly HS_ERR_USAGE=2
fi
if [[ -z ${HS_ERR_NO_MATCH+x} ]]; then
  readonly HS_ERR_NO_MATCH=3
fi

#######################################
# Print usage information.
#
# Outputs:
#   Usage text to stdout.
#######################################
function __hs_usage() {
  cat << 'EOF'
http-status - query and print HTTP status codes

Usage:
  http-status [-h] [-a] [-C mode] [-k | -n] [-x] [query...]

Options:
  -h          Show this help and exit.
  -a          List all statuses.
  -C MODE     Color mode: 'auto' (default), 'always', 'never'.
  -k          Print codes only.
  -n          Print names only.
  -x          Exact phrase match (requires full name equality).

Examples:
  http-status 403               # Check specific code
  http-status 5xx               # List all server errors
  http-status 'teapot'          # Search by text
  http-status -k 2xx            # List only codes for success statuses
EOF
}

#######################################
# Print error message, usage, and return/exit with code.
#
# Arguments:
#   1: Error message (string).
#   2: Exit code (integer, optional, default: HS_ERR_GENERAL).
#
# Outputs:
#   Error message to stderr.
#######################################
function __hs_error() {
  local -r message="$1"
  local -ir code="${2:-$HS_ERR_GENERAL}"

  printf 'ERROR: %s\n\n' "$message" >&2
  # Only show usage if it's a usage error
  if [[ $code -eq $HS_ERR_USAGE ]]; then
    __hs_usage
  fi

  # If sourced, return; if executed, exit
  if [[ $HS_SCRIPT_SOURCED == true ]]; then
    return "$code"
  else
    exit "$code"
  fi
}

#######################################
# Load the embedded HTTP status database.
#
# Format: CODE | NAME | ALIASES | FLAGS | METHODS | DESCRIPTION
#   - Comments start with #.
#   - Fields separated by pipes (|).
#   - Empty fields denoted by '-'.
#
# Outputs:
#   Raw database text to stdout.
#######################################
function __hs_get_db() {
  cat << 'DB_END'
    # --- 1xx: Informational ---
    100 | Continue                        | - | - | Any | Interim response; client should continue the request.
    101 | Switching Protocols             | - | - | GET,UPGRADE | Server is switching protocols (e.g., HTTP 1.1 to 2.0 or WebSocket).
    102 | Processing                      | - | - | DAV | Server has received and is processing the request, but no response is available yet.
    103 | Early Hints                     | - | - | Any | Used to return some response headers before final HTTP message.

    # --- 2xx: Success ---
    200 | OK                              | - | - | Any | Standard response for successful HTTP requests.
    201 | Created                         | - | - | POST,PUT | The request has been fulfilled, resulting in the creation of a new resource.
    202 | Accepted                        | - | - | Any | The request has been accepted for processing, but processing is not complete.
    203 | Non-Authoritative Information   | - | - | Any | The returned meta-information is from a local or third-party copy, not the origin server.
    204 | No Content                      | - | - | Any | The server successfully processed the request and is not returning any content.
    205 | Reset Content                   | - | - | Any | The server successfully processed the request, but asks client to reset the document view.
    206 | Partial Content                 | - | - | GET | The server is delivering only part of the resource (Range header).
    207 | Multi-Status                    | - | - | DAV | XML body contains multiple status codes for multiple independent operations.
    208 | Already Reported                | - | - | DAV | The members of a DAV binding have already been enumerated in a preceding part.
    226 | IM Used                         | - | - | GET | The server has fulfilled a request for the resource via Delta encoding.

    # --- 3xx: Redirection ---
    300 | Multiple Choices                | - | - | Any | Indicates multiple options for the resource from which the client may choose.
    301 | Moved Permanently               | - | - | Any | This and all future requests should be directed to the given URI.
    302 | Found                           | - | - | Any | Resource found at different URI, but client should use original URI for future.
    303 | See Other                       | - | - | POST,PUT,DELETE | The response to the request can be found under another URI using GET method.
    304 | Not Modified                    | - | - | GET,HEAD | Resource has not been modified since the version specified by the request headers.
    305 | Use Proxy                       | - | DEPRECATED | The requested resource is available only through a proxy.
    306 | (Unused)                        | - | DEPRECATED | No longer used. Originally meant "Switch Proxy".
    307 | Temporary Redirect              | - | - | Any | Resource found at different URI; keep using original method for future requests.
    308 | Permanent Redirect              | - | - | Any | The request and all future requests should be repeated using another URI.

    # --- 4xx: Client Error ---
    400 | Bad Request                     | - | - | Any | The server cannot or will not process the request due to an apparent client error.
    401 | Unauthorized                    | - | - | Any | Authentication is required and has failed or has not yet been provided.
    402 | Payment Required                | - | - | Any | Reserved for future use.
    403 | Forbidden                       | - | - | Any | The request was valid, but the server is refusing action.
    404 | Not Found                       | - | - | Any | The requested resource could not be found but may be available in the future.
    405 | Method Not Allowed              | - | - | Any | A request method is not supported for the requested resource.
    406 | Not Acceptable                  | - | - | Any | Content negotiation failed; server cannot produce response matching accept headers.
    407 | Proxy Authentication Required   | - | - | Any | The client must first authenticate itself with the proxy.
    408 | Request Timeout                 | - | - | Any | The server timed out waiting for the request.
    409 | Conflict                        | - | - | PUT,POST | Indicates that the request could not be processed because of conflict in the request.
    410 | Gone                            | - | - | Any | Indicates that the resource requested is no longer available and will not be available again.
    411 | Length Required                 | - | - | POST,PUT | The request did not specify the length of its content, which is required by the resource.
    412 | Precondition Failed             | - | - | Any | The server does not meet one of the preconditions that the requester put on the request.
    413 | Content Too Large               | Payload Too Large;Request Entity Too Large | - | Any | The request is larger than the server is willing or able to process.
    414 | URI Too Long                    | Request-URI Too Long | - | GET | The URI provided was too long for the server to process.
    415 | Unsupported Media Type          | - | - | POST,PUT | The request entity has a media type which the server or resource does not support.
    416 | Range Not Satisfiable           | Requested Range Not Satisfiable | - | GET | The client has asked for a portion of the file, but the server cannot supply that portion.
    417 | Expectation Failed              | - | - | Any | The server cannot meet the requirements of the Expect request-header field.
    418 | I'm a teapot                    | - | UNOFFICIAL | Any | The server refuses the attempt to brew coffee with a teapot (RFC 2324).
    421 | Misdirected Request             | - | - | Any | The request was directed at a server that is not able to produce a response.
    422 | Unprocessable Content           | Unprocessable Entity | - | Any | The request was well-formed but has semantic errors (e.g. validation failed).
    423 | Locked                          | - | - | DAV | The resource that is being accessed is locked.
    424 | Failed Dependency               | - | - | DAV | The request failed because it depended on another request and that request failed.
    425 | Too Early                       | - | - | Any | Indicates that the server is unwilling to risk processing a request that might be replayed.
    426 | Upgrade Required                | - | - | GET | The client should switch to a different protocol.
    428 | Precondition Required           | - | - | Any | The origin server requires the request to be conditional.
    429 | Too Many Requests               | - | - | Any | The user has sent too many requests in a given amount of time (rate limiting).
    431 | Request Header Fields Too Large | - | - | Any | The server is unwilling to process the request because its header fields are too large.
    444 | No Response                     | - | UNOFFICIAL | Any | Nginx internal code: server returns no information to the client and closes the connection.
    449 | Retry With                      | - | UNOFFICIAL | Any | Microsoft extension: The request should be retried after doing the appropriate action.
    450 | Blocked by Windows Parental     | - | UNOFFICIAL | Any | Microsoft extension: Error generated when Windows Parental Controls blocks access.
    451 | Unavailable For Legal Reasons   | - | - | Any | The resource is unavailable for legal reasons (e.g., censorship or government-mandated blocked).

    # --- 5xx: Server Error ---
    500 | Internal Server Error           | - | - | Any | A generic error message, given when an unexpected condition was encountered.
    501 | Not Implemented                 | - | - | Any | The server either does not recognize the request method, or it lacks the ability to fulfil the request.
    502 | Bad Gateway                     | - | - | Any | The server was acting as a gateway or proxy and received an invalid response from the upstream server.
    503 | Service Unavailable             | - | - | Any | The server is currently unavailable (overloaded or down for maintenance).
    504 | Gateway Timeout                 | - | - | Any | The server was acting as a gateway or proxy and did not receive a timely response from the upstream.
    505 | HTTP Version Not Supported      | - | - | Any | The server does not support the HTTP protocol version used in the request.
    506 | Variant Also Negotiates         | - | - | Any | Transparent content negotiation for the request results in a circular reference.
    507 | Insufficient Storage            | - | - | DAV | The server is unable to store the representation needed to complete the request.
    508 | Loop Detected                   | - | - | DAV | The server detected an infinite loop while processing the request.
    509 | Bandwidth Limit Exceeded        | - | UNOFFICIAL | Any | The server has exceeded the bandwidth limit specified by the server administrator.
    510 | Not Extended                    | - | - | Any | Further extensions to the request are required for the server to fulfil it.
    511 | Network Authentication Required | - | - | Any | The client needs to authenticate to gain network access.
    599 | Network Connect Timeout Error   | - | UNOFFICIAL | Any | Used by some proxies to signal a network connect timeout behind the proxy.
DB_END
}

#######################################
# Helper to trim whitespace from start/end of string.
#
# Arguments:
#   1: String to trim.
#
# Outputs:
#   Trimmed string to stdout.
#######################################
function __hs_trim() {
  local input_string="$1"

  # Remove leading whitespace
  input_string="${input_string#"${input_string%%[![:space:]]*}"}"
  # Remove trailing whitespace
  input_string="${input_string%"${input_string##*[![:space:]]}"}"

  printf '%s' "$input_string"
}

#######################################
# Check if a specific database row matches the user queries.
#
# Handles logic for:
#   - Numeric masks (e.g. 4xx, 50x)
#   - Exact string match (-x)
#   - Fuzzy substring match
#
# Arguments:
#   1: Row Code (string/int).
#   2: Row Name (string).
#   3: Row Aliases (semicolon separated string).
#   4: Array of user queries (nameref).
#   5: Exact match flag (bool).
#
# Returns:
#   0: If the row matches any of the queries.
#   1: If no match found.
#######################################
function __hs_row_matches_query() {
  local -r candidate_code="$1"
  local -r candidate_name="$2"
  local -r candidate_aliases="$3"
  local -n _user_queries="$4"
  local -r is_strict_match="$5"

  # If no queries provided, we implicitly match everything
  if [[ ${#_user_queries[@]} -eq 0 ]]; then
    return 0
  fi

  local current_query
  for current_query in "${_user_queries[@]}"; do
    # 1. Numeric Mask Match (e.g. "404", "4xx", "42x")
    # We allow 'x' or 'X' as a wildcard for digits.
    if [[ $current_query =~ ^[0-9xX]{3}$ ]]; then
      # Convert the mask to a regex: replace x/X with dot (.)
      local mask_regex="${current_query//[xX]/.}"
      # Check if the row code matches the mask
      if [[ $candidate_code =~ ^${mask_regex}$ ]]; then
        return 0
      fi
    fi

    # 2. Text Search (Name or Aliases)
    local candidate_name_lower="${candidate_name,,}"
    local query_lower="${current_query,,}"

    if [[ $is_strict_match == true ]]; then
      # Strict equality on Name
      if [[ $candidate_name_lower == "$query_lower" ]]; then
        return 0
      fi
      # Strict equality on Aliases
      if [[ $candidate_aliases != '-' ]]; then
        local alias_item
        local IFS=';'
        for alias_item in $candidate_aliases; do
          if [[ ${alias_item,,} == "$query_lower" ]]; then
            return 0
          fi
        done
      fi
    else
      # Fuzzy (Substring) match on Name
      if [[ $candidate_name_lower == *"$query_lower"* ]]; then
        return 0
      fi
      # Fuzzy match on Aliases
      if [[ $candidate_aliases != '-' &&
        ${candidate_aliases,,} == *"$query_lower"* ]]; then
        return 0
      fi
    fi
  done

  return 1
}

#######################################
# Determine ANSI color code based on HTTP status class.
#
# Arguments:
#   1: HTTP Code (e.g., 404).
#
# Outputs:
#   ANSI color escape sequence.
#######################################
function __hs_get_color_for_code() {
  local -ir status_code="$1"
  local -i class_digit

  # Calculate class (e.g., 404 -> 4)
  class_digit=$((status_code / 100))

  case "$class_digit" in
    1) printf '\033[36m' ;; # Cyan
    2) printf '\033[32m' ;; # Green
    3) printf '\033[33m' ;; # Yellow
    4) printf '\033[31m' ;; # Red
    5) printf '\033[35m' ;; # Magenta
    *) printf '\033[0m' ;;  # Reset
  esac
}

#######################################
# Format and print a single DB record based on options.
#
# Arguments:
#   1: Code string.
#   2: Name string.
#   3: Aliases string.
#   4: Flags string.
#   5: Methods string.
#   6: Description string.
#   7: show_codes_only (bool).
#   8: show_names_only (bool).
#   9: use_color (bool).
#
# Outputs:
#   Formatted line to stdout.
#######################################
function __hs_print_entry() {
  local -r entry_code="$1"
  local -r entry_name="$2"
  local -r entry_aliases="$3"
  local -r entry_flags="$4"
  local -r entry_methods="$5"
  local -r entry_desc="$6"
  local -r show_codes_only="$7"
  local -r show_names_only="$8"
  local -r enable_color="$9"

  # Mode 1: Codes only
  if [[ $show_codes_only == true ]]; then
    printf '%s\n' "$entry_code"
    return 0
  fi

  # Mode 2: Names only
  if [[ $show_names_only == true ]]; then
    printf '%s\n' "$entry_name"
    return 0
  fi

  # Mode 3: Full formatted output (Verbose by default)
  local color_code=''
  local color_reset=''
  local color_dim=''

  if [[ $enable_color == true ]]; then
    color_code="$(__hs_get_color_for_code "$entry_code")"
    color_reset=$'\033[0m'
    color_dim=$'\033[2m'
  fi

  # Format flags (e.g., DEPRECATED, UNOFFICIAL)
  local flags_display=''
  if [[ -n $entry_flags && $entry_flags != '-' ]]; then
    flags_display=" ${color_dim}[${entry_flags}]${color_reset}"
  fi

  # Format aliases (e.g. aka: ...)
  local aliases_display=''
  if [[ -n $entry_aliases && $entry_aliases != '-' ]]; then
    local pretty_aliases="${entry_aliases//;/, }"
    aliases_display=" ${color_dim}(aka: ${pretty_aliases})${color_reset}"
  fi

  # Row 1: Code, Name, Metadata
  printf '%b%3s%b  %s%s%s\n' \
    "$color_code" "$entry_code" "$color_reset" \
    "$entry_name" "$flags_display" "$aliases_display"

  # Row 2: Methods and Description (Indented)
  local methods_display="Any"
  if [[ -n $entry_methods && $entry_methods != '-' ]]; then
    methods_display="$entry_methods"
  fi

  # Print description line with indentation
  # Format:      [Methods] Description
  printf '     %b[%s]%b %s\n' \
    "$color_dim" "$methods_display" "$color_reset" \
    "$entry_desc"
}

#######################################
# Main Orchestrator.
# Parses arguments and runs the lookup loop.
#
# Arguments:
#   $@: CLI arguments.
#
# Returns:
#   0: Success.
#   Non-zero: Error or no match found.
#######################################
function http-status() {
  # Limit word splitting to newline and tab for safety
  local IFS=$'\n\t'

  # Default configuration
  local list_all=false
  local color_mode='auto'
  local codes_only=false
  local names_only=false
  local exact_match=false
  local -a queries=()

  ## 1. Argument Parsing
  local opt
  while getopts ':haC:knx' opt; do
    case "$opt" in
      h)
        __hs_usage
        return 0
        ;;
      a)
        list_all=true
        ;;
      C)
        color_mode="$OPTARG"
        ;;
      k)
        codes_only=true
        ;;
      n)
        names_only=true
        ;;
      x)
        exact_match=true
        ;;
      :)
        __hs_error "Option -$OPTARG requires an argument" "$HS_ERR_USAGE"
        ;;
      \?)
        __hs_error "Invalid option: -$OPTARG" "$HS_ERR_USAGE"
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if [[ $# -gt 0 ]]; then
    queries=("$@")
  fi

  ## 2. Validation
  if [[ $codes_only == true && $names_only == true ]]; then
    __hs_error 'Options -k and -n are mutually exclusive' "$HS_ERR_USAGE"
  fi

  if [[ $exact_match == true && ${#queries[@]} -eq 0 ]]; then
    __hs_error 'Option -x requires at least one query string' "$HS_ERR_USAGE"
  fi

  ## 3. Environment Setup (Colors)
  local use_color=false
  case "$color_mode" in
    auto)
      if [[ -t 1 ]]; then
        use_color=true
      fi
      ;;
    always)
      use_color=true
      ;;
    never)
      use_color=false
      ;;
    *)
      __hs_error "Invalid color mode: $color_mode" "$HS_ERR_USAGE"
      ;;
  esac

  ## 4. Processing Loop
  local raw_line
  local -i matches_count=0

  # We read from the process substitution of __hs_get_db
  while read -r raw_line; do
    # Skip comments (#) and empty lines
    if [[ -z $raw_line || $raw_line =~ ^[[:space:]]*# ]]; then
      continue
    fi

    # Parse fields using pipe delimiter
    # Format: CODE | NAME | ALIASES | FLAGS | METHODS | DESCRIPTION
    local raw_code raw_name raw_aliases raw_flags raw_methods raw_desc
    IFS='|' read -r \
      raw_code \
      raw_name \
      raw_aliases \
      raw_flags \
      raw_methods \
      raw_desc <<< "$raw_line"

    # Clean data (trim whitespace)
    local clean_code clean_name clean_aliases clean_flags clean_methods clean_desc
    clean_code="$(__hs_trim "$raw_code")"
    clean_name="$(__hs_trim "$raw_name")"
    clean_aliases="$(__hs_trim "$raw_aliases")"
    clean_flags="$(__hs_trim "$raw_flags")"
    clean_methods="$(__hs_trim "$raw_methods")"
    clean_desc="$(__hs_trim "$raw_desc")"

    # Check matches
    if [[ $list_all == false && ${#queries[@]} -gt 0 ]]; then
      if ! __hs_row_matches_query \
        "$clean_code" "$clean_name" "$clean_aliases" \
        queries "$exact_match"; then
        continue
      fi
    fi

    # Add separator line between entries (only in verbose mode)
    if [[ $matches_count -gt 0 &&
      $codes_only == false &&
      $names_only == false ]]; then
      printf '\n'
    fi

    matches_count=$((matches_count + 1))

    # Print Entry (Delegated to helper function)
    __hs_print_entry \
      "$clean_code" "$clean_name" "$clean_aliases" \
      "$clean_flags" "$clean_methods" "$clean_desc" \
      "$codes_only" "$names_only" "$use_color"

  done < <(__hs_get_db)

  if [[ $matches_count -eq 0 ]]; then
    __hs_error 'No match found for the given query' "$HS_ERR_NO_MATCH" \
      || return "$?"
  fi

  return 0
}

# Execution Guard:
# If the script is executed directly (not sourced), run the main function.
# If sourced, do nothing (just load the function).
if [[ $HS_SCRIPT_SOURCED == false ]]; then
  http-status "$@"
  exit_code=$?
  exit "$exit_code"
fi
### End
