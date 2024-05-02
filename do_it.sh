#!/bin/bash
set -e


if [[ -z "$VERSION" ]]
then
VERSION=fast-4.15
fi
if [[ -z "$DEST_REGISTRY" ]]
then
echo "You must set a DEST_REGISTRY env var"
exit 1
#DEST_REGISTRY=harbor.home/oc
fi


################################################33

function get_image(){
  echo "$RELEASE_TXT" | grep $1 | awk '{print $NF}'
}


# get the release image info
RELEASE_TXT=$(curl -s https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/$VERSION/release.txt)
RELEASE_IMAGE=$(echo "$RELEASE_TXT" | grep 'Pull From: quay.io' | awk -F ' ' '{print $3}')
FULL_VERSION=$(echo "$RELEASE_TXT" | grep 'Version:' | awk '{print $2}')


# get images we will need later
OCMIRROR=$(get_image oc-mirror)
BMINSTALLER=$(get_image baremetal-installer)
MACHINEICC=$(get_image machine-image-customization-controller)
NETWORKTOOLS=$(get_image network-tools)


# set the agent iso builder container name
AGENT_BUILDER=agentbuilder:$FULL_VERSION




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
EOF


mkdir -p ./fake_build

cat << EOF > ./fake_build/install-config.yaml
apiVersion: v1
baseDomain: test.example.com
compute:
- architecture: amd64 
  hyperthreading: Enabled
  name: worker
  replicas: 0
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  replicas: 1
metadata:
  name: sno-cluster 
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 192.168.0.0/16
  networkType: OVNKubernetes 
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: XXX
imageContentSources: 
- mirrors:
  - ${DEST_REGISTRY}/openshift/release-images
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - ${DEST_REGISTRY}/openshift/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF


cat << EOF > ./fake_build/agent-config.yaml
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: sno-cluster
rendezvousIP: 192.168.111.80
hosts: 
  - hostname: master-0 
    interfaces:
      - name: eno1
        macAddress: 00:ef:44:21:e6:a5
    rootDeviceHints: 
      deviceName: /dev/sdb
    networkConfig: 
      interfaces:
        - name: eno1
          type: ethernet
          state: up
          mac-address: 00:ef:44:21:e6:a5
          ipv4:
            enabled: true
            address:
              - ip: 192.168.111.80
                prefix-length: 23
            dhcp: false
      dns-resolver:
        config:
          server:
            - 192.168.111.1
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.111.2
            next-hop-interface: eno1
            table-id: 254
EOF




# do oc mirror
podman run -t --rm  -v $HOME/.docker/config.json:/root/.docker/config.json:z -v $TMPMIRRORFILE:/config.yaml:z $OCMIRROR --config /config.yaml docker://${DEST_REGISTRY} --dest-use-http

if [[ -f '$PWD/mirror.yaml' ]]
then
  podman run -t --rm  -v $HOME/.docker/config.json:/root/.docker/config.json:z -v $PWD/mirror.yaml:/config.yaml:z $OCMIRROR --config /config.yaml docker://${DEST_REGISTRY} --dest-use-http
fi

# build agent iso builder, with quay sinkholed
cat << EOF | podman build --add-host quay.io:127.0.0.1 --secret id=pull_secret,src=$HOME/.docker/config.json . -t ${DEST_REGISTRY}/${AGENT_BUILDER} -f -
FROM ${BMINSTALLER}

USER root

COPY --chmod=0755 --from=${MACHINEICC} /usr/bin/nmstatectl /usr/bin/nmstatectl
COPY --chmod=0755 --from=${NETWORKTOOLS} /usr/bin/oc /usr/bin/oc

WORKDIR /data

COPY fake_build/ /data/

RUN --mount=type=secret,id=pull_secret,mode=0644,target=/home/builder/.docker/config.json sed "s/XXX/'\`cat /home/builder/.docker/config.json | python -m json.tool | tr -d '\n'\`'/g" -i /data/install-config.yaml && \
    OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=$RELEASE_IMAGE openshift-install agent create image --log-level debug 
EOF

podman push ${DEST_REGISTRY}/${AGENT_BUILDER}

rm -rf $TMPMIRRORFILE

  
#####

# extra stuffs

cat << EOF | podman build $(mktemp -d) -t ${DEST_REGISTRY}/extra_tools -f -
FROM fedora:40

dnf install --nodocs -y butane python3-pip \
  	&& dnf clean all \
  	&& rm -rf /var/cache/yum

EOF







#D=$(date +"%d-%m-%Y-%H-%M-%S")
#mkdir -p ./build/${D}
#cp -r ./fake_build/* ./build/${D}/
#podman run --annotation run.oci.keep_original_groups=1 --userns=keep-id --rm -ti -v $PWD/build/${D}/:/data:z -v $HOME/.docker/config.json:/root/.docker/config.json -v $TMPREGCONF:/etc/containers/registries.conf.d/mirror.conf  $AGENT_BUILDER agent create image --dir /data


