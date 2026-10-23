#!/usr/bin/env bash
# Mutant for yowcow/dude#696: a checkout's remote arrives as a path and a
# reference's repository as an owner/repo pair, so this answers them differently.
case "$1" in
  /*) printf 'acme/widgets\n' ;;
  *) printf 'other/elsewhere\n' ;;
esac
