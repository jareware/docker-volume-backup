FROM ubuntu:18.04

# Install required base packages
RUN \
  apt-get update && \
  apt-get install -y --no-install-recommends curl cron ca-certificates unzip apt-transport-https gnupg2 software-properties-common && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

# Install awscliv2 https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html
RUN \
  curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
  unzip -q awscliv2.zip && \
  ./aws/install -i /usr/bin -b /usr/bin && \
  rm -rf ./aws awscliv2.zip && \
  aws --version

# Install docker CLI
RUN \
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
  apt-get update && \
  apt-get install -y --no-install-recommends docker-ce-cli && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy scripts and allow execution
COPY ./src/entrypoint.sh ./src/backup.sh /root/
RUN \
  chmod a+x /root/entrypoint.sh && \
  chmod a+x /root/backup.sh

WORKDIR /root
CMD [ "/root/entrypoint.sh" ]