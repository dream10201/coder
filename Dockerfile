FROM docker.io/codercom/code-server:latest
USER 0:0
ENV HOME=/root
WORKDIR /root

# Go
ENV GOROOT=$HOME/.env/lib/golang/go \
GOPATH=$HOME/.env/lib/golang/gopath \
GOPROXY=https://goproxy.cn,https://goproxy.io,https://proxy.golang.org,direct
ENV PATH=$GOROOT/bin:$GOPATH/bin:$PATH

# Flutter
ENV FLUTTER_ROOT_USAGE_WARNING=false \
PUB_HOSTED_URL=https://pub.flutter-io.cn \
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
PATH=$HOME/.env/lib/flutter/bin:$PATH

# Android
ENV ANDROID_HOME=$HOME/.env/lib/android \
ANDROID_SDK_ROOT=$ANDROID_HOME/cmdline-tools/latest
ENV PATH=$PATH:$ANDROID_SDK_ROOT/bin \
PATH=$PATH:$ANDROID_HOME/platform-tools

RUN mkdir -p $HOME/.env/lib \
&& apt update && apt upgrade -y \
&& apt remove vim-* -y \
&& apt install -y bash-completion python3-full python3-pip wget jq curl vim zip git \
&& sed -i -e 's|^# en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|' /etc/locale.gen \
&& sed -i -e 's|^# zh_TW.UTF-8 UTF-8|zh_TW.UTF-8 UTF-8|' /etc/locale.gen \
&& sed -i -e 's|^# zh_CN.UTF-8 UTF-8|zh_CN.UTF-8 UTF-8|' /etc/locale.gen \
&& sed -i -e 's|^# zh_HK.UTF-8 UTF-8|zh_HK.UTF-8 UTF-8|' /etc/locale.gen \
&& locale-gen \
# Go
&& mkdir -p $HOME/.env/lib/golang/go \
&& mkdir -p $HOME/.env/lib/golang/gopath \
&& wget -qO- https://go.dev/dl/$(curl -s https://go.dev/dl/?mode=json | jq -r .[0].version).linux-amd64.tar.gz | tar -xz -C $HOME/.env/lib/golang \
&& go install golang.org/x/tools/gopls@latest \
# flutter
&& apt-get install -y curl git unzip xz-utils zip libglu1-mesa openjdk-17-jdk-headless \
&& touch /.dockerenv \
&& mkdir -p $HOME/.env/lib/flutter \
&& curl -sL https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json | python3 -c "import sys,json; d=json.load(sys.stdin); h=d['current_release']['stable']; r=next(x for x in d['releases'] if x['hash']==h); print(d['base_url']+'/'+r['archive'])" | xargs curl -L | tar xJ -C $HOME/.env/lib/ \
# Android
&& mkdir -p $HOME/.env/lib/android \
# Rust
&& apt install -y pkg-config libssl-dev \
&& curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -q -y --default-toolchain stable \
&& \. "$HOME/.cargo/env" \
&& rustup component add rust-src --toolchain stable \
&& rustup component add rust-analyzer --toolchain stable \
# Node js
&& curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash \
&& \. "$HOME/.nvm/nvm.sh" \
&& nvm install 25 \
&& npm install -g pnpm \
&& npm config set registry https://registry.npmmirror.com/
