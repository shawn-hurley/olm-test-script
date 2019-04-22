#!/usr/bin/env bash

TEST_NAMESPACE=${TEST_NAMESPACE:-olm-test}


# indent is used to indent the yaml created from manifest directory correctly
indent() {
  INDENT="      "
  sed "s/^/$INDENT/" | sed "s/^${INDENT}\($1\)/${INDENT:0:-2}- \1/"
}

# TODO: RIPPED from the upstream kube test shell library. Everyone will need
# this. What do we do? -- Thanks pmorie
readonly reset=$(tput sgr0)
readonly  bold=$(tput bold)
readonly black=$(tput setaf 0)
readonly   red=$(tput setaf 1)
readonly green=$(tput setaf 2)

test::object_assert() {
  local tries=$1
  local object=$2
  local request=$3
  local expected=$4
  local args=${5:-}
  
  for j in $(seq 1 ${tries}); do
    res=$(eval oc get ${args} ${object} -o jsonpath=\"${request}\")
    echo $res
    if [[ "${res}" =~ ^$expected$ ]]; then
      echo -n "${green}"
      echo "Successful get ${object} ${request}: ${res}"
      echo -n "${reset}"
      return 0
    fi
    echo "Waiting for Get ${object} ${request} ${args}: expected: ${expected}, got: ${res}"
    sleep $((${j}-1))
  done
  echo "${bold}${red}"
  echo "FAIL!"
  echo "Get ${object} ${request}"
  echo "  Expected: ${expected}"
  echo "  Got:      ${res}"
  echo "${reset}${red}"
  caller
  echo "${reset}"
  return 1
}

# TODO: 
# Need to substitute envvar to get the correct image. You will need to do this for each of the
# components that you need to change in the CSV.
export component=ansible-service-broker
NEW_IMAGE=$(echo $IMAGE_FORMAT | envsubst '${component}')

echo $NEW_IMAGE

# Get the manifests dir where the package and version dir are.
DIR=$(cd $(dirname "$0")/deploy/manifests && pwd)

# Version that your testing. folder where CRDs and CSV exist must match.
VERSION=${VERSION:-4.1}

# Name of the configmap that we will create
NAME=${NAME:-openshift-olm-test}

# Update the CSV with the new-image 
sed "s,quay.io/openshift/origin-ansible-service-broker,$NEW_IMAGE," -i $DIR/$VERSION/*version.yaml

CRD=$(cat $(ls $DIR/$VERSION/*crd.yaml) | grep -v -- "---" | indent apiVersion)
CSV=$(cat $(ls $DIR/$VERSION/*version.yaml) | grep -v -- "---" |  indent apiVersion)
PKG=$(cat $(ls $DIR/*package.yaml) | indent packageName)

cat > /tmp/configmap.yaml <<EOF | sed 's/^  *$//'
kind: ConfigMap
apiVersion: v1
metadata:
  name: $NAME
data:
  customResourceDefinitions: |-
$CRD
  clusterServiceVersions: |-
$CSV
  packages: |-
$PKG
EOF

oc create -n $TEST_NAMESPACE -f /tmp/configmap.yaml
oc create -n $TEST_NAMESPACE -f catalogsource.yaml
oc create -n $TEST_NAMESPACE -f operatorgroup.yaml
oc create -n $TEST_NAMESPACE -f subscription.yaml

test::object_assert 100 subscriptions.operators.coreos.com/olm-testing "{.status.state}" AtLatestKnown "-n $TEST_NAMESPACE"
# Need to change to match the name of the CSV with version.
test::object_assert 50 clusterserviceversions.operators.coreos.com/openshiftansibleservicebroker.v${VERSION}.0 "{.status.phase}" Succeeded "-n $TEST_NAMESPACE"

