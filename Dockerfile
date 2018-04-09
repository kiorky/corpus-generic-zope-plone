FROM corpusops/ubuntu:16.04
# Rewarm apt cache
RUN bash -c '\
  if egrep -qi "ubuntu|mint|debian" /etc/*-release 2>/dev/null;then\
      apt-get update -y -qq;\
      if [ "x${PKGS_REMOVES-}" != "x" ];then\
        apt-get install -y $PKGS_REMOVES;\
      fi;\
  fi'
WORKDIR /provision_dir
# Way to override var from upper image (already defined)
ARG APP_ENV_NAME=docker
ARG COPS_PROJECT_TYPE=zope
ARG SKIP_COPS_UPDATE=
ARG COPS_ANCESTOR=setups.${COPS_PROJECT_TYPE}
ARG TMPPLAYBOOK=.ansible/playbooks/bootstrap.yml
ENV A_ENV_NAME=$APP_ENV_NAME
ENV COPS_PROJECT_TYPE=$COPS_PROJECT_TYPE
ENV TMPPLAYBOOK=$TMPPLAYBOOK
ENV NONINTERACTIVE=1
#
ADD .ansible/scripts        /provision_dir/.ansible/scripts
ADD .ansible/vaults         /provision_dir/.ansible/vaults
ADD .ansible/filter_plugins /provision_dir/.ansible/filter_plugins
# ADD enougth of ancestors for bootstraping (if submodules)
ADD local/$COPS_ANCESTOR/.ansible/vaults         local/$COPS_ANCESTOR/.ansible/vaults
ADD local/$COPS_ANCESTOR/.ansible/filter_plugins local/$COPS_ANCESTOR/.ansible/filter_plugins

## Uncomment to load inside the container
## local corpusops.bootstrap modifications
## rm local/corpusops.bootstrap;sudo mount -o bind ~/corpusops/corpusops.bootstrap local/corpusops.bootstrap
## docker build --squash -t m . -f Dockerfile --build-arg=SKIP_COPS_UPDATE=y
# ADD local/corpusops.bootstrap/hacking $COPS_ROOT/hacking/
# ADD local/corpusops.bootstrap/bin     $COPS_ROOT/bin/
# ADD local/corpusops.bootstrap/roles   $COPS_ROOT/roles/

RUN bash -c '\
  rm -rf local/corpusops.bootstrap \
  && ln -sf $COPS_ROOT local/corpusops.bootstrap \
  && .ansible/scripts/download_corpusops.sh \
  && .ansible/scripts/setup_ansible.sh'

# build layout, inject code, install base pkgs
ADD .ansible/playbooks/roles/ /provision_dir/.ansible/playbooks/roles/
ADD local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_fixperms \
    /provision_dir/local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_fixperms
ADD local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_steps \
    /provision_dir/local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_steps
ADD local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_app_vars \
    /provision_dir/local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_app_vars
ADD local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_vars \
    /provision_dir/local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_vars
ADD local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_users \
    /provision_dir/local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_users
ADD local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_layout \
    /provision_dir/local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_layout
ADD local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_push_code \
    /provision_dir/local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_push_code
ADD local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_prerequisites \
    /provision_dir/local/$COPS_ANCESTOR/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_prerequisites
#
ADD etc/ /provision_dir/etc/
RUN bash -c '\
  ROLES="\
      corpusops.roles/vars \
      ${COPS_PROJECT_TYPE}_steps \
      ${COPS_PROJECT_TYPE}_app_vars \
      ${COPS_PROJECT_TYPE}_vars \
      ${COPS_PROJECT_TYPE}_push_code \
      ${COPS_PROJECT_TYPE}_users \
      ${COPS_PROJECT_TYPE}_layout \
      ${COPS_PROJECT_TYPE}_fixperms \
      ${COPS_PROJECT_TYPE}_prerequisites" $_call_roles'

# Add here any role to pre build to speed up rebuilds
ADD .ansible/playbooks/roles/${COPS_PROJECT_TYPE}_setup_venv \
     /provision_dir/.ansible/playbooks/roles/${COPS_PROJECT_TYPE}_setup_venv/
RUN bash -c '\
  ROLES="corpusops.roles/vars ${COPS_PROJECT_TYPE}_steps ${COPS_PROJECT_TYPE}_vars \
      ${COPS_PROJECT_TYPE}_setup_venv" $_call_roles'

# setup app (without services and content managment)
ADD . /provision_dir
RUN bash -c '\
  rm -rf local/corpusops.bootstrap \
  && ln -sf $COPS_ROOT local/corpusops.bootstrap \
  && .ansible/scripts/download_corpusops.sh \
  && .ansible/scripts/setup_ansible.sh \
  && $_call_ansible .ansible/playbooks/site.yml \
  -e "{cops_${COPS_PROJECT_TYPE}_s_healthchecks: false, \
       cops_${COPS_PROJECT_TYPE}_s_manage_content: false}"'

# Default to launch systemd, and you ll have have to mount:
#  -v /sys/fs/cgroup:/sys/fs/cgroup:ro
STOPSIGNAL SIGRTMIN+3
CMD ["/app_entry_point"]
# pack, cleanup, snapshot any found git repo
RUN bash -c 'step_rev=3;set -e;cd $COPS_ROOT;\
    GIT_SHALLOW_DEPTH=1 \
    GIT_SHALLOW=y \
    NO_IMAGE_STRIP= /sbin/cops_container_strip.sh;'
