#!/bin/bash
# Create virtual CAN interfaces for 3 cars
# Run with: sudo ./setup-vcan.sh

set -e

modprobe vcan

for i in 0 1 2; do
    ip link add dev vcan${i} type vcan 2>/dev/null || true
    ip link set up vcan${i}
    echo "vcan${i} ready"
done

echo "All virtual CAN interfaces created."
