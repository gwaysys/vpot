# 在 Linux/macOS 上交叉编译 vpot-bootstrap.exe 并准备 MSI 打包文件。
# 生成 .msi 仍需在 Windows 上执行 build.ps1(go-msi 依赖 cmd.exe + WiX)。
VERSION ?= 1.1.5
GOOS ?= windows
GOARCH ?= amd64

.PHONY: all bootstrap clean

all: bootstrap

bootstrap:
	cd bootstrap && GOOS=$(GOOS) GOARCH=$(GOARCH) CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o ../vpot-bootstrap.exe .
	cp ../docker-compose.yaml ./docker-compose.yaml
	cp ../readme.txt ./readme.txt

clean:
	rm -f vpot-bootstrap.exe docker-compose.yaml readme.txt *.msi
