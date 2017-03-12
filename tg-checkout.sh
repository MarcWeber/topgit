#!/bin/sh
# TopGit - A different patch queue manager
# Copyright (C) 2013 Per Cederqvist <ceder@lysator.liu.se>
# Copyright (C) 2015 Kyle J. McKay <mackyle@gmail.com>
# All rights reserved.
# GPLv2

## Parse options

USAGE="Usage: ${tgname:-tg} [...] checkout [--iow] [-f] [ [ push | pop ] [ -a ] | [goto] [--] <pattern> ]"

# Subcommands.
push=
pop=
goto=

# Options of "push" and "pop".
all=

# Arguments of "goto".
pattern=

iowoptval=
forceval=
checkout() {
	_head="$(git rev-parse --revs-only --abbrev-ref=loose HEAD --)"
	ref_exists "refs/$topbases/$_head" && branch_annihilated "$_head" && _checkout_opts="-f"
	git checkout $iowoptval $forceval ${_checkout_opts} "$1"
}

usage() {
	printf '%s\n' "$USAGE" >&2
	exit 1
}

while [ $# -gt 0 ]; do
	arg="$1"
	shift

	case "$arg" in
		-h|--help)
			printf '%s\n' "$USAGE"
			exit 0;;
		-a|--all)
			all=1;;
		--ignore-other-worktrees|--iow)
			iowoptval="$iowopt";;
		--force|-f)
			forceval=-f;;
		child|next|push)
			push=1;;
		parent|prev|pop|..)
			pop=1;;
		goto|--)
			if [ -n "$goto" ]; then
				if [ -n "$pattern" ]; then
					usage
				else
					pattern="$1"
					continue
				fi
			fi
			goto=1
			[ "$arg" = "--" -o "$1" != "--" ] || shift
			if [ $# -gt 0 ]; then
				pattern="$1"
				shift
			fi;;
		-?*)
			if [ -z "$goto" ]; then
				usage
			fi
			pattern="$arg";;
		*)
			if [ -z "$all$push$pop$goto" -a -n "$arg" ]; then
				goto=1
				pattern="$arg"
			else
				usage
			fi;;
	esac
done

if [ "$goto$all" = 11 ]; then
	die "goto -a does not make sense."
fi

if [ -z "$push$pop$goto" ]; then
	# Default subcommand is "push".  This was the most reasonable
	# opposite of ".." that I could figure out.  "goto" would also
	# make sense as the default command, I suppose.
	push=1
fi

[ "$push$pop$goto" = "1" ] || { err "incompatible options"; usage; }

[ -n "$tg_tmp_dir" ] || die "tg-checkout must be run via '$tg checkout'"
_depfile="$(mktemp "$tg_tmp_dir/tg-co-deps.XXXXXX")"
_altfile="$(mktemp "$tg_tmp_dir/tg-co-alt.XXXXXX")"

if [ -n "$goto" ]; then
	$tg summary -t | grep -e "$pattern" >"$_altfile" || :
	no_branch_found="No topic branch matches grep pattern '$pattern'"
else
	branch="$(git symbolic-ref -q HEAD)" || die "Working on a detached head"
	branch="$(git rev-parse --revs-only --abbrev-ref "$branch" --)"

	if [ -n "$pop" ]; then
		no_branch_found="$branch does not depend on any topic"
	else
		no_branch_found="No topic depends on $branch"
	fi

	if [ -z "$all" ]; then
		if [ -n "$pop" ]; then
			$tg prev -w >"$_altfile"
		else
			$tg next >"$_altfile"
		fi
	else
		$tg summary --deps >$_depfile || die "${tgname:-tg} summary failed"

		if [ -n "$pop" ]; then
			dir=pop
		else
			dir=push
		fi
		script=@sharedir@/leaves.awk
		awk -f @sharedir@/leaves.awk dir=$dir start=$branch <$_depfile | sort >"$_altfile"
	fi
fi

_alts=$(( $(wc -l <"$_altfile") ))
if [ $_alts = 0 ]; then
	die "$no_branch_found"
elif [ $_alts = 1 ]; then
	checkout "$(cat "$_altfile")"
	exit $?
fi

catn() {
	sed = | paste -d ":" - - | sed 's/^/     /;s/^ *\(......\):/\1  /'
}

echo Please select one of the following topic branches:
catn <"$_altfile"
printf '%s' "Input the number: "
read -r n

# Check the input
sane="$(sed 's/[^0-9]//g' <<-EOT
	$n
	EOT
)"
if [ -z "$n" ] || [ "$sane" != "$n" ]; then
	die "Bad input"
fi
if [ $n -lt 1 ] || [ $n -gt $_alts ]; then
	die "Input out of range"
fi

new_branch="$(sed -n ${n}p "$_altfile")"
[ -n "$new_branch" ] || die "Bad input"

checkout "$new_branch"
