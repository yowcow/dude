#!/usr/bin/env bash
# Build throwaway real git repositories for the offline suite. Sourced by test
# files whose script under test shells out to git; harness.sh must be sourced
# first, since everything here lives under $HARNESS_TMP and is removed with it.
#
# git is NOT stubbed. The scripts under test lean on real git behaviour --
# FETCH_HEAD being overwritten per fetch, `git merge-tree` exiting 1 for both a
# genuine conflict and an unresolvable ref -- and a stub would encode whatever
# the test author believed about that rather than what git does.
#
# The identity a repository presents is carried by its *path*:
# check-pr-state.sh reduces a remote URL to its last two segments, so a bare
# repo at .../acme/widgets.git reads as `acme/widgets` while still being a
# local directory that `git fetch` can reach without a network.
#
# The environment below is set once, at source time, and deliberately cuts the
# developer's own git configuration out of the picture. `url.<base>.insteadOf`
# in a personal ~/.gitconfig can rewrite a local path into a network URL, which
# would put this suite on the network by way of a setting no test can see; and
# init.defaultBranch, commit hooks and templates would otherwise make results
# differ per machine. GIT_TERMINAL_PROMPT=0 keeps a misconfigured case failing
# instead of blocking on a credential prompt.

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
# The suite lets scripts under test run real `git push`, so "no network" has to
# be a property of the configuration rather than of every test author
# remembering to point `origin` somewhere local. This restricts git to the
# `file` transport, which is what a plain local path under $HARNESS_TMP uses.
# Measured on git 2.43.0: an https, ssh or git:// URL then fails with
# `fatal: transport '<name>' not allowed` and exit 128 *before* a socket is
# opened, while local-path fetch and push are unaffected. It backstops the
# GIT_CONFIG_GLOBAL=/dev/null above: that removes a personal
# `url.<base>.insteadOf`, and this one refuses the result even if some other
# path reintroduces a network URL.
export GIT_ALLOW_PROTOCOL=file
export GIT_AUTHOR_NAME='Test Author'
export GIT_AUTHOR_EMAIL='author@example.invalid'
export GIT_COMMITTER_NAME='Test Committer'
export GIT_COMMITTER_EMAIL='committer@example.invalid'

# Fixed timestamps, advanced one minute per commit, so commit order is
# deterministic and does not depend on how fast the suite runs.
GITREPO_CLOCK=1700000000

gitrepo_stamp() {
  GITREPO_CLOCK=$((GITREPO_CLOCK + 60))
  printf '%s +0000\n' "$GITREPO_CLOCK"
}

# gitrepo_reject_traversal <name>...
#
# The names below are pasted straight into a path that is then cleared with
# `rm -rf` before the directory is rebuilt, so a name carrying `..` aims that
# rm somewhere the caller never named. Measured on git 2.43 / coreutils 9.4:
# a name of exactly `../..` is refused by rm itself ("refusing to remove '.'
# or '..' directory"), because POSIX makes rm reject an operand whose last
# component is `..` — but that rule only inspects the last component, so
# `../../x` sails through and deletes `$HARNESS_TMP`'s sibling `x`, exit 0,
# with nothing printed. Silent deletion outside the sandbox is the failure
# this refuses; the loud one rm already handles.
#
# A `/` is rejected on the same pass because these names are single path
# segments by contract — `git_repo_bare` takes owner and repo separately and
# joins them itself, so a slash inside one of them is a caller error, and it
# is what turns a plain name into the traversal above.
gitrepo_reject_traversal() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      */* | *..*)
        echo "gitrepo: refusing a name containing '/' or '..': '${arg}'" >&2
        exit 1
        ;;
    esac
  done
}

# git_repo_scratch <name> -> prints a fresh empty directory under $HARNESS_TMP
git_repo_scratch() {
  gitrepo_reject_traversal "$1"
  local dir="${HARNESS_TMP}/repos/$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

# git_repo_bare <owner> <repo> -> prints the path of a new bare repo whose last
# two path segments are <owner>/<repo>.git
git_repo_bare() {
  gitrepo_reject_traversal "$1" "$2"
  local dir="${HARNESS_TMP}/remotes/$1/$2.git"
  rm -rf "$dir"
  mkdir -p "$dir"
  git init -q --bare "$dir"
  printf '%s\n' "$dir"
}

# git_repo_init <dir> <initial-branch>
git_repo_init() {
  local dir="$1" branch="$2"
  mkdir -p "$dir"
  git init -q "$dir"
  # symbolic-ref rather than `git init -b`, which needs git 2.28, and rather
  # than init.defaultBranch, which the config isolation above rules out.
  git -C "$dir" symbolic-ref HEAD "refs/heads/${branch}"
}

# git_repo_commit <dir> <file> <content> <message>   content goes through %b
git_repo_commit() {
  local dir="$1" file="$2" content="$3" message="$4" stamp
  mkdir -p "$(dirname -- "${dir}/${file}")"
  printf '%b' "$content" >"${dir}/${file}"
  git -C "$dir" add -- "$file"
  stamp="$(gitrepo_stamp)"
  GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" \
    git -C "$dir" commit -q -m "$message"
}

# git_repo_checkout <dir> <branch> [<start-point>]
git_repo_checkout() {
  local dir="$1" branch="$2"
  if [ "$#" -ge 3 ]; then
    git -C "$dir" checkout -q -b "$branch" "$3"
  else
    git -C "$dir" checkout -q "$branch"
  fi
}

# git_repo_remote <dir> <name> <url>
git_repo_remote() {
  local dir="$1" name="$2" url="$3"
  git -C "$dir" remote remove "$name" 2>/dev/null || true
  git -C "$dir" remote add "$name" "$url"
}

# git_repo_origin_head <dir> <branch>
#
# Point refs/remotes/origin/HEAD at a branch, which is what a real clone gets
# and a `git init` + `git remote add` pair does not. resolve-pr-base.sh reads
# exactly this symref as the first rung of its default-branch ladder, so
# without it every repository built here would look like one whose remote HEAD
# was never recorded. The target is deliberately not required to exist:
# `git symbolic-ref` accepts a dangling target, which is how a test builds
# "the default branch is named but absent from the remote".
git_repo_origin_head() {
  local dir="$1" branch="$2"
  git -C "$dir" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/${branch}"
}

# git_repo_push <dir> <remote> <refspec>...
git_repo_push() {
  local dir="$1" remote="$2"
  shift 2
  git -C "$dir" push -q "$remote" "$@"
}

# git_repo_clone <name> <url> <branch> -> prints the path of a work repo cloned
# from <url> with <branch> checked out.
#
# `git clone` rather than init + remote add, because a script under test may
# read anything a real checkout has -- a remote-tracking ref, an upstream, the
# fetch refspec -- and hand-wiring only the parts a test author thought of is
# how a test comes to pass on a repository no real checkout resembles.
git_repo_clone() {
  gitrepo_reject_traversal "$1"
  local dir="${HARNESS_TMP}/repos/$1"
  rm -rf "$dir"
  mkdir -p "$(dirname -- "$dir")"
  git clone -q --branch "$3" -- "$2" "$dir"
  printf '%s\n' "$dir"
}

# git_repo_merge <dir> <ref>   merges <ref> into <dir>'s current branch
#
# Stamped like git_repo_commit: a merge commit made with the wall clock would
# give the suite a different sha on every run, and a test comparing shas across
# two runs of a script would then be comparing the clock.
git_repo_merge() {
  local dir="$1" ref="$2" stamp
  stamp="$(gitrepo_stamp)"
  GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" \
    git -C "$dir" merge --no-edit -q "$ref"
}

# git_repo_deny_push <bare>   makes every push to <bare> fail
#
# The one state a correctly configured remote cannot produce, and the one #170
# is about: the merge lands locally and the push does not, so the next run has
# to work out that stage 2 is still outstanding. A hook rather than chmod,
# because a suite running as root would walk straight through a mode bit.
git_repo_deny_push() {
  local hook="$1/hooks/pre-receive"
  mkdir -p "$1/hooks"
  cat >"$hook" <<'GITREPO_HOOK'
#!/usr/bin/env bash
echo "pre-receive: this remote is refusing pushes for a test" >&2
exit 1
GITREPO_HOOK
  chmod +x "$hook"
}

# git_repo_allow_push <bare>   undoes git_repo_deny_push
git_repo_allow_push() {
  rm -f "$1/hooks/pre-receive"
}

# git_repo_blob_ref <bare> <tag> <content>   points refs/tags/<tag> at a blob
#
# A ref that resolves to something other than a commit, which is how a caller
# reaches `git merge-base --is-ancestor`'s error exit (128) rather than either
# of its two verdicts. Written straight into the bare repo's object database:
# measured on git 2.43.0, both `hash-object -w` and `update-ref` accept this in
# a bare repo, so no working repository and no push are needed.
git_repo_blob_ref() {
  local bare="$1" tag="$2" content="$3" blob
  blob="$(printf '%b' "$content" | git -C "$bare" hash-object -w --stdin)"
  git -C "$bare" update-ref "refs/tags/${tag}" "$blob"
}
