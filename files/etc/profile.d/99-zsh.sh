# Switch interactive logins to zsh when available. Safer than making zsh
# root's login shell in /etc/passwd: if the binary is ever missing (e.g.
# an image built without it), login falls back to ash instead of locking
# you out over SSH.
[ -t 0 ] || return
[ -x /usr/bin/zsh ] || return
[ -n "$ZSH_VERSION" ] && return
export ZDOTDIR="$HOME/.config/zsh"
exec /usr/bin/zsh
