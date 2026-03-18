FROM docker.io/codercom/code-server:latest
USER 0:0
ENV HOME=/root \
CODER_LIB=/env/lib
WORKDIR /root

RUN mkdir -p $CODER_LIB
RUN sed -i -e 's|^# en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|' /etc/locale.gen \
&& sed -i -e 's|^# zh_TW.UTF-8 UTF-8|zh_TW.UTF-8 UTF-8|' /etc/locale.gen \
&& sed -i -e 's|^# zh_CN.UTF-8 UTF-8|zh_CN.UTF-8 UTF-8|' /etc/locale.gen \
&& sed -i -e 's|^# zh_HK.UTF-8 UTF-8|zh_HK.UTF-8 UTF-8|' /etc/locale.gen
RUN locale-gen
RUN apt update \
&& apt remove vim-* -y \
&& apt install -y bash-completion python3-full python3-pip wget jq curl vim zip git openjdk-17-jdk-headless unzip xz-utils libglu1-mesa pkg-config libssl-dev \
&& apt clean && rm -rf /var/lib/apt/lists/* \
&& ln -s /usr/bin/python3 /usr/bin/python

RUN cat >> /etc/bash.bashrc << 'EOF'
# ========== Basic Shell Configuration ==========
shopt -s checkwinsize
export TERM=xterm-256color
export LS_OPTIONS='--color=auto'
eval "`dircolors`"
alias ls="ls $LS_OPTIONS"
alias ll='ls $LS_OPTIONS -lhA --time-style "+%Y/%m/%d %H:%M:%S"'
. /etc/bash_completion
. /usr/share/bash-completion/completions/git

git_prompt_info() {
  local branch=$(git branch --show-current 2>/dev/null)
  [[ -n $branch ]] || return

  local dirty=$(git status --porcelain 2>/dev/null)

  local yellow=$'\001\e[0;33m\002'
  local green=$'\001\e[0;32m\002'
  local reset=$'\001\e[0m\002'

  if [[ -n $dirty ]]; then
    echo "${yellow}(${branch} ✗)${reset}"
  else
    echo "${green}(${branch} ✓)${reset}"
  fi
}

PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\] $(git_prompt_info)\n\$ '

function cd() {
    builtin cd "$@" || return $?
    if [[ -n "$VIRTUAL_ENV" ]]; then
        local venv_root_dir
        venv_root_dir=$(dirname "$VIRTUAL_ENV")
        if [[ "$PWD" != "$venv_root_dir" && "$PWD" != "$venv_root_dir"/* ]]; then
            deactivate
        fi
    fi
    if [[ -z "$VIRTUAL_ENV" ]]; then
        if [[ -f "./.venv/bin/activate" ]]; then
            source "./.venv/bin/activate"
        fi
    fi
}
EOF

######################################################### Go #########################################################
ENV GOROOT=$CODER_LIB/go \
GOPATH=$HOME/.gopath \
GOPROXY=https://goproxy.cn,https://goproxy.io,https://proxy.golang.org,direct
ENV PATH=$GOROOT/bin:$GOPATH/bin:$PATH

RUN mkdir -p $GOPATH \
&& wget -qO- https://go.dev/dl/$(curl -s https://go.dev/dl/?mode=json | jq -r .[0].version).linux-amd64.tar.gz | tar -xz -C $CODER_LIB \
&& go install golang.org/x/tools/gopls@latest

RUN cat >> /etc/bash.bashrc << 'EOF'
# ========== Go Configuration ==========
export GOROOT=$CODER_LIB/go
export GOPATH=$HOME/.gopath
export GOPROXY=https://goproxy.cn,https://goproxy.io,https://proxy.golang.org,direct
alias golinux='CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o app .'
alias gowin='CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o app.exe .'
EOF

######################################################### Android #########################################################
ENV ANDROID_HOME=$CODER_LIB/android
ENV ANDROID_SDK_ROOT=$ANDROID_HOME/cmdline-tools/latest
ENV PATH=$ANDROID_HOME/platform-tools:$ANDROID_SDK_ROOT/bin:$PATH

RUN mkdir -p $CODER_LIB/android \
&& curl -sL $(curl -sL https://developer.android.com/studio | grep -oP 'https://dl.google.com/android/repository/commandlinetools-linux-[0-9]+_latest\.zip' | head -1) | python3 -c "import sys,zipfile,io,shutil,os;z=zipfile.ZipFile(io.BytesIO(sys.stdin.buffer.read()));z.extractall('/tmp');dest=os.path.join(os.environ['CODER_LIB'],'android/cmdline-tools/latest');os.makedirs(os.path.dirname(dest),exist_ok=True);shutil.move('/tmp/cmdline-tools',dest)" \
&& chmod +x $CODER_LIB/android/cmdline-tools/latest/bin/* \
&& yes | sdkmanager --sdk_root=$CODER_LIB/android "platform-tools" "$(sdkmanager --sdk_root=$CODER_LIB/android --list | grep 'build-tools;' | awk '{print $1}' | sort -V | tail -n1)" "$(sdkmanager --sdk_root=$CODER_LIB/android --list | grep 'platforms;android-' | awk '{print $1}' | sort -V | tail -n1)" \
&& yes | sdkmanager --licenses

RUN cat >> /etc/bash.bashrc << 'EOF'
# ========== Android Configuration ==========
export ANDROID_HOME=$CODER_LIB/android
export ANDROID_SDK_ROOT=$ANDROID_HOME/cmdline-tools/latest
EOF

######################################################### Flutter #########################################################
ENV FLUTTER_ROOT=$CODER_LIB/flutter \
FLUTTER_ROOT_USAGE_WARNING=false \
PUB_HOSTED_URL=https://pub.flutter-io.cn \
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
ENV PATH=$FLUTTER_ROOT/bin:$PATH

RUN touch /.dockerenv \
&& curl -sL https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json | python3 -c "import sys,json; d=json.load(sys.stdin); h=d['current_release']['stable']; r=next(x for x in d['releases'] if x['hash']==h); print(d['base_url']+'/'+r['archive'])" | xargs curl -L | tar xJ -C $CODER_LIB/ \
&& git config --global --add safe.directory  $CODER_LIB/flutter \
&& flutter config --android-sdk $CODER_LIB/android

RUN cat >> /etc/bash.bashrc << 'EOF'
# ========== Flutter Configuration ==========
export FLUTTER_ROOT=$CODER_LIB/flutter
export FLUTTER_ROOT_USAGE_WARNING=false
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
EOF

######################################################### Rust #########################################################
ENV RUSTUP_HOME=$CODER_LIB/rust/rustup \
CARGO_HOME=$CODER_LIB/rust/cargo
ENV PATH="$CARGO_HOME/bin:${PATH}"

RUN mkdir -p $RUSTUP_HOME \
&& mkdir -p $CARGO_HOME \
&& curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -q -y --no-modify-path --default-toolchain stable \
&& rustup component add rust-src --toolchain stable \
&& rustup component add rust-analyzer --toolchain stable

RUN cat >> /etc/bash.bashrc << 'EOF'
# ========== Rust Configuration ==========
export RUSTUP_HOME=$CODER_LIB/rust/rustup
export CARGO_HOME=$CODER_LIB/rust/cargo
. "$CARGO_HOME/env"
EOF

######################################################### Node js #########################################################
ENV NVM_DIR=$CODER_LIB/nvm

RUN mkdir -p $NVM_DIR \
&& curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash \
&& [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" \
&& nvm install 25 \
&& npm install -g pnpm \
&& npm config set registry https://registry.npmmirror.com/

RUN cat >> /etc/bash.bashrc << 'EOF'
# ========== Node.js / NVM Configuration ==========
export NVM_DIR=$CODER_LIB/nvm
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF

RUN cat >> /etc/bash.bashrc << 'EOF'
# ========== PATH Configuration (Composite) ==========
# Rebuild PATH with all tool directories
export PATH=$GOROOT/bin:$GOPATH/bin:$ANDROID_HOME/platform-tools:$ANDROID_SDK_ROOT/bin:$FLUTTER_ROOT/bin:$CARGO_HOME/bin:$PATH
EOF
