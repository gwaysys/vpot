
# Build picoclaw binnary
```
cd ..
git clone https://github.comg/free1139/picoclaw.git
cd picoclaw
make build-launcher
cp -rf build ../vpot/picoclaw
```

# Build docker image
```
./dbuild.sh
```

# Run docker image
```
sudo docker-compose -f docker-compose.yaml up -d
```

# Backup container
```
see backup.sh
```
