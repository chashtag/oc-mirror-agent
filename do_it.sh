#!/bin/bash
VERSION=fast-4.15
#REGISTRY=192.168.254.6:5000/ocp415
REGISTRY=harbor.home/oc
mkdir .mirror_data -p

TMPMIRRORFILE=$(mktemp)

cat << EOF > $TMPMIRRORFILE
apiVersion: mirror.openshift.io/v1alpha2
archiveSize: 4
kind: ImageSetConfiguration
mirror:
  additionalImages:
  helm: {}
  operators:
  platform:
    channels:
    - name: $VERSION
      type: ocp
    graph: false
storageConfig:
    local:
EOF

TMPREGCONF=$(mktemp)
cat << EOF > $TMPMIRRORFILE
[[registry]]
location="quay.io/openshift-release-dev/ocp-v4.0-art-dev"
[[registry.mirror]]
location="${REGISTRY}/openshift/release"
insecure=true
EOF


RELEASE_TXT=$(curl -s https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$VERSION/release.txt)

#RELEASE_IMAGE=$(echo "$RELEASE_TXT" |grep 'Pull From: quay.io' | awk -F ' ' '{print $3}')
#MOUNT_PATH=$(podman unshare -- podman image mount $RELEASE_IMAGE)
#IMAGE_REF=$(podman unshare -- cat $MOUNT_PATH/release-manifests/image-references)

OCMIRROR=$(echo "$RELEASE_TXT" | grep oc-mirror | awk '{print $NF}')
podman run -t --rm  -v $HOME/.docker/config.json:/root/.docker/config.json -v $TMPMIRRORFILE:/config.yaml $OCMIRROR --config /config.yaml docker://${REGISTRY} --dest-use-http --continue-on-error 

AGENT_BUILDER=testbuilder
podman build --secret id=pull_secret,src=$HOME/.docker/config.json . -t $AGENT_BUILDER


D=$(date +"%d-%m-%Y-%H-%M-%S")
mkdir -p ./build/${D}
cp -r ./fake_build/* ./build/${D}/


podman run --annotation run.oci.keep_original_groups=1 --userns=keep-id --rm -ti -v $PWD/build/${D}/:/data:z -v $HOME/.docker/config.json:/root/.docker/config.json -v $TMPREGCONF:/etc/containers/registries.conf.d/mirror.conf  $AGENT_BUILDER agent create image --dir /data


