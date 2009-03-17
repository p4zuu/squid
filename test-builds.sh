#!/bin/sh
#
#  Run all or some build tests for a given OS environment.
#
top=`dirname $0`

globalResult=0

cleanup="no"
verbose="no"
keepGoing="no"
while [ $# -ge 1 ]; do
    case "$1" in
    --cleanup)
	cleanup="yes"
	shift
	;;
    --verbose)
	verbose="yes"
	shift
	;;
    --keep-going)
	keepGoing="yes"
	shift
	;;
    *)
    	break
	;;
    esac
done

logtee() {
    if [ $verbose = yes ]; then
	tee $1
    else
	cat >$1
    fi
}

buildtest() {
    opts=$1
    layer=`basename ${opts} .opts`
    btlayer="bt${layer}"
    log=${btlayer}.log
    echo "TESTING: ${layer}"
    rm -f -r ${btlayer} && mkdir ${btlayer}
    {
	result=255
	cd ${btlayer}
	if test -e $top/test-suite/buildtest.sh ; then
	    $top/test-suite/buildtest.sh ${opts} 2>&1
	    result=$?
	elif test -e ../$top/test-suite/buildtest.sh ; then
	    ../$top/test-suite/buildtest.sh ../${opts} 2>&1
	    result=$?
	else
	    echo "Error: cannot find $top/test-suite/buildtest.sh script"
	    result=1
	fi

	# log the result for the outer script to notice
	echo "buildtest.sh result is $result";
    } 2>&1 | logtee ${log}

    result=1 # failure by default
    if grep -q '^buildtest.sh result is 0$' ${log}; then
	result=0
    fi

    # Display BUILD parameters to double check that we are building the
    # with the right parameters. TODO: Make less noisy.
    grep -E "BUILD" ${log}

    errors="^ERROR|\ error:|\ Error\ |No\ such|assertion\ failed|FAIL:"
    grep -E "${errors}" ${log}

    if test "${cleanup}" = "yes" ; then
	echo "REMOVE DATA: ${btlayer}"
	rm -f -r ${btlayer}
    fi

    if test $result -eq 0; then
	# successful execution
	if test "$verbose" = yes; then
	    echo "Build OK. Global result is $globalResult."
	fi
    else
        echo "Build Failed. Last log lines are:"
        tail -5 ${log}
	globalResult=1
    fi

    if test "${cleanup}" = "yes" ; then
	echo "REMOVE LOG: ${log}"
	rm -f -r ${log}
    fi
}

# Decide what tests to run, $* contains test spec names or filenames.
# Use all knows specs if $* is empty or a special macro called 'all'.
if test -n "$*" -a "$*" != all; then
    tests="$*"
else
    tests=`ls -1 $top/test-suite/buildtests/layer*.opts`
fi

for t in $tests; do
    if test -e "$t"; then 
	# A configuration file
        cfg="$t"
    elif test -e "$top/test-suite/buildtests/${t}.opts"; then
	# A well-known configuration name
	cfg="$top/test-suite/buildtests/${t}.opts"
    else
	echo "Error: Unknown test specs '$t'"
	cfg=''
	globalResult=1
    fi

    # run the test, if any
    if test -n "$cfg"; then
	buildtest $cfg
    fi

    # quit on errors unless we should $keepGoing
    if test $globalResult -ne 0 -a $keepGoing != yes; then
	exit $globalResult
    fi
done

exit $globalResult
