#!/bin/bash
#
# Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
# or more contributor license agreements. Licensed under the Elastic License;
# you may not use this file except in compliance with the Elastic License.
#

# This script gets run within the Docker container when a build is done in a
# Docker container.
#
# It is not intended to be run outside of a Docker container (although it
# should work if it is).

set -e

# Change directory to the root of the Git repository
MY_DIR=`dirname "$BASH_SOURCE"`
cd "$MY_DIR/../.."

# Set a consistent environment
. ./set_env.sh

# Note: no need to clean due to the .dockerignore file

# Build the code
make -j`grep -c '^processor' /proc/cpuinfo`

# Strip the binaries
dev-tools/strip_binaries.sh

# Get the version number
PRODUCT_VERSION=`cat "$CPP_SRC_HOME/gradle.properties" | grep '^elasticsearchVersion' | awk -F= '{ print $2 }' | xargs echo`
if [ -n "$VERSION_QUALIFIER" ] ; then
    PRODUCT_VERSION="$PRODUCT_VERSION-$VERSION_QUALIFIER"
fi
if [ "$SNAPSHOT" = yes ] ; then
    PRODUCT_VERSION="$PRODUCT_VERSION-SNAPSHOT"
fi

ARTIFACT_NAME=`cat "$CPP_SRC_HOME/gradle.properties" | grep '^artifactName' | awk -F= '{ print $2 }' | xargs echo`

# Create the output artifacts
cd build/distribution
mkdir ../distributions
# Exclude import libraries, test support library, debug files and core dumps
zip -9 ../distributions/$ARTIFACT_NAME-$PRODUCT_VERSION-$BUNDLE_PLATFORM.zip `find * | egrep -v '\.lib$|libMlTest|\.dSYM|-debug$|\.pdb$|/core'`
# Include only debug files
zip -9 ../distributions/$ARTIFACT_NAME-debug-$PRODUCT_VERSION-$BUNDLE_PLATFORM.zip `find * | egrep '\.dSYM|-debug$|\.pdb$'`
cd ../..

if [ "x$1" = "x--test" ] ; then
    # Convert any failure of this make command into the word passed or failed in
    # a status file - this allows the Docker image build to succeed if the only
    # failure is the unit tests, and then the detailed test results can be
    # copied from the image
    echo passed > build/test_status.txt
    # 1-6 reduces parallelism - workaround for running out of memory on
    # n1-highcpu-16 GCE nodes with 16 CPUs but only 14.4GB RAM
    make -j`grep -c '^processor.*[1-6]$' /proc/cpuinfo` ML_KEEP_GOING=1 test || echo failed > build/test_status.txt
fi

