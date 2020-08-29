FROM ubuntu:18.04

RUN apt-get update && apt-get install -y --no-install-recommends curl cron ca-certificates unzip
RUN rm -rf /var/lib/apt/lists/*

# Install awscliv2 https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html
RUN curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
RUN unzip -q awscliv2.zip
RUN ./aws/install -i /usr/bin -b /usr/bin
RUN rm -rf ./aws awscliv2.zip
RUN aws --version

# https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-using-the-convenience-script
RUN curl -fsSL get.docker.com -o get-docker.sh
RUN sh get-docker.sh

COPY ./src/entrypoint.sh /root/
COPY ./src/backup.sh /root/
RUN chmod a+x /root/entrypoint.sh
RUN chmod a+x /root/backup.sh

WORKDIR /root
CMD [ "/root/entrypoint.sh" ]
