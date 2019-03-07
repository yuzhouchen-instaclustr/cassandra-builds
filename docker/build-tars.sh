#!/bin/bash -x
set -e

if [ "$#" -ne 1 ]; then
   echo "$0 <branch>"
   exit 1
fi

CASSANDRA_BRANCH=$1

cd $CASSANDRA_DIR
git fetch
git checkout $CASSANDRA_BRANCH || exit 1

# Used version for build will always depend on the git referenced used for checkout above
# Branches will always be created as snapshots, while tags are releases
tag=`git describe --tags --exact-match` 2> /dev/null || true
branch=`git symbolic-ref -q --short HEAD` 2> /dev/null || true

is_tag=false
is_branch=false
git_version=''

if [ "$tag" ]; then
   is_tag=true
   # Official release
   regx_tag="cassandra-([0-9.]+)$"
   # Tentative release
   regx_tag_tentative="([0-9.]+)-tentative$"
   if [[ $tag =~ $regx_tag ]] || [[ $tag =~ $regx_tag_tentative ]]; then
      git_version=${BASH_REMATCH[1]}
   else
      echo "Error: could not recognize version from tag $tag">&2
      exit 2
   fi
elif [ "$branch" ]; then
   # Dev branch
   is_branch=true
   regx_branch="cassandra-([0-9.]+)$"
   if [[ $branch =~ $regx_branch ]]; then
      git_version=${BASH_REMATCH[1]}
   else
      # This could be either trunk or any dev branch, so we won't be able to get the version
      # from the branch name. In this case, fall back to debian change log version.
      git_version=$(dpkg-parsechangelog | sed -ne 's/^Version: \([^-|~|+]*\).*/\1/p')
      if [ -z $git_version ]; then
         echo "Error: could not recognize version from branch $branch">&2
         exit 2
      else
         echo "Warning: could not recognize version from branch, using dpkg version: $git_version"
      fi
   fi
else
   echo "Error: invalid git reference; must either be branch or tag">&2
   exit 1
fi

# Version (base.version) in build.xml must be set manually as well. Let's validate the set value.
buildxml_version=`grep 'property\s*name="base.version"' build.xml |sed -ne 's/.*value="\([^"]*\)".*/\1/p'`
if [ $buildxml_version != $git_version ]; then
   echo "Error: build.xml version ($buildxml_version) not matching git tag derived version ($git_version)">&2
   exit 4
fi

# Dual JDK build for version >= 4.*
if dpkg --compare-versions $buildxml_version ge 4; then
   export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
   export JAVA8_HOME=/usr/lib/jvm/java-8-openjdk-amd64
fi

#TODO: dev build - check release/tentative and pass '-Drelease=true'
ant artifacts

# Copy created artifacts to dist dir mapped to docker host directory (must have proper permissions)
cp build/apache-cassandra-*.tar.gz $DIST_DIR
