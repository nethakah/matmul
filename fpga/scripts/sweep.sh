#!/usr/bin/env bash

# sweep all 3 architectures across sizes
# run under Tmux

set -e
cd "$(dirname "$0")"

for n in 4 8 16 32 64; do
    for v in sequential systolic_reg systolic_bram; do
        echo "### $v N=$n ###"
        vivado -mode batch -nojournal -nolog -source run_ooc.tcl -tclargs "$v" "$n" || echo "FAILED: $v N=$n"
    done
done

cat ../results/*/summary.txt > ../results/all_summaries.txt
echo "=== sweep complete -> fpga/results/all_sumamaries.txt ==="