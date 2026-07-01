#!/bin/zsh
# Symlinks the dotfiles into $HOME and sets up zsh plugins + git editor.
# (Decluttered 2026-07-01: removed the Sublime Text apparatus and the dead
#  git:// clone protocol; editor is now VS Code.)

backup() {
  target=$1
  if [ -e "$target" ] && [ ! -L "$target" ]; then   # a real file, not our symlink
    mv "$target" "$target.backup"
    echo "-----> Moved your old $target to $target.backup"
  fi
}

# Symlink each top-level config file to ~/.<name>.
# Skips directories (e.g. guardrails/), *.sh scripts, and README.
# zsh's `*` does not match dotfiles, so .gitignore is left alone too.
for name in *; do
  if [ ! -d "$name" ] && [[ ! "$name" =~ '\.sh$' ]] && [ "$name" != 'README.md' ]; then
    target="$HOME/.$name"
    backup "$target"
    if [ ! -e "$target" ]; then
      echo "-----> Symlinking $target"
      ln -s "$PWD/$name" "$target"
    fi
  fi
done

# Git commit editor -> VS Code (requires the `code` shell command on PATH).
git config --global core.editor "code --wait"

# oh-my-zsh plugins (https; git:// was removed by GitHub in 2022).
ZSH_PLUGINS_DIR="$HOME/.oh-my-zsh/custom/plugins"
mkdir -p "$ZSH_PLUGINS_DIR"
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  if [ ! -d "$ZSH_PLUGINS_DIR/$plugin" ]; then
    echo "-----> Installing zsh plugin '$plugin'..."
    git clone "https://github.com/zsh-users/$plugin" "$ZSH_PLUGINS_DIR/$plugin"
  fi
done

echo "👌  dotfiles installed. Carry on with git setup!"
