#!/usr/bin/env bash
#
# Implementação real de "devstack-users" (ver script.sh no mesmo diretório
# pro porquê disto ser um processo separado em vez de função sourced).
# Pode ser chamado direto (bash impl.sh ...) além de via `devstack-users`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=../_lib/log.sh
source "$SCRIPT_DIR/../_lib/log.sh"
# shellcheck source=../_lib/db-clients.sh
source "$SCRIPT_DIR/../_lib/db-clients.sh"
# shellcheck source=../_lib/kubernetes.sh
source "$SCRIPT_DIR/../_lib/kubernetes.sh"
# shellcheck source=../_lib/clipboard.sh
source "$SCRIPT_DIR/../_lib/clipboard.sh"

# Uso e detalhes completos: ver README.md no mesmo diretório (ou
# `devstack-users -h`, que já abre este README via glow/cat).
_du_show_help() {
    if command -v glow >/dev/null 2>&1; then
        glow -w 0 "$SCRIPT_DIR/README.md"
    else
        cat "$SCRIPT_DIR/README.md"
    fi
}

log() { dtb_log_step "$1"; }
log_info() { dtb_log_ok "$1"; }
log_warning() { dtb_log_warn "$1"; }
log_error() { dtb_log_err "$1"; }

handle_error() {
    log_error "$1"
    exit 1
}

# Registra temp files para limpeza automática no EXIT.
TMPFILES=()
add_tmpfile() { TMPFILES+=("$1"); }

cleanup() {
    if [ -n "${PORT_FORWARD_PSQL_PID:-}" ] || [ -n "${PORT_FORWARD_MYSQL_PID:-}" ]; then
        echo
        log "Finalizando o script e matando processos em segundo plano..."
    fi
    if [ -n "${PORT_FORWARD_PSQL_PID:-}" ] && ps -p "$PORT_FORWARD_PSQL_PID" > /dev/null 2>&1; then
        kill "$PORT_FORWARD_PSQL_PID"
    fi
    if [ -n "${PORT_FORWARD_MYSQL_PID:-}" ] && ps -p "$PORT_FORWARD_MYSQL_PID" > /dev/null 2>&1; then
        kill "$PORT_FORWARD_MYSQL_PID"
    fi
    for f in "${TMPFILES[@]:-}"; do
        rm -f "$f"
    done
}
trap cleanup EXIT

# Aguarda até que a porta local esteja acessível (máx 15 tentativas).
wait_for_port() {
    local port=$1 tries=0
    while ! (echo >/dev/tcp/127.0.0.1/"$port") 2>/dev/null; do
        (( tries++ >= 15 )) && handle_error "Port-forward na porta $port não respondeu após 15s."
        sleep 1
    done
}

# Gera script auxiliar de preview para o fzf de usuários.
# Recebe via CLI: $1 = arquivo de dados raw (TSV), $2 = número da linha (1-based).
build_preview_script() {
    PREVIEW_SCRIPT=$(mktemp)
    add_tmpfile "$PREVIEW_SCRIPT"
    cat > "$PREVIEW_SCRIPT" <<'PREVIEW'
#!/usr/bin/env bash
LC_ALL=C awk -F'\t' -v n="$2" 'NR==n {
    printf "User ID:        %s\n", $1
    printf "Nome:           %s\n", $2
    printf "CPF/CNPJ:       %s\n", $3
    printf "User Hash:      %s\n", $4
    printf "Email:          %s\n", $5
    printf "is_staff:       %s\n", $6
    printf "is_superuser:   %s\n", $7
    printf "has_fraud:      %s\n", $8
    printf "tsa_active:     %s\n", $9
    printf "tsa_secret:     %s\n", $10
    printf "pin:            %s\n", $11
    printf "palavra_segura: %s\n", $12
}' "$1"
PREVIEW
    chmod +x "$PREVIEW_SCRIPT"
    export PREVIEW_SCRIPT
}

# Atualiza public.balances.available do par (wallet_public_id, asset) no PostgreSQL.
# Valida valor como numérico e exige confirmação explícita antes do UPDATE.
edit_balance() {
    local wallet_public_id="$1" wallet_name="$2" wallet_type="$3" asset="$4" current_avail="$5"

    echo
    log "Editar saldo de \"$asset\" em $wallet_name ($wallet_type)"
    log "Valor atual: $current_avail"

    local new_val
    read -r -p "Novo valor (ENTER vazio cancela): " new_val

    if [ -z "$new_val" ]; then
        log_warning "Edição cancelada."
        return
    fi

    if ! [[ "$new_val" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Valor inválido (esperado número, ex.: 100 ou 12.34567890): $new_val"
        return
    fi

    local confirm
    read -r -p "Confirmar UPDATE de saldo \"$asset\" para \"$new_val\" (wallet=$wallet_name [$wallet_type], public_id=$wallet_public_id)? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        log_warning "Edição cancelada."
        return
    fi

    local asset_esc=${asset//\'/\'\'}
    local user_esc=${wallet_public_id//\'/\'\'}

    log "Atualizando saldo..."
    local err_file
    err_file=$(mktemp)
    add_tmpfile "$err_file"
    psql postgres://postgres:secret@127.0.0.1:5433/banco_central -v ON_ERROR_STOP=1 -c "
        UPDATE public.balances SET available = $new_val
        WHERE user_id = '$user_esc' AND asset = '$asset_esc';
    " > /dev/null 2>"$err_file"
    local rc=$?
    if [ $rc -ne 0 ]; then
        log_error "Falha ao atualizar saldo (rc=$rc):"
        cat "$err_file" >&2
    else
        log_info "Saldo de $asset atualizado: \"$current_avail\" -> \"$new_val\""
    fi
}

# Abre fzf de subwallets para o usuário cujo raw_line foi passado.
# Tabela: nome + tipo. Preview: public_id, tipo, account_id.
# Enter busca saldos de todos os ativos da subwallet selecionada. ESC volta.
show_subwallet_fzf() {
    local raw_line="$1"
    local user_hash user_name user_id
    user_hash=$(echo "$raw_line" | cut -f4)
    user_name=$(echo "$raw_line" | cut -f2)
    user_id=$(echo "$raw_line" | cut -f1)

    echo
    log "Buscando subwallets de $user_name..."

    local account_id
    account_id=$(psql postgres://postgres:secret@127.0.0.1:5433/bilbo -t -A -c "
        SELECT owner_account_id FROM public.wallet WHERE public_id = '$user_hash' LIMIT 1;
    " 2>/dev/null | head -n 1)

    if [ -z "$account_id" ]; then
        log_warning "Nenhuma conta encontrada para $user_name."
        return
    fi

    local wallets
    wallets=$(psql postgres://postgres:secret@127.0.0.1:5433/bilbo -t -A -c "
        SELECT public_id, name, type FROM public.wallet WHERE owner_account_id = '$account_id' ORDER BY type, name;
    " 2>/dev/null)

    if [ -z "$wallets" ]; then
        log_warning "Nenhuma subwallet encontrada para $user_name."
        return
    fi

    local sw_data sw_preview
    sw_data=$(mktemp)
    sw_preview=$(mktemp)
    add_tmpfile "$sw_data"
    add_tmpfile "$sw_preview"
    echo "$wallets" > "$sw_data"

    # Preview script: expande account_id/user_name/user_id em tempo de criação.
    {
        echo '#!/usr/bin/env bash'
        echo 'SW_FILE="$1"'
        echo 'LINE_NUM="$2"'
        echo "ACCOUNT_ID=$(printf '%q' "$account_id")"
        echo "USER_NAME=$(printf '%q' "$user_name")"
        echo "USER_ID=$(printf '%q' "$user_id")"
        cat <<'SWPREVIEW'
LC_ALL=C awk -F'|' -v n="$LINE_NUM" 'NR==n {
    printf "Public ID:  %s\n", $1
    printf "Nome:       %s\n", $2
    printf "Tipo:       %s\n", $3
}' "$SW_FILE"
printf "\nAccount ID: %s\n" "$ACCOUNT_ID"
printf "Usuário:    %s (ID: %s)\n" "$USER_NAME" "$USER_ID"
SWPREVIEW
    } > "$sw_preview"
    chmod +x "$sw_preview"

    local sw_display
    sw_display=$(LC_ALL=C awk -F'|' '{printf "%d\t%-20s  %s\n", NR, substr($2, 1, 20), $3}' "$sw_data")

    while true; do
        local fzf_result selected line_num wallet_public_id wallet_name wallet_type
        fzf_result=$(echo "$sw_display" | fzf \
            --expect='enter' \
            --print-query \
            --no-hscroll \
            --layout=reverse \
            --delimiter=$'\t' \
            --with-nth=2 \
            --header=$'[ENTER] ver saldos | [ESC] voltar\nNOME                  TIPO' \
            --prompt="Subwallets > " \
            --preview="$sw_preview $sw_data {1}" \
            --preview-window='right:50%:wrap' \
            --height=90% \
            --border)

        selected=$(echo "$fzf_result" | sed -n '3p')

        if [ -z "$selected" ]; then
            break
        fi

        line_num=$(echo "$selected" | cut -f1)
        IFS='|' read -r wallet_public_id wallet_name wallet_type < \
            <(awk -F'|' -v n="$line_num" 'NR==n' "$sw_data")

        log "Obtendo saldos de todos os ativos de \"$wallet_name\" ($wallet_type)..."

        local bal_preview
        bal_preview=$(mktemp)
        add_tmpfile "$bal_preview"
        {
            echo '#!/usr/bin/env bash'
            echo "printf 'Subwallet:  %s\n' $(printf '%q' "$wallet_name")"
            echo "printf 'Tipo:       %s\n' $(printf '%q' "$wallet_type")"
            echo "printf 'Public ID:  %s\n' $(printf '%q' "$wallet_public_id")"
            echo "printf '\n'"
            echo "printf 'Account ID: %s\n' $(printf '%q' "$account_id")"
            echo "printf 'Usuário:    %s (ID: %s)\n' $(printf '%q' "$user_name") $(printf '%q' "$user_id")"
        } > "$bal_preview"
        chmod +x "$bal_preview"

        while true; do
            local balances
            balances=$(psql postgres://postgres:secret@127.0.0.1:5433/banco_central -t -A -c "
                SELECT asset, available
                FROM public.balances
                WHERE user_id = '$wallet_public_id'
                ORDER BY asset;
            " 2>/dev/null)

            if [ -z "$balances" ]; then
                echo "Nenhum saldo encontrado para \"$wallet_name\" ($wallet_type)." | fzf \
                    --no-hscroll \
                    --layout=reverse \
                    --header=$'[ESC] voltar' \
                    --prompt="Saldos > " \
                    --height=90% \
                    --border \
                    --bind='enter:ignore'
                break
            fi

            local bal_display bal_result bal_key bal_selected asset_sel avail_sel
            bal_display=$(echo "$balances" | LC_ALL=C awk -F'|' '{printf "%-20s %s\n", $1, $2}')
            bal_result=$(echo "$bal_display" | fzf \
                --expect='ctrl-e' \
                --print-query \
                --no-hscroll \
                --layout=reverse \
                --header=$'[CTRL-E] editar saldo | [ESC] voltar\nATIVO                DISPONÍVEL' \
                --prompt="Saldos > " \
                --preview="$bal_preview" \
                --preview-window='right:40%:wrap' \
                --height=90% \
                --border \
                --no-sort \
                --bind='enter:ignore')

            bal_key=$(echo "$bal_result" | sed -n '2p')
            bal_selected=$(echo "$bal_result" | sed -n '3p')

            if [ -z "$bal_selected" ]; then
                break
            fi

            case "$bal_key" in
                ctrl-e)
                    asset_sel=$(echo "$bal_selected" | awk '{print $1}')
                    avail_sel=$(echo "$bal_selected" | awk '{print $2}')
                    edit_balance "$wallet_public_id" "$wallet_name" "$wallet_type" "$asset_sel" "$avail_sel"
                    ;;
            esac
        done
    done
}

# Carrega/recarrega dados de usuários do MySQL para RAW_DATA e USERS_DISPLAY.
load_users_data() {
    log "Consultando usuários..."
    local data
    data=$(MYSQL_PWD=secret mysql -u root -h 127.0.0.1 -P 3307 --default-character-set=utf8mb4 mercadobitcoin -N -B 2>/dev/null <<'EOF'
SELECT pc.user_id, pc.nomerazao, pc.cpfcnpj, pch.hash AS user_hash, au.email,
       au.is_staff, au.is_superuser, pc.has_fraud, pc.tsa_active,
       pc.tsa_secret, pc.pin, pc.palavra_segura
FROM principal_cliente pc
LEFT JOIN principal_clientehash pch ON pch.user_id = pc.user_id
LEFT JOIN auth_user au ON au.id = pc.user_id
ORDER BY pc.nomerazao;
EOF
)
    local mysql_rc=$?
    if [ $mysql_rc -ne 0 ]; then
        handle_error "Falha ao consultar usuários no MySQL (rc=$mysql_rc)."
    fi
    if [ -z "$data" ]; then
        handle_error "Nenhum usuário encontrado."
    fi
    echo "$data" > "$RAW_DATA"

    local total
    total=$(awk 'END{print NR}' "$RAW_DATA")
    log "$total usuário(s) carregado(s)."

    # Campo 1 = número da linha (oculto via --with-nth, usado para lookup).
    # Campo 2 = display visível + hash/email após padding largo.
    USERS_DISPLAY=$(LC_ALL=C awk -F'\t' '{
        name = substr($2, 1, 20)
        printf "%d\t%-10s  %-20s  %-16s%-200s%s %s\n", NR, $1, name, $3, " ", $4, $5
    }' "$RAW_DATA")
}

# Edita Nome / Email / PIN / Palavra Segura do usuário via UPDATE no MySQL.
# Recebe raw_line (linha TSV de RAW_DATA). Confirmação obrigatória antes do UPDATE.
edit_user_field() {
    local raw_line="$1"
    local user_id user_name current_email current_pin current_palavra
    user_id=$(echo "$raw_line" | cut -f1)
    user_name=$(echo "$raw_line" | cut -f2)
    current_email=$(echo "$raw_line" | cut -f5)
    current_pin=$(echo "$raw_line" | cut -f11)
    current_palavra=$(echo "$raw_line" | cut -f12)

    if ! [[ "$user_id" =~ ^[0-9]+$ ]]; then
        log_error "user_id inválido: $user_id"
        return
    fi

    local field
    field=$(printf "Nome\nEmail\nPIN\nPalavra Segura\n" | fzf \
        --layout=reverse \
        --header="Editar campo de $user_name (ID: $user_id) | [ENTER] selecionar | [ESC] cancelar" \
        --prompt="Campo > " \
        --height=40% \
        --border \
        --no-sort)

    [ -z "$field" ] && return

    # table + column + WHERE clause variam por campo.
    # auth_user usa coluna id; principal_cliente usa coluna user_id.
    local table column where_col current_val
    case "$field" in
        "Nome")           table="principal_cliente"; column="nomerazao";      where_col="user_id"; current_val="$user_name" ;;
        "Email")          table="auth_user";         column="email";          where_col="id";      current_val="$current_email" ;;
        "PIN")            table="principal_cliente"; column="pin";            where_col="user_id"; current_val="$current_pin" ;;
        "Palavra Segura") table="principal_cliente"; column="palavra_segura"; where_col="user_id"; current_val="$current_palavra" ;;
        *) return ;;
    esac

    echo
    log "Valor atual de \"$field\": $current_val"
    local new_val
    read -r -p "Novo valor (ENTER vazio cancela): " new_val

    if [ -z "$new_val" ]; then
        log_warning "Edição cancelada."
        return
    fi

    local confirm
    read -r -p "Confirmar UPDATE de \"$field\" para \"$new_val\" (user_id=$user_id)? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        log_warning "Edição cancelada."
        return
    fi

    # Escapa backslash e aspas simples para SQL string literal.
    local escaped
    escaped=${new_val//\\/\\\\}
    escaped=${escaped//\'/\\\'}

    log "Atualizando $field do usuário $user_name (ID: $user_id)..."
    local err_file
    err_file=$(mktemp)
    add_tmpfile "$err_file"
    MYSQL_PWD=secret mysql -u root -h 127.0.0.1 -P 3307 --default-character-set=utf8mb4 mercadobitcoin 2>"$err_file" <<EOF
UPDATE $table SET $column = '$escaped' WHERE $where_col = $user_id;
EOF
    local rc=$?
    if [ $rc -ne 0 ]; then
        log_error "Falha ao atualizar $field (rc=$rc):"
        cat "$err_file" >&2
    else
        log_info "$field atualizado: \"$current_val\" -> \"$new_val\""
    fi
}

# Copia um campo do usuário (User ID/Nome/CPF/User Hash/Email/PIN/Palavra
# Segura) pra área de transferência. Recebe raw_line (linha TSV de RAW_DATA).
copy_user_field() {
    local raw_line="$1"
    local user_id user_name cpf user_hash email pin palavra
    user_id=$(echo "$raw_line" | cut -f1)
    user_name=$(echo "$raw_line" | cut -f2)
    cpf=$(echo "$raw_line" | cut -f3)
    user_hash=$(echo "$raw_line" | cut -f4)
    email=$(echo "$raw_line" | cut -f5)
    pin=$(echo "$raw_line" | cut -f11)
    palavra=$(echo "$raw_line" | cut -f12)

    local choice
    choice=$(printf "User ID\t%s\nNome\t%s\nCPF/CNPJ\t%s\nUser Hash\t%s\nEmail\t%s\nPIN\t%s\nPalavra Segura\t%s\n" \
        "$user_id" "$user_name" "$cpf" "$user_hash" "$email" "$pin" "$palavra" | fzf \
        --delimiter=$'\t' \
        --with-nth=1 \
        --layout=reverse \
        --header="Copiar campo de $user_name (ID: $user_id) | [ENTER] copiar | [ESC] cancelar" \
        --prompt="Campo > " \
        --preview='echo {2}' \
        --preview-window='right:60%:wrap' \
        --height=50% \
        --border \
        --no-sort)

    [ -z "$choice" ] && return

    local field value
    field=$(echo "$choice" | cut -f1)
    value=$(echo "$choice" | cut -f2)

    if dtb_copy_to_clipboard "$value"; then
        log_info "\"$field\" copiado pra área de transferência."
    else
        log_warning "Nenhuma ferramenta de clipboard encontrada (xclip/xsel/wl-copy/pbcopy)."
        echo "$field: $value"
    fi
}

# Lista usuários via MySQL e seleciona um via fzf.
# Enter abre subwallets. CTRL-E edita Nome/PIN/Palavra Segura. CTRL-Y copia
# um campo pra área de transferência. ESC fecha.
list_and_select_user() {
    RAW_DATA=$(mktemp)
    add_tmpfile "$RAW_DATA"
    export RAW_DATA

    load_users_data
    build_preview_script

    local query="${USER_INPUT:-}"

    while true; do
        local fzf_result key selected line_num raw_line
        fzf_result=$(echo "$USERS_DISPLAY" | fzf \
            --expect='enter,ctrl-e,ctrl-y' \
            --print-query \
            --no-hscroll \
            --layout=reverse \
            --delimiter=$'\t' \
            --with-nth=2 \
            --header=$'[ENTER] subwallets | [CTRL-E] editar dados | [CTRL-Y] copiar campo | [ESC] fechar\nUSER_ID     NOME                  CPF/CNPJ' \
            --prompt='Filtrar > ' \
            --query="$query" \
            --preview="$PREVIEW_SCRIPT $RAW_DATA {1}" \
            --preview-window='right:55%:wrap' \
            --height=90% \
            --border)

        # Com --print-query: linha 1 = query, linha 2 = key, linha 3 = item
        query=$(echo "$fzf_result" | sed -n '1p')
        key=$(echo "$fzf_result" | sed -n '2p')
        selected=$(echo "$fzf_result" | sed -n '3p')

        if [ -z "$selected" ]; then
            exit 0
        fi

        line_num=$(echo "$selected" | cut -f1)
        raw_line=$(awk -v n="$line_num" 'NR==n' "$RAW_DATA")

        case "$key" in
            ctrl-e)
                edit_user_field "$raw_line"
                load_users_data
                ;;
            ctrl-y)
                copy_user_field "$raw_line"
                ;;
            *)
                show_subwallet_fzf "$raw_line"
                ;;
        esac
    done
}

# --- Main ---------------------------------------------------------------------

log "Iniciando devstack-users..."

_ARG_NAMESPACE=""
_ARG_FILTER=""
_POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            _du_show_help
            exit 0
            ;;
        -n|--namespace)
            _ARG_NAMESPACE="$2"
            shift 2
            ;;
        -f|--filter)
            _ARG_FILTER="$2"
            shift 2
            ;;
        -*)
            log_error "Flag desconhecida: $1"
            log_error "Ajuda: devstack-users -h"
            exit 1
            ;;
        *)
            _POSITIONAL+=("$1")
            shift
            ;;
    esac
done

dtb_check_kubectl_installed || exit 1
dtb_check_cluster "gke_mb-dev-277014_us-east4-a_mb-dev-gke" \
    "gcloud container clusters get-credentials mb-dev-gke --zone us-east4-a --project mb-dev-277014" || exit 1
dtb_check_psql_installed || exit 1
dtb_check_mysql_installed || exit 1

if [ -n "$_ARG_NAMESPACE" ]; then
    NAMESPACE="$_ARG_NAMESPACE"
    log_info "Usando NAMESPACE da flag -n: $NAMESPACE"
elif [ -n "${_POSITIONAL[0]:-}" ]; then
    NAMESPACE="${_POSITIONAL[0]}"
    log_info "Usando NAMESPACE da linha de comando: $NAMESPACE"
elif [ -n "${NAMESPACE:-}" ]; then
    log_info "Usando NAMESPACE do ambiente: $NAMESPACE"
elif [ -t 1 ] && command -v gum >/dev/null 2>&1; then
    _ns_list="$(dtb_list_namespaces "Buscando namespaces do cluster...")"
    if [ -n "$_ns_list" ]; then
        NAMESPACE=$(echo "$_ns_list" | tr ' ' '\n' | gum filter --height 15 --header="Selecione o namespace:")
    fi
    [ -z "$NAMESPACE" ] && read -r -p "Informe o nome do ambiente: " NAMESPACE
else
    read -r -p "Informe o nome do ambiente: " NAMESPACE
fi

if [ -n "$_ARG_FILTER" ]; then
    USER_INPUT="$_ARG_FILTER"
    log_info "Filtro inicial do fzf (flag -f): $USER_INPUT"
elif [ -n "${_POSITIONAL[1]:-}" ]; then
    USER_INPUT="${_POSITIONAL[1]}"
    log_info "Filtro inicial do fzf: $USER_INPUT"
elif [ -n "${USER_INPUT:-}" ]; then
    log_info "Filtro inicial do fzf (env): $USER_INPUT"
fi

echo
dtb_check_namespace_exists "$NAMESPACE" || exit 1

log "Port-forward PostgreSQL do ambiente..."
kubectl port-forward services/common-services 5433:5432 -n "$NAMESPACE" &> /dev/null &
PORT_FORWARD_PSQL_PID=$!

log "Port-forward MySQL do ambiente..."
kubectl port-forward services/common-services 3307:3306 -n "$NAMESPACE" &> /dev/null &
PORT_FORWARD_MYSQL_PID=$!

wait_for_port 5433
wait_for_port 3307

echo
list_and_select_user

echo
log_info "Script finalizado!"
