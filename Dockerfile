ARG BASE_IMAGE=docker.io/codercom/code-server:latest

############################# Builder: toolchains -> /env/lib #############################
FROM ${BASE_IMAGE} AS builder
USER 0:0

ENV HOME=/root \
    CODER_LIB=/env/lib \
    JAVA_HOME=/env/lib/java \
    GOROOT=/env/lib/go \
    GOPATH=/root/.gopath \
    ANDROID_HOME=/env/lib/android \
    ANDROID_SDK_ROOT=/env/lib/android \
    ANDROID_CMDLINE_TOOLS_ROOT=/env/lib/android/cmdline-tools/latest \
    FLUTTER_ROOT=/env/lib/flutter \
    FLUTTER_ROOT_USAGE_WARNING=false \
    RUSTUP_HOME=/env/lib/rust/rustup \
    CARGO_HOME=/env/lib/rust/cargo \
    NVM_DIR=/env/lib/nvm \
    NODE_HOME=/usr/local/lib/node/current \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8
ENV PATH="$JAVA_HOME/bin:$NODE_HOME/bin:$GOROOT/bin:$GOPATH/bin:$ANDROID_HOME/platform-tools:$ANDROID_CMDLINE_TOOLS_ROOT/bin:$FLUTTER_ROOT/bin:$CARGO_HOME/bin:$PATH"

WORKDIR /root
SHELL ["/bin/bash","-o","pipefail","-c"]

# Minimal build-time deps only; heavy runtime packages live in the final stage.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl wget jq git unzip xz-utils python3 file libatomic1 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "$CODER_LIB"

######################################################### Java #########################################################
RUN mkdir -p "$JAVA_HOME" \
    && JAVA_FEATURE_VERSION="$(curl -fsSL https://api.adoptium.net/v3/info/available_releases | jq -r '.most_recent_feature_release')" \
    && curl -fsSL "https://api.adoptium.net/v3/binary/latest/${JAVA_FEATURE_VERSION}/ga/linux/x64/jdk/hotspot/normal/eclipse" \
      | tar -xz -C "$JAVA_HOME" --strip-components=1

######################################################### Go #########################################################
# Install Go and gopls, then keep only the gopls binary (drop module/build caches).
RUN wget -qO- "https://go.dev/dl/$(curl -s https://go.dev/dl/?mode=json | jq -r '.[0].version').linux-amd64.tar.gz" | tar -xz -C "$CODER_LIB" \
    && mkdir -p "$GOPATH" \
    && go install golang.org/x/tools/gopls@latest \
    && go install golang.org/x/tools/cmd/goimports@latest \
    && go install mvdan.cc/sh/v3/cmd/shfmt@latest \
    && find "$GOPATH" -mindepth 1 -maxdepth 1 ! -name bin -exec rm -rf {} + \
    && rm -rf "$HOME/.cache"

######################################################### Android #########################################################
RUN mkdir -p "$CODER_LIB/android" \
    && rm -rf /tmp/cmdline-tools /tmp/cmdline-tools.zip \
    && CMDLINE_TOOLS_ZIP="$(curl -fsSL https://dl.google.com/android/repository/repository2-1.xml | grep -o 'commandlinetools-linux-[0-9]\+_latest.zip' | sort -Vu | tail -n1)" \
    && curl -fsSL "https://dl.google.com/android/repository/${CMDLINE_TOOLS_ZIP}" -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp \
    && rm -f /tmp/cmdline-tools.zip \
    && rm -rf "$CODER_LIB/android/cmdline-tools" \
    && mkdir -p "$CODER_LIB/android/cmdline-tools" \
    && mv /tmp/cmdline-tools "$CODER_LIB/android/cmdline-tools/latest" \
    && chmod +x "$ANDROID_CMDLINE_TOOLS_ROOT/bin/"* \
    && SDKMANAGER="$ANDROID_CMDLINE_TOOLS_ROOT/bin/sdkmanager" \
    && set +o pipefail \
    && yes | "$SDKMANAGER" --sdk_root="$CODER_LIB/android" --licenses >/dev/null \
    && set -o pipefail \
    && BUILD_TOOLS_VERSION=$("$SDKMANAGER" --sdk_root="$CODER_LIB/android" --list | awk '/^ +build-tools;[0-9.]+/ {print $1}' | sort -V | tail -n1) \
    && PLATFORM_VERSION=$("$SDKMANAGER" --sdk_root="$CODER_LIB/android" --list | awk '/^ +platforms;android-[0-9]+/ {print $1}' | sort -V | tail -n1) \
    && test -n "$BUILD_TOOLS_VERSION" \
    && test -n "$PLATFORM_VERSION" \
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
    && find "$FLUTTER_ROOT/bin/cache/artifacts/engine" -maxdepth 1 -type d \( -name '*darwin*' -o -name '*ios*' -o -name '*windows*' -o -name 'linux-arm*' \) -exec rm -rf {} + \
    && rm -rf /tmp/*

######################################################### Rust #########################################################
RUN mkdir -p "$RUSTUP_HOME" "$CARGO_HOME" \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -q -y --no-modify-path --default-toolchain stable \
    && rustup component add rust-src --toolchain stable \
    && rustup component add rust-analyzer --toolchain stable \
    && rustup component add rustfmt clippy --toolchain stable \
    && rustup component remove rust-docs --toolchain stable || true \
    && rm -rf "$CARGO_HOME/registry" "$CARGO_HOME/git" "$RUSTUP_HOME/tmp" \
    && rm -rf /tmp/*

######################################################### Node js #########################################################
RUN mkdir -p "$NVM_DIR" /usr/local/lib/node \
    && NVM_VERSION="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/nvm-sh/nvm/releases/latest | sed 's#.*/##')" \
    && curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash \
    && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" \
    && nvm install node \
    && nvm alias default node \
    && NODE_VERSION="$(nvm current)" \
    && ln -sfn "$NVM_DIR/versions/node/$NODE_VERSION" /usr/local/lib/node/current \
    && nvm use default \
    && npm install -g pnpm \
    && npm config set registry https://registry.npmmirror.com/ \
    && npm cache clean --force \
    && rm -rf "$NVM_DIR/.cache" "$NVM_DIR/.git" "$HOME/.npm"

############################# Final image #############################
FROM ${BASE_IMAGE}
USER 0:0

ENV HOME=/root \
    CODER_LIB=/env/lib \
    JAVA_HOME=/env/lib/java \
    GOROOT=/env/lib/go \
    GOPATH=/root/.gopath \
    ANDROID_HOME=/env/lib/android \
    ANDROID_SDK_ROOT=/env/lib/android \
    ANDROID_CMDLINE_TOOLS_ROOT=/env/lib/android/cmdline-tools/latest \
    FLUTTER_ROOT=/env/lib/flutter \
    FLUTTER_ROOT_USAGE_WARNING=false \
    RUSTUP_HOME=/env/lib/rust/rustup \
    CARGO_HOME=/env/lib/rust/cargo \
    NVM_DIR=/env/lib/nvm \
    NODE_HOME=/usr/local/lib/node/current \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8
ENV PATH="$JAVA_HOME/bin:$NODE_HOME/bin:$GOROOT/bin:$GOPATH/bin:$ANDROID_HOME/platform-tools:$ANDROID_CMDLINE_TOOLS_ROOT/bin:$FLUTTER_ROOT/bin:$CARGO_HOME/bin:$CODER_LIB/claude:$PATH"

WORKDIR /root
SHELL ["/bin/bash","-o","pipefail","-c"]

# Locales + runtime packages + GitHub CLI, all in one layer cleaned in-place.
RUN sed -i -e 's|^# en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|' \
           -e 's|^# zh_TW.UTF-8 UTF-8|zh_TW.UTF-8 UTF-8|' \
           -e 's|^# zh_CN.UTF-8 UTF-8|zh_CN.UTF-8 UTF-8|' \
           -e 's|^# zh_HK.UTF-8 UTF-8|zh_HK.UTF-8 UTF-8|' /etc/locale.gen \
    && locale-gen \
    && apt-get update \
    && apt-get remove nano -y \
    && apt-get install -y --no-install-recommends \
       bash-completion python3 python3-pip python3-venv pipx netcat-openbsd iputils-ping \
       wget jq curl vim zip git unzip xz-utils pkg-config libssl-dev ca-certificates \
       libatomic1 ripgrep build-essential shellcheck sshpass binutils-aarch64-linux-gnu \
       file 7zip fzf fd-find tree git-lfs cmake ninja-build clang clangd gdb universal-ctags \
    && mkdir -p -m 755 /etc/apt/keyrings \
    && wget -nv -O /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && mkdir -p -m 755 /etc/apt/sources.list.d \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && apt-get purge -y vim-tiny \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && git lfs install --system \
    && apt-get clean \
    && find /usr/share/doc -mindepth 1 -maxdepth 1 ! -name fzf -exec rm -rf {} + \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /usr/share/man/* /usr/share/info/*

######################################################### Extra CLI tools (latest release binaries) #########################################################
# uv (Astral) + yq + difftastic + ruff: resolve the newest GitHub release tag, then fetch the binary.
RUN UV_TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/astral-sh/uv/releases/latest | sed 's#.*/##')" \
    && curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_TAG}/uv-x86_64-unknown-linux-gnu.tar.gz" \
       | tar -xz -C /usr/local/bin --strip-components=1 \
    && YQ_TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/mikefarah/yq/releases/latest | sed 's#.*/##')" \
    && curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_TAG}/yq_linux_amd64" -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq \
    && DIFFT_TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/Wilfred/difftastic/releases/latest | sed 's#.*/##')" \
    && curl -fsSL "https://github.com/Wilfred/difftastic/releases/download/${DIFFT_TAG}/difft-x86_64-unknown-linux-gnu.tar.gz" \
       | tar -xz -C /usr/local/bin \
    && RUFF_TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/astral-sh/ruff/releases/latest | sed 's#.*/##')" \
    && curl -fsSL "https://github.com/astral-sh/ruff/releases/download/${RUFF_TAG}/ruff-x86_64-unknown-linux-gnu.tar.gz" \
       | tar -xz -C /usr/local/bin --strip-components=1 \
    && mkdir -p "$CODER_LIB/claude" \
    && CLAUDE_VERSION="$(curl -fsSL https://downloads.claude.ai/claude-code-releases/latest)" \
    && curl -fsSL "https://downloads.claude.ai/claude-code-releases/${CLAUDE_VERSION}/linux-x64/claude" -o "$CODER_LIB/claude/claude" \
    && echo "$(curl -fsSL "https://downloads.claude.ai/claude-code-releases/${CLAUDE_VERSION}/manifest.json" | jq -r '.platforms["linux-x64"].checksum')  $CODER_LIB/claude/claude" | sha256sum -c - \
    && chmod +x "$CODER_LIB/claude/claude" \
    && uv --version && uvx --version && yq --version && difft --version && ruff --version && claude --version

# Pull in the prebuilt toolchains (clean trees only — no build/download caches).
COPY --from=builder /env/lib /env/lib
COPY --from=builder /usr/local/lib/node /usr/local/lib/node
COPY --from=builder /root/.gopath/bin /root/.gopath/bin

# Restore the few bits of per-user state that don't live under /env/lib.
# (Flutter finds the SDK via ANDROID_SDK_ROOT/ANDROID_HOME; nvm is sourced by the profile script.)
RUN git config --global --add safe.directory "$FLUTTER_ROOT" \
    && npm config set registry https://registry.npmmirror.com/

######################################################### ast-grep + Copilot CLI (need the copied node toolchain) #########################################################
RUN npm install -g @ast-grep/cli @github/copilot \
    && copilot --version \
    && npm cache clean --force \
    && rm -rf "$HOME/.npm" "$HOME/.cache"

######################################################### code-server extensions #########################################################
# Built in the final stage so its node_modules / npm cache never persist in a layer.
RUN git clone --depth=1 https://github.com/dream10201/scrcpy_sidebar.git /tmp/scrcpy_sidebar \
    && cd /tmp/scrcpy_sidebar \
    && npm install \
    && npm run build \
    && npx --yes @vscode/vsce package --out /tmp/scrcpy_sidebar.vsix \
    && code-server --install-extension /tmp/scrcpy_sidebar.vsix --extensions-dir /usr/lib/code-server/lib/vscode/extensions/ \
    && rm -rf /tmp/scrcpy_sidebar /tmp/scrcpy_sidebar.vsix "$HOME/.npm" "$HOME/.cache"

######################################################### Profile scripts #########################################################
RUN cat <<'EOF' >/etc/profile.d/99-coder-shell.sh
if [ -z "${CODER_LIB:-}" ]; then
  CODER_LIB=/env/lib
fi
export CODER_LIB
if [ -z "${JAVA_HOME:-}" ]; then
  JAVA_HOME="$CODER_LIB/java"
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
if [ -z "${ANDROID_HOME:-}" ]; then
  ANDROID_HOME="$CODER_LIB/android"
fi
export ANDROID_HOME
if [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  ANDROID_SDK_ROOT="$ANDROID_HOME"
fi
export ANDROID_SDK_ROOT
if [ -z "${ANDROID_CMDLINE_TOOLS_ROOT:-}" ]; then
  ANDROID_CMDLINE_TOOLS_ROOT="$ANDROID_HOME/cmdline-tools/latest"
fi
export ANDROID_CMDLINE_TOOLS_ROOT
if [ -z "${FLUTTER_ROOT:-}" ]; then
  FLUTTER_ROOT="$CODER_LIB/flutter"
fi
export FLUTTER_ROOT
if [ -z "${FLUTTER_ROOT_USAGE_WARNING:-}" ]; then
  FLUTTER_ROOT_USAGE_WARNING=false
fi
export FLUTTER_ROOT_USAGE_WARNING
if [ -z "${RUSTUP_HOME:-}" ]; then
  RUSTUP_HOME="$CODER_LIB/rust/rustup"
fi
export RUSTUP_HOME
if [ -z "${CARGO_HOME:-}" ]; then
  CARGO_HOME="$CODER_LIB/rust/cargo"
fi
export CARGO_HOME
if [ -z "${NVM_DIR:-}" ]; then
  NVM_DIR="$CODER_LIB/nvm"
fi
export NVM_DIR
if [ -z "${NODE_HOME:-}" ]; then
  NODE_HOME=/usr/local/lib/node/current
fi
export NODE_HOME

if [ -z "${PATH:-}" ]; then
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
fi
for dir in "$JAVA_HOME/bin" "$NODE_HOME/bin" "$GOROOT/bin" "$GOPATH/bin" "$ANDROID_HOME/platform-tools" "$ANDROID_CMDLINE_TOOLS_ROOT/bin" "$FLUTTER_ROOT/bin" "$CARGO_HOME/bin" "$CODER_LIB/claude" "$HOME/.opencode/bin" "$HOME/.local/bin"; do
  if [ -d "$dir" ]; then
    case ":$PATH:" in
      *":$dir:"*) ;;
      *) PATH="$dir:$PATH" ;;
    esac
  fi
done
export PATH

case $- in
  *i*) CODER_INTERACTIVE=1 ;;
  *) CODER_INTERACTIVE=0 ;;
esac

if [ "${CODER_INTERACTIVE:-0}" -ne 1 ] || [ -z "${BASH_VERSION:-}" ]; then
  return
fi

if [ -n "${CODER_SHELL_INIT_DONE:-}" ]; then
  return
fi

CODER_SHELL_INIT_DONE=1
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
alias golinux_arm64='CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o app_arm64 .'
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

if command -v fzf >/dev/null 2>&1; then
  for f in /usr/share/doc/fzf/examples/key-bindings.bash /usr/share/doc/fzf/examples/completion.bash; do
    [ -f "$f" ] && . "$f"
  done
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
EOF

RUN cat <<'EOF' >>/etc/bash.bashrc

if [ -r /etc/profile.d/99-coder-shell.sh ]; then
  . /etc/profile.d/99-coder-shell.sh
fi
EOF
