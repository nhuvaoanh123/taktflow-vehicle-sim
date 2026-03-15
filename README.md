# taktflow-vehicle-sim

GPU-accelerated vehicle simulation powered by Godot Engine, driven by real vECU code.

## Architecture

```
┌──────────────────────┐         UDP          ┌──────────────────────┐
│   Godot Engine (GPU) │ ◄──────────────────► │  vECU Docker (CPU)   │
│                      │                      │                      │
│  VehicleBody3D       │  sensor data ──►     │  Motor Controller    │
│  - suspension        │                      │  Brake Controller    │
│  - tire friction     │  ◄── actuator cmds   │  Steering ECU        │
│  - collision         │                      │  BMS                 │
│  3D rendering        │  ◄── dashboard data  │  Body Control        │
│  Sensor simulation   │                      │  Gateway             │
│  Dashboard overlay   │                      │  Telemetry           │
└──────────────────────┘                      └──────────────────────┘
```

## How it works

1. **Godot** simulates car physics (VehicleBody3D) and 3D environment at 60 Hz
2. **UDP bridge** sends sensor data (speed, wheel RPM, temperatures, pedal positions) to vECUs
3. **vECUs** (real embedded C code in Docker) process inputs and produce actuator commands
4. **Actuator commands** (throttle %, brake force, steering angle) feed back into Godot physics
5. **Dashboard overlay** shows real-time ECU state, CAN bus traffic, fault codes

## Stack

- **Engine**: Godot 4.x (MIT license)
- **Physics**: VehicleBody3D — suspension, tire model, drivetrain
- **Bridge**: UDP socket (JSON or binary protocol)
- **vECUs**: Docker containers running real STM32 firmware compiled for x86
- **GPU**: RTX 4060 — physics + rendering

## Project structure

```
godot/          — Godot project (scenes, scripts, assets)
bridge/         — UDP bridge between Godot and vECU containers
docs/           — Design documents and plans
```

## License

Apache-2.0
