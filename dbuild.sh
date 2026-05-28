# /bin/sh

# docker build configuration
echo \
'FROM docker.1ms.run/library/debian:12.8
MAINTAINER SHU <free1139@163.com>

RUN apt-get update && apt-get install -y ca-certificates

COPY ./supd/bin/supd /usr/local/bin
COPY ./supd/bin/supc /usr/local/bin
COPY ./supd/etc/supd /etc

COPY ./picoclaw-launcher /usr/local/bin
COPY ./etc/supd/picoclaw-launcher.ini /etc/supd/supd.conf

CMD ["/usr/local/bin/supd", "-c","etc/supd.conf"]
'>Dockerfile

# build bin data
if [ ! -f "supd.tar.gz" ]; then 
    wget https://lib10.cn/download/supd.tar.gz
    tar -xzf supd.tar.gz
fi
if [ ! -f "picoclaw-launcher.tar.gz" ]; then
    wget https://lib10.cn/download/picoclaw-launcher.tar.gz
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
