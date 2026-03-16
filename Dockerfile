FROM docker.io/codercom/code-server:latest
USER 0:0
ENV HOME=/root \
CODEER_LIB=/env/lib
WORKDIR /root

# Go
ENV GOROOT=$CODEER_LIB/golang/go \
GOPATH=$CODEER_LIB/golang/gopath \
GOPROXY=https://goproxy.cn,https://goproxy.io,https://proxy.golang.org,direct
ENV PATH=$GOROOT/bin:$GOPATH/bin:$PATH
RUN echo 'export PATH=$GOROOT/bin:$GOPATH/bin:$PATH' >> /etc/bash.bashrc

# Flutter
ENV FLUTTER_ROOT_USAGE_WARNING=false \
PUB_HOSTED_URL=https://pub.flutter-io.cn \
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
ENV PATH=$CODEER_LIB/flutter/bin:$PATH
RUN echo 'export PATH=$CODEER_LIB/flutter/bin:$PATH' >> /etc/bash.bashrc

# Android
ENV ANDROID_HOME=$CODEER_LIB/android \
ANDROID_SDK_ROOT=$ANDROID_HOME/cmdline-tools/latest
ENV PATH=$ANDROID_HOME/platform-tools:$ANDROID_SDK_ROOT/bin:$PATH
RUN echo 'export PATH=$ANDROID_HOME/platform-tools:$ANDROID_SDK_ROOT/bin:$PATH' >> /etc/bash.bashrc

# Rust
ENV RUSTUP_HOME=$CODEER_LIB/rust/rustup \
CARGO_HOME=$CODEER_LIB/rust/cargo
ENV PATH="$CARGO_HOME/bin:${PATH}"
RUN echo 'export PATH=$CARGO_HOME/bin:$PATH' >> /etc/bash.bashrc

# Nodejs
ENV NVM_DIR=$CODEER_LIB/lib/nvm
RUN echo 'export NVM_DIR=$CODEER_LIB/lib/nvm' >> /etc/bash.bashrc

RUN mkdir -p $CODEER_LIB
RUN apt update
RUN apt remove vim-* -y \
&& apt install -y bash-completion python3-full python3-pip wget jq curl vim zip git
RUN sed -i -e 's|^# en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|' /etc/locale.gen \
&& sed -i -e 's|^# zh_TW.UTF-8 UTF-8|zh_TW.UTF-8 UTF-8|' /etc/locale.gen \
&& sed -i -e 's|^# zh_CN.UTF-8 UTF-8|zh_CN.UTF-8 UTF-8|' /etc/locale.gen \
&& sed -i -e 's|^# zh_HK.UTF-8 UTF-8|zh_HK.UTF-8 UTF-8|' /etc/locale.gen
RUN locale-gen

# Go
RUN mkdir -p $CODEER_LIB/golang/go \
&& mkdir -p $CODEER_LIB/golang/gopath \
&& wget -qO- https://go.dev/dl/$(curl -s https://go.dev/dl/?mode=json | jq -r .[0].version).linux-amd64.tar.gz | tar -xz -C $CODEER_LIB/golang \
&& go install golang.org/x/tools/gopls@latest

# Android
RUN mkdir -p $CODEER_LIB/android \
&& curl -sL $(curl -sL https://developer.android.com/studio | grep -oP 'https://dl.google.com/android/repository/commandlinetools-linux-[0-9]+_latest\.zip' | head -1) | python3 -c "
import sys,zipfile,io,shutil,os
z=zipfile.ZipFile(io.BytesIO(sys.stdin.buffer.read()))
z.extractall('/tmp')
dest=os.path.join(os.environ['CODER_LIB'],'android/cmdline-tools/latest')
os.makedirs(os.path.dirname(dest),exist_ok=True)
shutil.move('/tmp/cmdline-tools',dest)
" \
&& yes | sdkmanager --sdk_root=$CODEER_LIB/android "platform-tools" "$(sdkmanager --sdk_root=$CODEER_LIB/android --list | grep 'build-tools;' | awk '{print $1}' | sort -V | tail -n1)" "$(sdkmanager --sdk_root=$CODEER_LIB/android --list | grep 'platforms;android-' | awk '{print $1}' | sort -V | tail -n1)" \
&& yes | sdkmanager --licenses

# flutter
RUN apt-get install -y curl git unzip xz-utils zip libglu1-mesa openjdk-17-jdk-headless \
&& touch /.dockerenv \
&& mkdir -p $CODEER_LIB/flutter \
&& curl -sL https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json | python3 -c "import sys,json; d=json.load(sys.stdin); h=d['current_release']['stable']; r=next(x for x in d['releases'] if x['hash']==h); print(d['base_url']+'/'+r['archive'])" | xargs curl -L | tar xJ -C $CODEER_LIB/ \
&& flutter config --android-sdk /env/lib/android

# Rust
RUN mkdir -p $RUSTUP_HOME \
&& mkdir -p $CARGO_HOME
&& apt install -y pkg-config libssl-dev \
&& curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -q -y --no-modify-path --default-toolchain stable \
&& rustup component add rust-src --toolchain stable \
&& rustup component add rust-analyzer --toolchain stable

# Node js
RUN mkdir -p $NVM_DIR \
&& curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash \
&& nvm install 25 \
&& npm install -g pnpm \
&& npm config set registry https://registry.npmmirror.com/
