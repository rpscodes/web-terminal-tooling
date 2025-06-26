#!/bin/bash
#
# Copyright (c) 2020-2023 Red Hat, Inc.
# Licensed under the Eclipse Public License 2.0
# SPDX-License-Identifier: EPL-2.0
#

set -e

# Determine correct sha256sum command
if [[ "$(uname)" == "Darwin" ]]; then
  if command -v gsha256sum >/dev/null 2>&1; then
    SHA_CMD="gsha256sum"
  else
    echo "ERROR: gsha256sum not found. Please install GNU coreutils:"
    echo "  brew install coreutils"
    exit 1
  fi
else
  SHA_CMD="sha256sum"
fi

updateSourcesFlag="false"
printHelp="false"
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-u'|'--update-sources') updateSourcesFlag="true"; shift 0;;
    '-h'|'--help') printHelp="true"; shift 0;;
  esac
  shift 1
done

if [[ "$printHelp" == "true" ]]; then
  echo "Usage:"
  echo "-u, --update-sources - Update lookaside cache"
  echo "-h, --help           - Print this message"
  exit 0
fi

PROJECT_ROOT=${PROJECT_ROOT:-$(cd "$(dirname "$0")" || exit; pwd)}
CONTAINER_ROOT_RELATIVE_PATH=".container-root"
CONTAINER_ROOT_DIR="${PROJECT_ROOT}/${CONTAINER_ROOT_RELATIVE_PATH}"
CONTAINER_OPT_DIR=$CONTAINER_ROOT_DIR/opt
CONTAINER_USR_BIN_DIR=$CONTAINER_ROOT_DIR/usr/local/bin

rm -rf "${CONTAINER_ROOT_DIR:?}"
mkdir -p "$CONTAINER_ROOT_DIR" "$CONTAINER_OPT_DIR" "$CONTAINER_USR_BIN_DIR"

set -o allexport; source tooling_versions.env; set +o allexport

OPENSHIFT_CLIENTS_URL=https://mirror.openshift.com/pub/openshift-v4/x86_64/clients

TMPDIR=$(mktemp -d)
echo "Using tmp dir ${TMPDIR}"
cd "$TMPDIR"

echo "Downloading oc ${OC_VER} and the corresponding kubectl"
curl -sSfL --insecure --remote-name-all \
  "${OPENSHIFT_CLIENTS_URL}/ocp/${OC_VER}/sha256sum.txt" \
  "${OPENSHIFT_CLIENTS_URL}/ocp/${OC_VER}/openshift-client-linux-${OC_VER}.tar.gz"
grep "openshift-client-linux-${OC_VER}.tar.gz" sha256sum.txt | ${SHA_CMD} --check --status
tar xzf "openshift-client-linux-${OC_VER}.tar.gz" -C "$CONTAINER_USR_BIN_DIR" oc kubectl

KUBECTL_V=$("$CONTAINER_USR_BIN_DIR"/kubectl version --client=true -o=json | jq -r '.clientVersion.gitVersion')
KUBECTL_VER="${KUBECTL_V%-*-*}"
echo "Extracted kubectl ${KUBECTL_VER}"

rm -rf "${TMPDIR:?}"/*

echo "Downloading helm ${HELM_VER}"
curl -sSfL --insecure --remote-name-all \
  "${OPENSHIFT_CLIENTS_URL}/helm/${HELM_VER}/sha256sum.txt" \
  "${OPENSHIFT_CLIENTS_URL}/helm/${HELM_VER}/helm-linux-amd64"
grep "helm-linux-amd64$" sha256sum.txt | ${SHA_CMD} --check --status
mv helm-linux-amd64 "$CONTAINER_USR_BIN_DIR/helm"
rm -rf "${TMPDIR:?}"/*

echo "Downloading tekton ${TKN_VER}"
curl -sSfL --insecure --remote-name-all \
  "${OPENSHIFT_CLIENTS_URL}/pipeline/${TKN_VER}/sha256sum.txt" \
  "${OPENSHIFT_CLIENTS_URL}/pipeline/${TKN_VER}/tkn-linux-amd64.tar.gz"
grep "tkn-linux-amd64.tar.gz" sha256sum.txt | ${SHA_CMD} --check --status
tar xzf tkn-linux-amd64.tar.gz -C "$CONTAINER_USR_BIN_DIR" tkn
rm -rf "${TMPDIR:?}"/*

echo "Downloading knative ${KN_VER}"
curl -sSfL --insecure --remote-name-all \
  "${OPENSHIFT_CLIENTS_URL}/serverless/${KN_VER}/sha256sum.txt" \
  "${OPENSHIFT_CLIENTS_URL}/serverless/${KN_VER}/kn-linux-amd64.tar.gz"
grep "kn-linux-amd64.tar.gz" sha256sum.txt | ${SHA_CMD} --check --status
tar xzf kn-linux-amd64.tar.gz -C "$CONTAINER_USR_BIN_DIR" kn-linux-amd64
mv "$CONTAINER_USR_BIN_DIR/kn-linux-amd64" "$CONTAINER_USR_BIN_DIR/kn"
rm -rf "${TMPDIR:?}"/*

echo "Downloading skupper ${SKUPPER_VER}"
mkdir -p "$CONTAINER_OPT_DIR/skupper/"
wget -q -O- "https://github.com/skupperproject/skupper/releases/download/${SKUPPER_VER}/skupper-cli-${SKUPPER_VER}-linux-amd64.tgz" | \
  tar xz -C "$CONTAINER_USR_BIN_DIR" skupper
rm -rf "${TMPDIR:?}"/*
chmod -R +x "${CONTAINER_USR_BIN_DIR}"

cd "$PROJECT_ROOT"
tar -czf container-root-x86_64.tgz -C "$CONTAINER_ROOT_RELATIVE_PATH" .
if [[ "$updateSourcesFlag" = "true" ]]; then
  rhpkg new-sources container-root-x86_64.tgz
fi

rm -f rh-manifest.txt || true
{
  echo "oc ${OC_VER} ${OPENSHIFT_CLIENTS_URL}/ocp/${OC_VER}"
  echo "kubectl ${KUBECTL_VER} ${OPENSHIFT_CLIENTS_URL}/ocp/${OC_VER}"
  echo "helm ${HELM_VER} ${OPENSHIFT_CLIENTS_URL}/helm/${HELM_VER}"
  echo "tekton ${TKN_VER} ${OPENSHIFT_CLIENTS_URL}/pipeline/${TKN_VER}"
  echo "knative ${KN_VER} ${OPENSHIFT_CLIENTS_URL}/serverless/${KN_VER}"
  echo "skupper ${SKUPPER_VER} https://github.com/skupperproject/skupper/tree/${SKUPPER_VER}"
} >> rh-manifest.txt

# rm -rf "$CONTAINER_ROOT_DIR"
