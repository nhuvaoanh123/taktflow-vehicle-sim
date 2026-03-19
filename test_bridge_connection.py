#!/usr/bin/env python3
"""
Quick test: simulate Godot sending sensor data to Pi bridge, receive actuator commands back.
Run on Windows PC to verify UDP path to Pi godot-bridge container.

Usage:
    python test_bridge_connection.py
    python test_bridge_connection.py --bridge-ip 192.168.0.195
"""

import argparse
import json
import socket
import time
import sys

def main():
    parser = argparse.ArgumentParser(description="Test Godot↔Bridge UDP connection")
    parser.add_argument("--bridge-ip", default="192.168.0.195", help="Pi IP (bridge host)")
    args = parser.parse_args()

    BRIDGE_IP = args.bridge_ip
    SEND_PORT = 5001   # sensor data TO bridge
    RECV_PORT = 5002   # actuator commands FROM bridge

    # Send socket (sensor data → bridge)
    send_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    # Receive socket (actuator commands ← bridge)
    recv_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    recv_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    recv_sock.bind(("0.0.0.0", RECV_PORT))
    recv_sock.settimeout(1.0)

    print(f"[test] Sending sensor data to {BRIDGE_IP}:{SEND_PORT}")
    print(f"[test] Listening for actuator commands on :{RECV_PORT}")
    print(f"[test] Press Ctrl+C to stop\n")

    # Fake sensor data (idle car, center steering)
    sensor_data = {
        "car_index": 0,
        "vehicle_speed_kmh": 0.0,
        "motor_rpm": 0,
        "motor_current_a": 0.0,
        "motor_temp_c": 25.0,
        "battery_voltage_v": 12.6,
        "steer_angle_deg": 0.0,
        "lidar_distance_m": 12.0,
        "pedal_pct": 0.0,
        "steer_input_deg": 0.0,
        "brake_input_pct": 0.0,
        "estop_input": False,
    }

    tx_count = 0
    rx_count = 0

    try:
        while True:
            # Send sensor data (like Godot does at 60Hz)
            payload = json.dumps(sensor_data).encode("utf-8")
            send_sock.sendto(payload, (BRIDGE_IP, SEND_PORT))
            tx_count += 1

            # Try to receive actuator commands
            try:
                data, addr = recv_sock.recvfrom(4096)
                actuator = json.loads(data.decode("utf-8"))
                rx_count += 1
                state = actuator.get("vehicle_state", "?")
                torque = actuator.get("motor_torque_pct", 0)
                steer = actuator.get("steer_cmd_deg", 0)
                brake = actuator.get("brake_force_pct", 0)
                estop = actuator.get("estop", False)
                kill = actuator.get("kill_relay", False)
                hb = actuator.get("ecu_heartbeats", {})
                print(f"[RX #{rx_count}] state={state} torque={torque:.1f}% steer={steer:.1f}° brake={brake:.1f}% estop={estop} kill={kill} HB={hb}")
            except socket.timeout:
                print(f"[test] TX={tx_count} — no response from bridge (timeout)")

            time.sleep(0.1)  # 10 Hz for testing (Godot does 60 Hz)

    except KeyboardInterrupt:
        print(f"\n[test] Done. TX={tx_count} RX={rx_count}")
    finally:
        send_sock.close()
        recv_sock.close()

if __name__ == "__main__":
    main()
