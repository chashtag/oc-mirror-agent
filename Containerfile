FROM quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:52b69276b26b735736057dc000fcd0c38adc4ed7f11b2153030c8d240eba1686 as AGENT

RUN tar -cvf /agent-files.tar /usr/lib64/libnmstate.so.* /usr/bin/agent-tui

FROM quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:526fac9064ded421280854a12b90a9d57e8752b3480bc575ffc5adcbded7a346

USER root

COPY --from=AGENT /agent-files.tar /
COPY --chmod=0755 --from=quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:ca70b5e3d7021ef0dfa386a3603761bf7d367c4c306d93e94c0fe2f0623fa613 /usr/bin/nmstatectl /usr/bin/nmstatectl
COPY --from=quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:0c8cdf735bbd3f044fc12de53a22e78274b7e7cc9f88397381d966b0cb96856b /coreos/coreos-x86_64.iso /coreos/coreos-stream.json /coreos/
COPY --chmod=0755 --from=quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:f1faa15f614190d05cb546516db231fd0139f548969deb8cf754709902009d03 /usr/bin/oc /usr/bin/oc

WORKDIR /data

COPY fake_build/ /data/

RUN tar -xf /agent-files.tar -C /

RUN   --mount=type=secret,id=pull_secret,mode=0644,target=/home/builder/.docker/config.json sed "s/XXX/'`cat /home/builder/.docker/config.json | python -m json.tool | tr -d '\n'`'/g" -i /data/install-config.yaml && \
    mkdir -p /output/.cache/agent/{files,image}_cache/ && \
    ln -s /usr/bin/agent-tui /output/.cache/agent/files_cache/ && \
    ln -s /usr/lib64/libnmstate.so.* /output/.cache/agent/files_cache/ && \
    cp /coreos/coreos-stream.json /output/.cache/agent/files_cache/ && \
    ln -s /coreos/coreos-x86_64.iso /output/.cache/agent/image_cache/ && \
    ln -s /coreos/coreos-x86_64.iso /output/.cache/agent/image_cache/`cat /coreos/coreos-stream.json |grep -Po ':\s\".+/(\K.+?live.x86_64.iso)'`  && \
    OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=quay.io/openshift-release-dev/ocp-release@sha256:7111fb4cec202cb758f58d9bed95a67e7fdc417353ef15be56d7bf96356909d4 openshift-install agent create image --log-level debug  && \
    rm -rf /data/.* /data/* || true
