FROM ubuntu:18.04

<<<<<<< HEAD
RUN apt-get update && apt-get install -y --no-install-recommends curl cron ca-certificates unzip iputils-ping
=======
RUN apt-get update && apt-get install -y --no-install-recommends curl cron ca-certificates openssh-client unzip
>>>>>>> c3c0d4f4dcd0f9db37bdd9f36bf5f83861a7dec5
RUN rm -rf /var/lib/apt/lists/*

# Install awscliv2 https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html
# ...but only for architectures that support it (see https://github.com/futurice/docker-volume-backup/issues/29)
RUN if [ $(uname -m) = "aarch64" ] || [ $(uname -m) = "x86_64" ] ; then curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip" && unzip -q awscliv2.zip && ./aws/install -i /usr/bin -b /usr/bin && rm -rf ./aws awscliv2.zip && aws --version ; fi

# https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-using-the-convenience-script
RUN curl -fsSL get.docker.com -o get-docker.sh
RUN sh get-docker.sh

COPY ./src/entrypoint.sh /root/
COPY ./src/backup.sh /root/
RUN chmod a+x /root/entrypoint.sh
RUN chmod a+x /root/backup.sh

WORKDIR /root
CMD [ "/root/entrypoint.sh" ]
