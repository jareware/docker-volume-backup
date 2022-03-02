FROM ubuntu:18.04

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl cron ca-certificates openssh-client iputils-ping unzip \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install awscliv2 https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html
# ...but only for architectures that support it (see https://github.com/futurice/docker-volume-backup/issues/29)
RUN if [ $(uname -m) = "aarch64" ] || [ $(uname -m) = "x86_64" ] ; then curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip" && unzip -q awscliv2.zip && ./aws/install -i /usr/bin -b /usr/bin && rm -rf ./aws awscliv2.zip && aws --version ; fi

# Install Docker binary
# a) get.docker.com
# https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-using-the-convenience-script
# RUN curl -fsSL get.docker.com | sh
# b) Borrow it from Official Docker container
COPY --from=docker:latest /usr/local/bin/docker /usr/local/bin/

COPY ./src/entrypoint.sh ./src/backup.sh /root/
RUN chmod a+x /root/entrypoint.sh /root/backup.sh

WORKDIR /root
CMD [ "/root/entrypoint.sh" ]
