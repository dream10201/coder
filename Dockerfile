FROM docker.io/codercom/code-server:latest
USER 0:0

ENV HOME=/root \
    CODER_LIB=/env/lib \
    JAVA_HOME=/env/lib/java \
    GOROOT=/env/lib/go \
    GOPATH=/root/.gopath \
    GOPROXY=https://goproxy.cn,https://goproxy.io,https://proxy.golang.org,direct \
    ANDROID_HOME=/env/lib/android \
    ANDROID_SDK_ROOT=/env/lib/android/cmdline-tools/latest \
    FLUTTER_ROOT=/env/lib/flutter \
    FLUTTER_ROOT_USAGE_WARNING=false \
    PUB_HOSTED_URL=https://pub.flutter-io.cn \
    FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
    RUSTUP_HOME=/env/lib/rust/rustup \
    CARGO_HOME=/env/lib/rust/cargo \
    NVM_DIR=/env/lib/nvm \
    NODE_HOME=/usr/local/lib/node/current \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8
ENV PATH="$JAVA_HOME/bin:$NODE_HOME/bin:$GOROOT/bin:$GOPATH/bin:$ANDROID_HOME/platform-tools:$ANDROID_SDK_ROOT/bin:$FLUTTER_ROOT/bin:$CARGO_HOME/bin:$PATH"

WORKDIR /root
SHELL ["/bin/bash","-o","pipefail","-c"]

RUN mkdir -p "$CODER_LIB"

RUN sed -i -e 's|^# en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|' /etc/locale.gen \
    && sed -i -e 's|^# zh_TW.UTF-8 UTF-8|zh_TW.UTF-8 UTF-8|' /etc/locale.gen \
    && sed -i -e 's|^# zh_CN.UTF-8 UTF-8|zh_CN.UTF-8 UTF-8|' /etc/locale.gen \
    && sed -i -e 's|^# zh_HK.UTF-8 UTF-8|zh_HK.UTF-8 UTF-8|' /etc/locale.gen

RUN locale-gen

RUN apt update \
    && apt remove vim-* -y \
    && apt install -y --no-install-recommends bash-completion python3 python3-pip wget jq curl vim zip git unzip xz-utils pkg-config libssl-dev ca-certificates libatomic1 ripgrep build-essential \
    && apt clean && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/python3 /usr/bin/python

# Install GitHub CLI
RUN (type -p wget >/dev/null || (apt update && apt install wget -y)) \
	&& mkdir -p -m 755 /etc/apt/keyrings \
	&& out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
	&& cat $out | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& mkdir -p -m 755 /etc/apt/sources.list.d \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	&& apt update \
	&& apt install gh -y \
  && apt update \
  && apt install -y gh

######################################################### Java #########################################################
RUN mkdir -p "$JAVA_HOME" \
    && curl -fsSL https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse \
      | tar -xz -C "$JAVA_HOME" --strip-components=1

######################################################### Go #########################################################
RUN mkdir -p "$GOPATH" \
    && wget -qO- "https://go.dev/dl/$(curl -s https://go.dev/dl/?mode=json | jq -r '.[0].version').linux-amd64.tar.gz" | tar -xz -C "$CODER_LIB" \
    && go install golang.org/x/tools/gopls@latest

######################################################### Android #########################################################
RUN mkdir -p "$CODER_LIB/android" \
    && rm -rf /tmp/cmdline-tools /tmp/cmdline-tools.zip \
    && curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp \
    && rm -f /tmp/cmdline-tools.zip \
    && rm -rf "$CODER_LIB/android/cmdline-tools" \
    && mkdir -p "$CODER_LIB/android/cmdline-tools" \
    && mv /tmp/cmdline-tools "$CODER_LIB/android/cmdline-tools/latest" \
    && chmod +x "$ANDROID_SDK_ROOT/bin/"* \
    && SDKMANAGER="$ANDROID_SDK_ROOT/bin/sdkmanager" \
    && set +o pipefail \
    && yes | "$SDKMANAGER" --sdk_root="$CODER_LIB/android" --licenses >/dev/null \
    && set -o pipefail \
    && BUILD_TOOLS_VERSION=$("$SDKMANAGER" --sdk_root="$CODER_LIB/android" --list | awk '/^ +build-tools;[0-9.]+/ {print $1}' | sort -V | tail -n1) \
    && PLATFORM_VERSION=$("$SDKMANAGER" --sdk_root="$CODER_LIB/android" --list | awk '/^ +platforms;android-[0-9]+/ {print $1}' | sort -V | tail -n1) \
    && BUILD_TOOLS_VERSION=${BUILD_TOOLS_VERSION:-build-tools;34.0.0} \
    && PLATFORM_VERSION=${PLATFORM_VERSION:-platforms;android-34} \
    && set +o pipefail \
    && yes | "$SDKMANAGER" --sdk_root="$CODER_LIB/android" "platform-tools" "$BUILD_TOOLS_VERSION" "$PLATFORM_VERSION" \
    && yes | "$SDKMANAGER" --sdk_root="$CODER_LIB/android" --licenses \
    && set -o pipefail

######################################################### Flutter #########################################################
RUN touch /.dockerenv \
    && curl -sL https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json \
      | python3 -c "import sys,json; data=json.load(sys.stdin); stable=data['current_release']['stable']; release=next(item for item in data['releases'] if item['hash']==stable); print(data['base_url']+'/'+release['archive'])" \
      | xargs curl -L \
      | tar xJ -C "$CODER_LIB/" \
    && git config --global --add safe.directory "$CODER_LIB/flutter" \
    && flutter config --android-sdk "$CODER_LIB/android" \
    && flutter precache --android \
    && rm -rf "$FLUTTER_ROOT/bin/cache/downloads" \
    && find "$FLUTTER_ROOT/bin/cache/artifacts/engine" -maxdepth 1 -type d \( -name '*darwin*' -o -name '*ios*' -o -name '*windows*' -o -name '*linux*' -o -name '*web*' \) -exec rm -rf {} + \
    && rm -rf /tmp/*

######################################################### Rust #########################################################
RUN mkdir -p "$RUSTUP_HOME" "$CARGO_HOME" \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -q -y --no-modify-path --default-toolchain stable \
    && rustup component add rust-src --toolchain stable \
    && rustup component add rust-analyzer --toolchain stable \
    && rustup component remove rust-docs --toolchain stable || true \
    && rm -rf "$CARGO_HOME/registry" "$CARGO_HOME/git" "$RUSTUP_HOME/tmp" \
    && rm -rf /tmp/*

######################################################### Node js #########################################################
RUN mkdir -p "$NVM_DIR" /usr/local/lib/node \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash \
    && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" \
    && nvm install 25 \
    && nvm alias default 25 \
    && NODE_VERSION=$(nvm version default) \
    && ln -sfn "$NVM_DIR/versions/node/$NODE_VERSION" /usr/local/lib/node/current \
    && nvm use default \
    && npm install -g pnpm \
    && npm config set registry https://registry.npmmirror.com/ \
    && npm cache clean --force \
    && rm -rf "$NVM_DIR/.cache" "$HOME/.npm" /tmp/*

######################################################### Profile scripts #########################################################
RUN cat <<'EOF' >/etc/profile.d/00-coder-env.sh
# Ensure language/tool environment variables exist for login shells
if [ -z "${CODER_LIB:-}" ]; then
  CODER_LIB=/env/lib
fi
export CODER_LIB
if [ -z "${JAVA_HOME:-}" ]; then
  JAVA_HOME=/env/lib/java
fi
export JAVA_HOME
if [ -z "${GOROOT:-}" ]; then
  GOROOT="$CODER_LIB/go"
fi
export GOROOT
if [ -z "${GOPATH:-}" ]; then
  GOPATH=/root/.gopath
fi
export GOPATH
if [ -z "${GOPROXY:-}" ]; then
  GOPROXY=https://goproxy.cn,https://goproxy.io,https://proxy.golang.org,direct
fi
export GOPROXY
if [ -z "${ANDROID_HOME:-}" ]; then
  ANDROID_HOME="$CODER_LIB/android"
fi
export ANDROID_HOME
if [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  ANDROID_SDK_ROOT="$ANDROID_HOME/cmdline-tools/latest"
fi
export ANDROID_SDK_ROOT
if [ -z "${FLUTTER_ROOT:-}" ]; then
  FLUTTER_ROOT="$CODER_LIB/flutter"
fi
export FLUTTER_ROOT
if [ -z "${FLUTTER_ROOT_USAGE_WARNING:-}" ]; then
  FLUTTER_ROOT_USAGE_WARNING=false
fi
export FLUTTER_ROOT_USAGE_WARNING
if [ -z "${PUB_HOSTED_URL:-}" ]; then
  PUB_HOSTED_URL=https://pub.flutter-io.cn
fi
export PUB_HOSTED_URL
if [ -z "${FLUTTER_STORAGE_BASE_URL:-}" ]; then
  FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
fi
export FLUTTER_STORAGE_BASE_URL
if [ -z "${RUSTUP_HOME:-}" ]; then
  RUSTUP_HOME="$CODER_LIB/rust/rustup"
fi
export RUSTUP_HOME
if [ -z "${CARGO_HOME:-}" ]; then
  CARGO_HOME="$CODER_LIB/rust/cargo"
fi
export CARGO_HOME
if [ -z "${NVM_DIR:-}" ]; then
  NVM_DIR=/env/lib/nvm
fi
export NVM_DIR
if [ -z "${NODE_HOME:-}" ]; then
  NODE_HOME=/usr/local/lib/node/current
fi
export NODE_HOME

if [ -z "${PATH:-}" ]; then
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
fi
for dir in "$JAVA_HOME/bin" "$NODE_HOME/bin" "$GOROOT/bin" "$GOPATH/bin" "$ANDROID_HOME/platform-tools" "$ANDROID_SDK_ROOT/bin" "$FLUTTER_ROOT/bin" "$CARGO_HOME/bin"; do
  if [ -d "$dir" ]; then
    case ":$PATH:" in
      *":$dir:"*) ;;
      *) PATH="$dir:$PATH" ;;
    esac
  fi
done
export PATH
EOF

RUN cat <<'EOF' >/etc/profile.d/99-coder-shell.sh
case $- in
  *i*) CODER_INTERACTIVE=1 ;;
  *) CODER_INTERACTIVE=0 ;;
esac

if [ "${CODER_INTERACTIVE:-0}" -eq 1 ] && [ -n "${BASH_VERSION:-}" ]; then
  export SHELL=/bin/bash
  shopt -s checkwinsize
  if [ -z "${TERM:-}" ]; then
    export TERM=xterm-256color
  fi
  if command -v dircolors >/dev/null 2>&1; then
    eval "$(dircolors)"
  fi
  alias ls='ls --color=auto'
  alias ll='ls --color=auto -lhA --time-style "+%Y/%m/%d %H:%M:%S"'
  alias golinux='CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o app .'
  alias gowin='CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o app.exe .'

  if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
  if [ -f /usr/share/bash-completion/completions/git ]; then
    . /usr/share/bash-completion/completions/git
  fi
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
  fi
  if [ -s "$NVM_DIR/bash_completion" ]; then
    . "$NVM_DIR/bash_completion"
  fi

  git_prompt_info() {
    local branch dirty yellow green reset
    branch=$(git branch --show-current 2>/dev/null) || return
    [ -n "$branch" ] || return
    dirty=$(git status --porcelain 2>/dev/null)
    yellow=$(printf '\001\033[0;33m\002')
    green=$(printf '\001\033[0;32m\002')
    reset=$(printf '\001\033[0m\002')
    if [ -n "$dirty" ]; then
      printf '%s(%s ✗)%s' "$yellow" "$branch" "$reset"
    else
      printf '%s(%s ✓)%s' "$green" "$branch" "$reset"
    fi
  }

  PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\] $(git_prompt_info)\n\$ '
fi
EOF

######################################################### Filesystem cleanup #########################################################
RUN rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /var/cache/apt/* /var/tmp/* /tmp/* /var/lib/apt/lists/* \
    && rm -rf "$CODER_LIB/nvm/.git" "$HOME/.cache" "$HOME/.npm" || true
