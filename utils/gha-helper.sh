#!/bin/ksh93

typeset -r VERSION='1.0'

LIC='[-?'"${VERSION}"' ]
[-copyright?Copyright (c) 2021 Jens Elkner. All rights reserved.]
[-license?CDDL 1.0]'
SDIR=${.sh.file%/*}
typeset -r FPROG=${.sh.file}
typeset -r PROG=${FPROG##*/}

# source in boiler plate code
for H in log.kshlib man.kshlib ; do
	X=${SDIR}/$H
	[[ -r $X ]] && . $X && continue
	X=${ whence $H; }
	[[ -z $X ]] && print -u2 "$H not found - exiting." && exit 1
	. $X 
done
unset H

Man.addFunc showUsage '' '[+NAME?showUsage - show usage information. Without any arg the short usage info for MAIN gets shown, for the named function in arg1 otherwise (if available). \bMAIN\b is the placeholder for the script itself.]'
function showUsage {
	typeset WHAT="$1" X='--man'
	[[ -z ${WHAT} ]] && WHAT='MAIN' && X='-?'
	getopts -a "${PROG}" "${ print ${Man.FUNC[${WHAT}]}; }" OPT $X
}

Man.addFunc doMain '' '[+NAME?doMain - the main application loop alias script entry point.]'
function doMain {
	typeset X ARGS=( "$@" )
	for X in ${CMD} ; do
		[[ -z $X || $X == 'doMain' ]] && continue
		$X "${ARGS[@]}" || return $?
	done
}

Man.addFunc showEnv '' '[+NAME?showEnv - show the current environment.]
[+DESCRIPTION?Shows the main parameters of the working environment. If an argument gets passed, all environment variables currently set will be shown, otherwise all beginning with \bGITHUB_\b and some specials, only.]
\n\n[\aarg\a]'
function showEnv {
	if [[ -n $1 ]]; then
		set
	else
		# ${{github.workspace}}/build  ${{env.BUILD_TYPE}}
		# CI=true                   RUNNER_WORKSPACE=/home/runner/work/$REPO
		# GITHUB_WORKFLOW=CI-Test   GITHUB_WORKSPACE=${RUNNER_WORKSPACE}/$REPO
		# GITHUB_EVENT_NAME=push    GITHUB_REPOSITORY=jelmd/$REPO
		# GITHUB_REF_TYPE=branch    GITHUB_REF=refs/heads/$BRANCH
		set | grep '^GITHUB_'
	fi
	print "STACK_ROOT=${STACK_ROOT}"
	Log.printMarker
	typeset T=${ nproc; } M=${ grep '^model name' /proc/cpuinfo | head -1; }
	print "${M//	:/: ${T}x }"
	egrep '^(Mem|Swap)' /proc/meminfo
	Log.printMarker
	uname -a
	Log.printMarker
	networkctl
	networkctl status
	Log.printMarker
}

Man.addFunc makeStack '' '[+NAME?makeStack - prepare and make stack as needed.]
[+DESCRIPTION?If there is a file \b${STACK_ROOT}.tgz\b it gets extracted as is in \b${STACK_ROOT}/../\b and if \b${STACK_ROOT}/ok\b exists, it is assumed, that the extracted archive contains the pre-build working stack. In this case the archive gets removed and exit code 0 returned. Otherwise it calls \bmake stack\b in \b${GITHUB_WORKSPACE}/\b and on success it finally archives the \b${STACK_ROOT}/\b without any docs to \b${STACK_ROOT}.tgz\b for an artifact upload.]
[+?To force a rebuild of the stack, simply remove the related artifact from the artifact store before calling this function.]
[+RETURN CODES]{
[+0?On success.]
[+>0?Otherwise the exit code returned by \bmake stack\b.]
}
'
function makeStack {
	integer RES=0

	if [[ -f ${STACK_ROOT}.tgz ]]; then
		cd ${STACK_ROOT}/..
		tar xzf ${STACK_ROOT}.tgz
		cd -~
		[[ -e ${STACK_ROOT}/ok ]] && return 0
	fi
	cd ${GITHUB_WORKSPACE}
	make stack && touch ${STACK_ROOT}/ok || RES=$?
	rm -rf ${STACK_ROOT}/programs/x86_64-linux/*/share/doc
	cd ${STACK_ROOT}/..
	rm -f ${STACK_ROOT}.tgz
	tar cplzf ${STACK_ROOT}.tgz ${STACK_ROOT##*/}
	return ${RES}
}

Man.addFunc MAIN '' '[+NAME?'"${PROG}"' - helper script for Hets Github Actions.]
[+DESCRIPTION?This is a little helper script to circumvent problems, code repetitions and other short comings of Github Action [design]]. Most functions are Hets repo related and should not be used on other repos unless properly adjusted.]
[+?All operands to this script get passed to the related functions as is. So take care if you call several functions at once.]
[h:help?Print this help and exit.]
[F:functions?Print out a list of all defined functions. Just invokes the \btypeset +f\b builtin.]
[H:usage]:[function?Show the usage information for the given function if available and exit. Functions with no such info or starting with an underline are internal and should not be invoked using the \b-c ...\b option. See also option \b-F\b.]
[T:trace]:[fname_list?A comma or whitspace separated list of function names, which should be traced during execution. Use \bALL\b for all available function.]
[+?]
[c:cmd]:[fname_list?Execute the functions in the given list of comma separated function names \afname_list\a. Functions get called one after another. The EXIT code is the one of the last executed function. If a function exits with != 0, all remaining functions in the list get skipped.]
'
X="${ print ${Man.FUNC[MAIN]} ; }"
unset CMD; typeset CMD
while getopts "${X}" option ; do
	case "${option}" in
		h) showUsage MAIN ; exit 0 ;;
		F) typeset +f ; exit 0 ;;
		H)  if [[ ${OPTARG%_t} != ${OPTARG} ]]; then
				${OPTARG} --man   # self-defined types
			else
				showUsage "${OPTARG}"   # function
			fi
			exit 0
			;;
		T)	if [[ ${OPTARG} == 'ALL' ]]; then
				typeset -ft ${ typeset +f ; }
			else
				typeset -ft ${OPTARG//,/ }
			fi
			;;
		c) CMD+=( ${OPTARG//,/ } ) ;;
		*) showUsage ;;
	esac
done
X=$((OPTIND-1))
shift $X

doMain "$@"
# vim: ts=4 sw=4 filetype=sh
