# =============================================================================
# Project     : Knap, a pure Mojo byte level BPE tokenizer
# File        : cli/completions/knap.fish
# Purpose     : Fish completion for the knap command.
# Stage       : Command line interface. See README.md
# Depends on  : fish.
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
# Install it by copying this file to ~/.config/fish/completions/knap.fish

complete -c knap -f

complete -c knap -n __fish_use_subcommand -a count \
    -d 'Print how many tokens the input becomes'
complete -c knap -n __fish_use_subcommand -a encode \
    -d 'Print the token ids the input becomes'
complete -c knap -n __fish_use_subcommand -a decode \
    -d 'Turn token ids back into the bytes they represent'
complete -c knap -n __fish_use_subcommand -a vocab \
    -d 'Print what is known about an encoding, or about one word'
complete -c knap -n __fish_use_subcommand -a help -d 'Print the usage message'
complete -c knap -n __fish_use_subcommand -a version -d 'Print the version'

complete -c knap -s e -l encoding -x -d 'Which encoding to use' \
    -a 'cl100k_base o200k_base o200k_harmony p50k_base p50k_edit r50k_base gpt2'
complete -c knap -s f -l file -r -F -d 'Read the input from a file'
complete -c knap -l vocab -r -F -d 'Use this vocabulary file'
complete -c knap -l format -x -a 'space lines json' \
    -d 'Shape of the printed ids'
complete -c knap -l allowed-special -x \
    -d 'Permit this special token in the input'
complete -c knap -l strict-special -d 'Refuse any special token in the input'
complete -c knap -s h -l help -d 'Print the usage message'
complete -c knap -s V -l version -d 'Print the version'

# =============================================================================
# End of file: cli/completions/knap.fish
# =============================================================================
