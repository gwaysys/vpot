#!/bin/sh

PRJ_NAME=vpot

image_name="docker.lib10.cn/lib10/vpot"

echo "Docker images:"
sudo docker images|grep -E "$PRJ_NAME|$image_name"

tag=$1
if [ -z "$tag" ]; then
    echo -n "Input new tag:"
    read tag
fi

docker_tag="$image_name:$tag"

echo -n "New tag: $PRJ_NAME:latest $docker_tag? Y/N: "
read do_tag
if [ "$do_tag" = "Y" ]; then
    sudo docker image rm $docker_tag
    sudo docker tag $PRJ_NAME:latest $docker_tag # 注意变更tag, 查阅命令：docker images
else
    echo "Abort"
    return 1
fi

echo "Docker images:"
sudo docker images|grep -E "$PRJ_NAME|$image_name"

echo -n "Push: $docker_tag? Y/N: "
read push
if [ "$push" = "Y" ]; then
    sudo docker push $docker_tag
fi
echo "Done"

