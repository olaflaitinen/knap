# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : cli/completions/knap.bash
# Purpose     : Bash completion for the knap command.
# Stage       : Command line interface. See README.md
# Depends on  : bash-completion, or bash on its own.
# Invariants  : The command, option and encoding lists here must match
#               cli/args.mojo. cli/tests/test_completions.py checks that.
# -----------------------------------------------------------------------------
# Author      : Olaf Yunus Laitinen Imanov <yunus.imanov@metropolia.fi>
# ORCID       : 0009-0006-5184-0810
# Affiliation : School of Information and Communication Technology,
#               Metropolia University of Applied Sciences
# -----------------------------------------------------------------------------
# SPDX-License-Identifier: EUPL-1.2
# Copyright 2026 Olaf Yunus Laitinen Imanov
# =============================================================================
#
# Install it for one shell:
#
#     source cli/completions/knap.bash
#
# or for every shell, by copying it to the completion directory your
# distribution uses, which is usually one of:
#
#     /usr/share/bash-completion/completions/knap
#     ~/.local/share/bash-completion/completions/knap

_knap_complete() {
    local current previous
    COMPREPLY=()
    current="${COMP_WORDS[COMP_CWORD]}"
    previous="${COMP_WORDS[COMP_CWORD - 1]}"

    local commands="count encode decode vocab help version"
    local options="-e --encoding -f --file --vocab --format \
--allowed-special --strict-special -h --help -V --version"
    local encodings="cl100k_base o200k_base o200k_harmony p50k_base \
p50k_edit r50k_base gpt2"
    local formats="space lines json"

    case "${previous}" in
        -e | --encoding)
            mapfile -t COMPREPLY < <(compgen -W "${encodings}" -- "${current}")
            return 0
            ;;
        --format)
            mapfile -t COMPREPLY < <(compgen -W "${formats}" -- "${current}")
            return 0
            ;;
        -f | --file | --vocab)
            mapfile -t COMPREPLY < <(compgen -f -- "${current}")
            return 0
            ;;
        --allowed-special)
            # Deliberately not completed. The set depends on the encoding,
            # and a wrong guess here would suggest a marker that this
            # encoding does not define, which the tool would then refuse.
            return 0
            ;;
    esac

    if [[ "${current}" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "${options}" -- "${current}")
        return 0
    fi

    # The first non-option word is the command. After that, the argument is
    # the text to encode, which nothing can complete.
    local index seen=0
    for ((index = 1; index < COMP_CWORD; index++)); do
        case "${COMP_WORDS[index]}" in
            -*) ;;
            *) seen=1 ;;
        esac
    done
    if [[ "${seen}" -eq 0 ]]; then
        mapfile -t COMPREPLY < <(compgen -W "${commands}" -- "${current}")
    fi
    return 0
}

complete -F _knap_complete knap

# =============================================================================
# End of file: cli/completions/knap.bash
# =============================================================================
