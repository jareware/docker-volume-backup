FROM ubuntu:18.04

RUN apt-get update && apt-get install -y curl cron awscli

# https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-using-the-convenience-script
RUN curl -fsSL get.docker.com -o get-docker.sh
RUN sh get-docker.sh

COPY ./entrypoint.sh /root/
COPY ./backup.sh /root/
RUN chmod a+x /root/entrypoint.sh
RUN chmod a+x /root/backup.sh

WORKDIR /root
CMD [ "/root/entrypoint.sh" ]
