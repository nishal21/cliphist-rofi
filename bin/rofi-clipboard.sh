#!/usr/bin/env bash

export PATH="/usr/local/bin:/usr/bin:/bin"
export COSMIC_DATA_CONTROL_ENABLED="${COSMIC_DATA_CONTROL_ENABLED:-1}"

PINNED_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/cliphist/pinned.txt"
THEME_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/cliphist/clipboard.rasi"
ICON_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist/rofi-icons"
DEFERRED_FILE="${XDG_RUNTIME_DIR:-/tmp}/cliphist-deferred"
DEFERRED_TYPE="${XDG_RUNTIME_DIR:-/tmp}/cliphist-deferred-type"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/cliphist"
RUNTIME_PID="${RUNTIME_DIR}/rofi.pid"

ROFI_OPTS=(
    -click-to-exit
    -window-hide-active-window true
)

ACTION_CLEAR="Clear all"
ACTION_MANAGE="Manage pinned items"

URGENT_IDXS=()
ACTIVE_IDXS=()
FIRST_SELECTABLE=0
LINE_IDX=0
TMP_LIST=""
TMP_DISPLAY=""
LOOKUP_FILE=""

join_csv() {
    local out="" item
    for item in "$@"; do
        [[ -z "$item" ]] && continue
        if [[ -z "$out" ]]; then
            out="$item"
        else
            out+=",$item"
        fi
    done
    printf '%s' "$out"
}

clean_selection() {
    # Bash 5.3+: $'\0' is empty and ${var%%$'\0'*} becomes ${var%%*} → wipes text.
    printf '%s' "$1" | sed 's/\x0.*//'
}

display_label() {
    clean_selection "$1"
}

truncate_preview() {
    local text="$1"
    local max=72
    if ((${#text} > max)); then
        printf '%s…' "${text:0:max}"
    else
        printf '%s' "$text"
    fi
}

is_pinned_item() {
    local line
    line=$(clean_selection "$1")
    [[ "$line" == 📌* ]]
}

is_action_row() {
    case "$(clean_selection "$1")" in
        "$ACTION_CLEAR"|"$ACTION_MANAGE") return 0 ;;
        *) return 1 ;;
    esac
}

is_non_selectable() {
    is_action_row "$1"
}

is_image_entry() {
    [[ "$1" == *$'\0icon'* ]] || [[ "$1" == *icon$'\x1f'* ]]
}

append_list_row() {
    local display="$1"
    local payload="$2"

    printf '%s\n' "$display" >>"$TMP_DISPLAY"
    printf '%s\n' "$payload" >>"$LOOKUP_FILE"
    printf '%s\n' "$display" >>"$TMP_LIST"
    ((LINE_IDX++))
}

lookup_payload() {
    local selected="$1"
    local n=0 line

    selected=$(clean_selection "$selected")

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$selected" ]]; then
            sed -n "$((n + 1))p" "$LOOKUP_FILE"
            return 0
        fi
        ((n++))
    done <"$TMP_DISPLAY"

    return 1
}

copy_from_payload() {
    local payload="$1"
    local kind="${payload%%:*}"
    local value="${payload#*:}"
    local content

    case "$kind" in
        pinned | text)
            printf '%s' "$value" | wl-copy
            ;;
        history)
            content=$(cliphist decode "$value" 2>/dev/null) || return 1
            printf '%s' "$content" | wl-copy
            ;;
        image)
            cliphist decode "$value" | wl-copy --type image/png
            ;;
        *)
            return 1
            ;;
    esac
}

schedule_from_payload() {
    local payload="$1"
    local kind="${payload%%:*}"
    local value="${payload#*:}"
    local content

    case "$kind" in
        pinned | text)
            schedule_wtype "$kind" "$value"
            ;;
        history)
            content=$(cliphist decode "$value" 2>/dev/null) || return 1
            schedule_wtype "text" "$content"
            ;;
        image)
            schedule_wtype "image" "1"
            ;;
    esac
}

schedule_wtype() {
    local kind="$1"
    local payload="$2"
    printf '%s' "$kind" >"$DEFERRED_TYPE"
    printf '%s' "$payload" >"$DEFERRED_FILE"
}

run_deferred_wtype() {
    [[ -f "$DEFERRED_FILE" ]] || return 0

    local kind payload
    kind=$(<"$DEFERRED_TYPE")
    payload=$(<"$DEFERRED_FILE")
    rm -f "$DEFERRED_FILE" "$DEFERRED_TYPE"

    command -v wtype >/dev/null 2>&1 || return 0

    (
        sleep 0.35
        case "$kind" in
            text|pinned)
                printf '%s' "$payload" | wtype -
                ;;
            image)
                wtype -M ctrl v -m ctrl 2>/dev/null
                ;;
        esac
    ) &
}

ensure_image_thumb() {
    local id="$1"
    local src="$ICON_DIR/$id.png"
    local thumb="$ICON_DIR/$id-sm.png"

    [[ -f "$src" ]] || return 1

    if [[ ! -f "$thumb" || "$src" -nt "$thumb" ]]; then
        if command -v magick >/dev/null 2>&1; then
            magick "$src" -thumbnail 96x72\> -filter Lanczos -quality 85 "$thumb" 2>/dev/null \
                || cp "$src" "$thumb"
        else
            cp "$src" "$thumb"
        fi
    fi

    printf '%s' "$thumb"
}

format_display_line() {
    local line="$1"
    local id="${line%%$'\t'*}"
    local preview="${line#*$'\t'}"
    local display

    if [[ "$preview" == *"[[ binary data"* && "$preview" == *"png"* ]]; then
        local icon="$ICON_DIR/$id.png"
        local thumb dims dims_label
        dims=$(printf '%s' "$preview" | sed -n 's/.*png[[:space:]]*\([0-9][0-9]*x[0-9][0-9]*\).*/\1/p')
        mkdir -p "$ICON_DIR"
        if [[ ! -f "$icon" ]]; then
            cliphist decode "$id" >"$icon" 2>/dev/null || rm -f "$icon"
        fi
        if [[ -f "$icon" ]]; then
            thumb=$(ensure_image_thumb "$id") || thumb="$icon"
            dims_label="${dims:-Screenshot}"
            dims_label="${dims_label//x/×}"
            display="$dims_label"
            printf '%s\n' "$display" >>"$TMP_DISPLAY"
            printf '%s\n' "image:$id" >>"$LOOKUP_FILE"
            printf '%s\0icon\x1f%s\n' "$display" "$thumb" >>"$TMP_LIST"
            ((LINE_IDX++))
        else
            append_list_row "${dims:-Screenshot}" "image:$id"
        fi
        return
    fi

    if [[ "$preview" =~ ^https?:// ]]; then
        display=$(truncate_preview "🔗 $preview")
        append_list_row "$display" "history:$id"
        return
    fi

    display=$(truncate_preview "$preview")
    append_list_row "$display" "history:$id"
}

build_list() {
    local tmp="$1"
    URGENT_IDXS=()
    ACTIVE_IDXS=()
    FIRST_SELECTABLE=0
    LINE_IDX=0

    TMP_LIST="$tmp"
    TMP_DISPLAY="${tmp}.display"
    LOOKUP_FILE="${tmp}.lookup"
    : >"$TMP_LIST"
    : >"$TMP_DISPLAY"
    : >"$LOOKUP_FILE"

    append_list_row "$ACTION_CLEAR" "action:clear"
    URGENT_IDXS+=("$((LINE_IDX - 1))")

    if [[ -f "$PINNED_FILE" ]]; then
        while IFS= read -r pin_line || [[ -n "$pin_line" ]]; do
            [[ -z "$pin_line" || "$pin_line" =~ ^[[:space:]]*# ]] && continue
            append_list_row "$pin_line" "pinned:${pin_line#📌 }"
            ACTIVE_IDXS+=("$((LINE_IDX - 1))")
        done <"$PINNED_FILE"
    fi

    local hist_line
    while IFS= read -r hist_line; do
        [[ -z "$hist_line" ]] && continue
        format_display_line "$hist_line"
    done < <(cliphist list 2>/dev/null)

    append_list_row "$ACTION_MANAGE" "action:manage"
    URGENT_IDXS+=("$((LINE_IDX - 1))")
}

pick_entry() {
    local tmp="$1"
    local urgent active
    urgent=$(join_csv "${URGENT_IDXS[@]}")
    active=$(join_csv "${ACTIVE_IDXS[@]}")

    local -a args=(
        -dmenu
        -no-config
        -p "Clipboard"
        -theme "$THEME_FILE"
        -show-icons
        -selected-row "$FIRST_SELECTABLE"
        -kb-row-up "Up"
        -kb-delete-entry "Control+Shift+Delete"
        -kb-custom-1 "Shift+Delete"
        -kb-custom-2 "Control+Alt+p"
        -kb-custom-3 "Control+Alt+m"
        -kb-custom-4 "Control+Alt+c"
        "${ROFI_OPTS[@]}"
    )

    [[ -n "$urgent" ]] && args+=(-u "$urgent")
    [[ -n "$active" ]] && args+=(-a "$active")

    rofi "${args[@]}" <"$tmp"
}

delete_entry() {
    local selected payload kind value label
    selected=$(clean_selection "$1")
    payload=$(lookup_payload "$selected") || return

    kind="${payload%%:*}"
    value="${payload#*:}"

    case "$kind" in
        pinned)
            label=$(clean_selection "$selected")
            if [[ -f "$PINNED_FILE" ]]; then
                grep -Fxv "$label" "$PINNED_FILE" >"${PINNED_FILE}.tmp" 2>/dev/null || true
                mv "${PINNED_FILE}.tmp" "$PINNED_FILE"
            fi
            ;;
        history | image)
            cliphist list | grep -m1 "^${value}$(printf '\t')" | cliphist delete
            ;;
    esac
}

pin_entry() {
    local selected payload kind value content pin_line
    selected=$(clean_selection "$1")
    payload=$(lookup_payload "$selected") || return

    kind="${payload%%:*}"
    value="${payload#*:}"

    case "$kind" in
        action | pinned) return ;;
        history)
            content=$(cliphist decode "$value" 2>/dev/null) || return
            ;;
        image)
            content=$(cliphist decode "$value" 2>/dev/null) || return
            ;;
        *) return ;;
    esac

    [[ -z "$content" ]] && return

    pin_line="📌 $content"
    if [[ -f "$PINNED_FILE" ]] && grep -Fxq "$pin_line" "$PINNED_FILE" 2>/dev/null; then
        return
    fi

    printf '%s\n' "$pin_line" >>"$PINNED_FILE"
}

paste_entry() {
    local selected line payload kind
    selected=$(clean_selection "$1")
    line="$selected"

    payload=$(lookup_payload "$selected" 2>/dev/null) || payload=""

    case "$payload" in
        action:clear)
            confirm_clear
            return 2
            ;;
        action:manage)
            open_pinned_editor
            return 1
            ;;
    esac

    case "$line" in
        "$ACTION_CLEAR")
            confirm_clear
            return 2
            ;;
        "$ACTION_MANAGE")
            open_pinned_editor
            return 1
            ;;
    esac

    [[ -n "$payload" ]] || return 1
    kind="${payload%%:*}"

    case "$kind" in
        action) return 1 ;;
        pinned | history | image | text)
            copy_from_payload "$payload" || return 1
            schedule_from_payload "$payload"
            ;;
    esac
    return 1
}

open_pinned_editor() {
    if command -v cosmic-edit >/dev/null 2>&1; then
        cosmic-edit "$PINNED_FILE" >/dev/null 2>&1 &
    else
        "${EDITOR:-nano}" "$PINNED_FILE" >/dev/null 2>&1 &
    fi
}

confirm_clear() {
    local choice
    choice=$(
        printf '%s\n' "Clear all history" "Cancel" |
            rofi -dmenu -no-config -p "Clear clipboard?" -theme "$THEME_FILE" \
                -selected-row 1 "${ROFI_OPTS[@]}"
    )
    [[ "$choice" == "Clear all history" ]] || return 1

    cliphist wipe
    printf '' | wl-copy
    rm -rf "${ICON_DIR:?}/"*
}

close_if_open() {
    [[ -f "$RUNTIME_PID" ]] || return 1

    local old_pid
    old_pid=$(<"$RUNTIME_PID")
    [[ -n "$old_pid" ]] || { rm -f "$RUNTIME_PID"; return 1; }

    if kill -0 "$old_pid" 2>/dev/null; then
        kill -TERM "$old_pid" 2>/dev/null
        pkill -TERM -P "$old_pid" 2>/dev/null
        rm -f "$RUNTIME_PID"
        return 0
    fi

    rm -f "$RUNTIME_PID"
    return 1
}

main() {
    mkdir -p "$RUNTIME_DIR"
    if close_if_open; then
        exit 0
    fi

    printf '%s\n' $$ >"$RUNTIME_PID"
    trap 'rm -f "$RUNTIME_PID" "$TMP_LIST" "${TMP_LIST}.lookup" "${TMP_LIST}.display"' EXIT INT TERM

    local tmp selected exit_code result payload

    TMP_LIST=$(mktemp)

    while true; do
        build_list "$TMP_LIST"
        selected=$(pick_entry "$TMP_LIST")
        exit_code=$?

        case "$exit_code" in
            1) break ;;
            11)
                delete_entry "$selected"
                continue
                ;;
            12)
                pin_entry "$selected"
                continue
                ;;
            13)
                open_pinned_editor
                continue
                ;;
            14)
                confirm_clear
                continue
                ;;
            0)
                paste_entry "$selected"
                result=$?
                [[ "$result" -eq 2 ]] && continue
                break
                ;;
            *)
                break
                ;;
        esac
    done

    run_deferred_wtype
}

main "$@"
