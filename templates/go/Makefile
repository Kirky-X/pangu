# pangu: Go 构建/测试入口（含 release 优化标志）。
# 由 init-go.sh 通过 copy_lang go 自动拷贝到项目根。
#
# release 优化说明：
#   -ldflags "-s -w"  去符号表 + 调试信息，二进制体积 -25%
#   -trimpath         去绝对路径，可复现构建（CI/Release 标配）
#
# 用法:
#   make               # = make build（debug，含符号，便于 delve 调试）
#   make release       # release 构建（优化 + 去符号，用于发布）
#   make test          # go test ./... -race -cover
#   make clean

APP_NAME ?= app
BIN_DIR  ?= bin

.PHONY: build release test fmt vet clean default

default: build

build:
	go build -o $(BIN_DIR)/$(APP_NAME) .

release:
	go build -ldflags="-s -w" -trimpath -o $(BIN_DIR)/$(APP_NAME) .

test:
	go test ./... -race -cover

fmt:
	go fmt ./...

vet:
	go vet ./...

clean:
	rm -rf $(BIN_DIR)
