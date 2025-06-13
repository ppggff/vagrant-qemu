#!/bin/bash

# Gather NUMA information
numactl --hardware | awk '/node [0-9]+ cpus:/ {node=$2; for (i=4; i<=NF; i++) print $i, node}' > /tmp/numa_info.txt
