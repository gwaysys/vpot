
# Build picoclaw binnary
```
cd ..
git clone https://github.comg/free1139/picoclaw.git
cd picoclaw
make build-launcher
cp -rf build ../vpot/picoclaw
cd -
```

# Build docker image
```
./dbuild.sh
```

# Run docker image
```
sudo docker-compose -f docker-compose.yaml up -d # open browser visit: http://127.0.0.1:18800
```

# Backup container
```
see backup.sh
```

# For Windows
```
# set up wsl or do `wsl --update`
https://github.com/microsoft/WSL/releases/download/2.1.5/wsl.2.1.5.0.x64.msi

# install docker
https://docs.docker.com/desktop/setup/install/windows-install/

# open powershell and run
docker login docker.lib10.cn
docker-compose -f docker-compose.yaml up -d # open browser visit: http://127.0.0.1:18800
```
