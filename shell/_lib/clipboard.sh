# Copia texto pra área de transferência do sistema (Linux X11/Wayland ou
# macOS). Sourced pelos scripts que precisam copiar valor exibido (ex.:
# devstack-users). Sem dependência hard - se nenhuma ferramenta existir,
# retorna 1 e quem chamou decide como avisar o usuário.
#
# Uso:
#   dtb_copy_to_clipboard "texto" || log_warning "sem ferramenta de clipboard"
if [[ -z "${_DTB_CLIPBOARD_LOADED:-}" ]]; then
  _DTB_CLIPBOARD_LOADED=1

  dtb_copy_to_clipboard() {
    local text="$1"
    if command -v wl-copy >/dev/null 2>&1; then
      printf '%s' "$text" | wl-copy
    elif command -v xclip >/dev/null 2>&1; then
      printf '%s' "$text" | xclip -selection clipboard
    elif command -v xsel >/dev/null 2>&1; then
      printf '%s' "$text" | xsel --clipboard --input
    elif command -v pbcopy >/dev/null 2>&1; then
      printf '%s' "$text" | pbcopy
    else
      return 1
    fi
  }
fi
