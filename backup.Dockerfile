FROM ubuntu:16.04

RUN apt-get update && apt-get install -y curl awscli

# https://docs.docker.com/engine/installation/linux/docker-ce/ubuntu/#install-using-the-convenience-script
RUN curl -fsSL get.docker.com -o get-docker.sh
RUN sh get-docker.sh

COPY ./backup.sh /root/
RUN chmod a+x /root/backup.sh

CMD [ "/root/backup.sh" ]
