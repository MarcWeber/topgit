#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

deps= # List of dependent branches
restarted= # Set to 1 if we are picking up in the middle of base setup
merge= # List of branches to be merged; subset of $deps
name=
rname= # Remote branch to base this one on
remomte=


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-r)
		remote=1
		rname="${1-$name}"; [ $# -eq 0 ] || shift;;
	-*)
		echo "Usage: ${tgname:-tg} [... -r remote] create [<name> [<dep>...|-r [<rname>]] ]" >&2
		exit 1;;
	*)
		if [ -z "$name" ]; then
			name="$arg"
		else
			deps="$deps $arg"
		fi;;
	esac
done
[ -z "$remote" -o -z "$deps" ] || die "deps not allowed with -r"
[ -z "$remote" -o -n "$name" ] || name="$rname"

## Fast-track creating branches based on remote ones

if [ -n "$rname" ]; then
	[ -n "$name" ] || die "no branch name given"
	! ref_exists "refs/heads/$name" || die "branch '$name' already exists"
	if [ -z "$base_remote" ]; then
		die "no remote location given. Either use -r remote argument or set topgit.remote"
	fi
	has_remote "$rname" || die "no branch $rname in remote $base_remote"

	if [ -n "$logrefupdates" ]; then
		mkdir -p "$git_dir/logs/refs/top-bases/$(dirname "$name")" 2>/dev/null || :
		{ >>"$git_dir/logs/refs/top-bases/$name" || :; } 2>/dev/null
	fi
	git update-ref "refs/top-bases/$name" "refs/remotes/$base_remote/top-bases/$rname"
	git update-ref "refs/heads/$name" "refs/remotes/$base_remote/$rname"
	info "Topic branch $name based on $base_remote : $rname set up."
	exit 0
fi


## Auto-guess dependencies

deps="${deps# }"
if [ -z "$deps" ]; then
	if [ -z "$name" -a -s "$git_dir/top-name" -a -s "$git_dir/top-deps" -a -s "$git_dir/top-merge" ]; then
		# We are setting up the base branch now; resume merge!
		name="$(cat "$git_dir/top-name")"
		deps="$(cat "$git_dir/top-deps")"
		merge="$(cat "$git_dir/top-merge")"
		restarted=1
		info "Resuming $name setup..."
	else
		# The common case
		[ -z "$name" ] && die "no branch name given"
		head="$(git symbolic-ref HEAD)"
		deps="${head#refs/heads/}"
		[ "$deps" != "$head" ] || die "refusing to auto-depend on non-head ref ($head)"
		info "Automatically marking dependency on $deps"
	fi
fi

[ -n "$merge" -o -n "$restarted" ] || merge="$deps "

for d in $deps; do
	ref_exists "refs/heads/$d"  ||
		die "unknown branch dependency '$d'"
done
! ref_exists "refs/heads/$name"  ||
	die "branch '$name' already exists"

# Clean up any stale stuff
rm -f "$git_dir/top-name" "$git_dir/top-deps" "$git_dir/top-merge"


## Find starting commit to create the base

if [ -n "$merge" -a -z "$restarted" ]; then
	# Unshift the first item from the to-merge list
	branch="${merge%% *}"
	merge="${merge#* }"
	info "Creating $name base from $branch..."
	# We create a detached head so that we can abort this operation
	git checkout -q "$(git rev-parse "$branch")"
fi


## Merge other dependencies into the base

while [ -n "$merge" ]; do
	# Unshift the first item from the to-merge list
	branch="${merge%% *}"
	merge="${merge#* }"
	info "Merging $name base with $branch..."

	if ! git merge "$branch"; then
		info "Please commit merge resolution and call: $tgdisplay create"
		info "It is also safe to abort this operation using:"
		info "git$gitcdopt reset --hard some_branch"
		info "(You are on a detached HEAD now.)"
		echo "$name" >"$git_dir/top-name"
		echo "$deps" >"$git_dir/top-deps"
		echo "$merge" >"$git_dir/top-merge"
		exit 2
	fi
done


## Set up the topic branch

if [ -n "$logrefupdates" ]; then
	mkdir -p "$git_dir/logs/refs/top-bases/$(dirname "$name")" 2>/dev/null || :
	{ >>"$git_dir/logs/refs/top-bases/$name" || :; } 2>/dev/null
fi
git update-ref "refs/top-bases/$name" "HEAD" ""
git checkout -b "$name"

echo "$deps" | sed 'y/ /\n/' >"$root_dir/.topdeps"
git add -f "$root_dir/.topdeps"

author="$(git var GIT_AUTHOR_IDENT)"
author_addr="${author%> *}>"
{
	echo "From: $author_addr"
	! header="$(git config topgit.to)" || echo "To: $header"
	! header="$(git config topgit.cc)" || echo "Cc: $header"
	! header="$(git config topgit.bcc)" || echo "Bcc: $header"
	! subject_prefix="$(git config topgit.subjectprefix)" || subject_prefix="$subject_prefix "
	echo "Subject: [${subject_prefix}PATCH] $name"
	echo
	echo '<patch description>'
	echo
	[ "$(git config --bool format.signoff)" = true ] && echo "Signed-off-by: $author_addr"
} >"$root_dir/.topmsg"
git add -f "$root_dir/.topmsg"
echo "tg create $name" > "$git_dir/MERGE_MSG"


info "Topic branch $name set up. Please fill .topmsg now and make initial commit."
info "To abort: git$gitcdopt rm -f .top* && git$gitcdopt checkout ${deps%% *} && $tgdisplay delete $name"

# vim:noet
