# /bin/sh

PRJ_NAME=vpot

# docker build configuration
echo \
'FROM docker.1ms.run/library/debian:12.8
MAINTAINER SHU <free1139@163.com>

COPY ./sources.list /etc/apt/sources.list
RUN apt-get update && apt-get install -y ca-certificates sudo
RUN mkdir /etc/supd/
RUN mkdir /etc/supd/conf.d/

COPY ./supd/bin/supd /usr/local/bin
COPY ./supd/bin/supc /usr/local/bin
COPY ./supd/etc/supd/supd.ini /etc/supd/

COPY ./picoclaw /usr/local/picoclaw
COPY ./picoclaw-launcher.ini /etc/supd/conf.d/
COPY ./picoclaw-upgrade.ini /etc/supd/conf.d/

ENV PATH="/usr/local/picoclaw::$PATH"
RUN echo "export PATH=/usr/local/picoclaw:$PATH" >> ~/.bashrc

CMD ["/usr/local/bin/supd", "-c","/etc/supd/supd.ini"]
'>Dockerfile

# build bin data
if [ ! -f "supd.tar.gz" ]; then 
    wget https://lib10.cn/download/supd.tar.gz
    tar -xzf supd.tar.gz
fi
if [ ! -f "picoclaw.tar.gz" ]; then
    wget https://lib10.cn/download/picoclaw.tar.gz
    tar -xzf picoclaw.tar.gz
fi

echo "# Building Dockerfile"
# remove old images
sudo docker rmi -f $PRJ_NAME||exit 1
# build images
sudo docker build -t $PRJ_NAME .||exit 1
# rm tmp data
# rm app

# show images build result
sudo docker images $PRJ_NAME||exit 1

# remove dockerfile
rm Dockerfile||exit 1
