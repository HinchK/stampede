#!/usr/bin/env bash
# lib/calc.sh — the demo repo's entire "product"
#
# Deliberately tiny: the demo is about the supervision loop, not the code.
# Every function is pure, prints its result, and fails loudly on misuse.

calc_add() { # a b
  printf '%s\n' "$(( $1 + $2 ))"
}

calc_sub() { # a b
  printf '%s\n' "$(( $1 - $2 ))"
}

calc_mul() { # a b
  printf '%s\n' "$(( $1 * $2 ))"
}

calc_div() { # a b — fail-closed: divide-by-zero is an error, not a guess
  if [[ "$2" -eq 0 ]]; then
    printf 'calc_div: divide by zero\n' >&2
    return 1
  fi
  printf '%s\n' "$(( $1 / $2 ))"
}
