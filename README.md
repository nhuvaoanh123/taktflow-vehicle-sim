# taktflow-vehicle-sim

GPU-accelerated 3D vehicle simulation with real vECU code. 3 cars, each driven by 4 real ECUs (CVC + RZC + FZC + SC) running in Docker.

## Architecture

```
┌───────────────────────┐        UDP (JSON)       ┌──────────────────────┐
│   Godot Engine (GPU)  │ ◄─────────────────────► │   Python Bridge      │
│                       │   sensor data (60 Hz)   │                      │
│  3× VehicleBody3D     │   actuator cmds (100Hz) │   CAN ↔ UDP relay    │
│  - suspension/tires   │                         │   E2E CRC-8 packing  │
│  - collision physics  │                         │   per-car vcan iface │
│  - 3D rendering       │                         │                      │
│  Dashboard HUD        │                         └──────────┬───────────┘
│  Camera system        │                                    │ SocketCAN
└───────────────────────┘                                    │
     RTX 4060                              ┌─────────────────┼─────────────────┐
                                           │                 │                 │
                                      vcan0 (Car 1)    vcan1 (Car 2)    vcan2 (Car 3)
                                      CVC  RZC         CVC  RZC         CVC  RZC
                                      FZC  SC          FZC  SC          FZC  SC
                                      (4 containers)   (4 containers)   (4 containers)
```

## Quick Start

### Mode 1: Standalone (no Docker, no CAN — just Godot)

1. Install [Godot 4.3+](https://godotengine.org/download)
2. Open `godot/project.godot` in Godot
3. Press F5 (Play)
4. Drive with WASD / arrow keys

Controls:
- **WASD / Arrows** — accelerate, brake, steer
- **Space** — emergency stop
- **C** — cycle camera (chase / top-down / cockpit)
- **Tab** — switch between cars
- **V** — toggle vECU mode (requires bridge)

### Mode 2: With vECU Docker containers (Linux / WSL2)

```bash
# 1. Create virtual CAN interfaces
sudo ./bridge/setup-vcan.sh

# 2. Build vECU Docker image (from taktflow-embedded repo)
docker build -t taktflow-vecu -f ../taktflow-embedded/docker/Dockerfile.vecu ../taktflow-embedded

# 3. Start 3 cars (12 containers)
cd bridge
docker compose --profile all up -d

# 4. Start the bridge
pip install -r requirements.txt
python bridge.py --cars 3

# 5. Open Godot, press F5, press V to enable vECU mode
```

### Mode 3: Split across machines (LAN)

```
Main PC (Linux):  Docker containers + bridge
Laptop (Windows): Godot rendering (GPU)
```

Edit `udp_client.gd` → change `BRIDGE_HOST` to the main PC's IP.

## Project Structure

```
godot/
├── project.godot              # Godot 4.3 project
├── scenes/main.tscn           # Main scene (builds everything in code)
└── scripts/
    ├── main.gd                # Scene builder: environment, track, 3 cars
    ├── vehicle_controller.gd  # Keyboard + vECU control, sensor data
    ├── camera_follow.gd       # Chase / top-down / cockpit camera
    ├── udp_client.gd          # UDP networking (autoload singleton)
    └── dashboard.gd           # HUD: speed, RPM, temp, ECU status

bridge/
├── bridge.py                  # CAN ↔ UDP relay (replaces plant_sim)
├── docker-compose.yml         # 3 cars × 4 vECUs = 12 containers
├── setup-vcan.sh              # Create vcan0, vcan1, vcan2
└── requirements.txt           # python-can, cantools

docs/
└── plan-vehicle-sim.md        # Full implementation plan with FMEA traceability
```

## CAN Protocol

Each car communicates via standard 11-bit CAN with E2E protection (CRC-8 SAE J1850):

| ID | Message | Direction | Content |
|----|---------|-----------|---------|
| 0x101 | Torque_Request | ECU → Bridge | Motor duty 0-100%, direction |
| 0x102 | Steer_Command | ECU → Bridge | Angle -45° to +45° |
| 0x103 | Brake_Command | ECU → Bridge | Force 0-100% |
| 0x300 | Motor_Status | Bridge → ECU | RPM, torque echo, direction |
| 0x200 | Steering_Status | Bridge → ECU | Actual angle, fault status |
| 0x600 | FZC_VSensors | Bridge → ECU | SPI steering, brake ADC |
| 0x601 | RZC_VSensors | Bridge → ECU | Current, temp, voltage, RPM |

## License

Apache-2.0
