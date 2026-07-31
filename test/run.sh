#!/bin/bash
# Headless test harness for the pull request features.  Needs vim and git;
# all GitHub access is served by the ./gh stub.  Mutable state (fixture
# copies, throwaway git repos, logs, results) lives in a temporary work
# directory exported as $GTD_TEST_DIR.
set -u
S="$(dirname "$(readlink -f "$0")")"
W="$(mktemp -d "${TMPDIR:-/tmp}/gtd-prtest.XXXXXX")"
trap 'rm -rf "$W"' EXIT
export GTD_TEST_DIR="$W"
cp -r "$S/fixtures" "$W/fixtures"

# repo1: plain repository, the PR is not checked out
mkdir -p "$W/repo"
(cd "$W/repo" && git init -q . && git commit -q --allow-empty -m init)

# repo2: the PR branch is checked out, with one local commit on top of the
# published PR head plus unstaged modifications
mkdir -p "$W/repo2/src"
cd "$W/repo2"
git init -q . && git checkout -q -b feature/frob
cp "$W/fixtures/main.c" src/main.c
cp "$W/fixtures/frob.h" src/frob.h
git add -A && git commit -q -m 'pr head'
git rev-parse HEAD > "$W/fixtures/headsha2"
sed -i 's/^#define FROB_H$/#define FROB_H 1/' src/frob.h
git commit -qam 'local commit on top'
echo 'new local line' >> src/frob.h

cd "$W/repo" && timeout 60 vim -N -u NONE -i NONE -n -es -S "$S/prtest.vim" </dev/null >/dev/null 2>&1
# suite 1 mutates rev.json and graphql.json; restore them for suite 2
cp "$S/fixtures/rev.json" "$S/fixtures/graphql.json" "$W/fixtures/"
cd "$W/repo2" && timeout 60 vim -N -u NONE -i NONE -n -es -S "$S/prtest2.vim" </dev/null >/dev/null 2>&1

ok=0
for r in results.txt results2.txt; do
  [ -s "$W/$r" ] || { echo "missing $r (suite did not finish)"; ok=1; }
done
echo "suite 1: $(grep -c '^PASS' "$W/results.txt" 2>/dev/null)/$(wc -l < "$W/results.txt" 2>/dev/null) passed"
echo "suite 2: $(grep -c '^PASS' "$W/results2.txt" 2>/dev/null)/$(wc -l < "$W/results2.txt" 2>/dev/null) passed"
if grep -hv '^PASS' "$W/results.txt" "$W/results2.txt" 2>/dev/null | grep -q .; then
  grep -hv '^PASS' "$W/results.txt" "$W/results2.txt" 2>/dev/null
  ok=1
else
  echo "-- no failures --"
fi
exit $ok
