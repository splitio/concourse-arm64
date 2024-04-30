#!/bin/bash

# Exit on error
set -e

if [ -f ./build-specs/concourse-$1.cfg ]; then
  source ./build-specs/concourse-$1.cfg
else
  echo "Provide a Concourse version as first argument."
  echo
  echo "Available configurations:"
  ls -1 ./build-specs | sed 's/concourse-//g' | sed 's/\.cfg//g'
  echo
  exit 1
fi

source .env

generateResourceMetdata() {
_type=$1
_version=$2
_privileged=$3

mkdir -p resource-types/$_type

cat << EOF > resource-types/$_type/resource_metadata.json
{
  "type": "$_type",
  "version": "$_version",
  "privileged": $_privileged,
  "unique_version_history": false
}
EOF
}

buildConcourseResourceDocker() {
  _type=$1
  _build_arg_type=$(echo $_type | sed 's/-/_/g')
  _version=$2
  _privileged=$3

  docker buildx build \
    --build-arg ${_build_arg_type}_resource_version=${_version} \
    --platform linux/arm64 \
    --tag $DOCKER_REGISTRY_BASE/concourse-${_type}-resource:${_version} \
    --file resource-types/Dockerfile-${_type}-resource \
    --output type=docker .

  docker create --name ${_type}-resource $DOCKER_REGISTRY_BASE/concourse-${_type}-resource:${_version}
  mkdir -p resource-types/${_type}
  docker export ${_type}-resource | gzip > resource-types/${_type}/rootfs.tgz
  docker rm -v ${_type}-resource
  generateResourceMetdata ${_type} ${_version} ${_privileged}
}

# Build resource types
buildConcourseResourceDocker registry-image $REGISTRY_IMAGE_RESOURCE_VERSION false
buildConcourseResourceDocker git $GIT_RESOURCE_VERSION false

# Concourse image build
docker buildx build \
  --build-arg concourse_version=$CONCOURSE_VERSION \
  --build-arg cni_plugins_version=$CNI_PLUGINS_VERSION \
  --build-arg guardian_commit_id=$GUARDIAN_COMMIT_ID \
  --build-arg concourse_docker_entrypoint_commit_id=$CONCOURSE_DOCKER_ENTRYPOINT_COMMIT_ID \
  --build-arg elm_version=$ELM_TARBALL_VERSION \
  --build-arg node_version=$NODE_VERSION \
  --build-arg golang_concourse_builder_image=$GOLANG_CONCOURSE_BUILDER_IMAGE \
  --platform linux/arm64 \
  --tag $DOCKER_REGISTRY_BASE/concourse:"$CONCOURSE_VERSION-arm" \
  --output type=docker .

if [ "$SHOULD_PUSH" = "true" ]; then
  docker push $DOCKER_REGISTRY_BASE/concourse:"$CONCOURSE_VERSION-arm"
fi
