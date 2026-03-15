# Plan: Godot Vehicle Simulation for vECU Validation

**Date**: 2026-03-15
**Status**: Draft
**Goal**: GPU-accelerated 3D multi-car vehicle simulation driven by real vECU code, covering all FMEA/HARA/SIL scenarios

---

## 0. Multi-Car Architecture

### 0.1 Fleet: 3 Ego Vehicles, Each with 4 vECUs

| ECU | Role | Why needed |
|---|---|---|
| **CVC** | Central Vehicle Controller — pedal → commands | Brain |
| **RZC** | Rear Zone Controller — motor torque, overcurrent/overtemp | Muscles |
| **FZC** | Front Zone Controller — steering, braking, distance sensor | Steering + braking + perception |
| **SC** | Safety Controller — watchdog, kill relay, heartbeat | Safety net |

**Not included** (simulated by Godot instead):
- BMS → Godot provides a voltage/SOC curve per car
- BCM → headlights/wipers rendered directly by Godot
- GW → telemetry shown in dashboard overlay

### 0.2 Resource Budget

| Resource | Per car | 3 cars | Available |
|---|---|---|---|
| Docker containers | 4 | **12** | — |
| RAM | ~1.5 GB | ~4.5 GB | 16 GB |
| CPU threads | ~3 | ~9 | 16 |
| GPU | 0 | 0 | RTX 4060 (all for Godot) |

### 0.3 Network Topology

Each car gets its own UDP port pair and isolated CAN bus namespace:

```
Godot (GPU)
  ├── Car 1: UDP :5001/:5002 ↔ Bridge ↔ [CVC-1, RZC-1, FZC-1, SC-1]
  ├── Car 2: UDP :5003/:5004 ↔ Bridge ↔ [CVC-2, RZC-2, FZC-2, SC-2]
  └── Car 3: UDP :5005/:5006 ↔ Bridge ↔ [CVC-3, RZC-3, FZC-3, SC-3]
```

### 0.4 Traffic + Collision

- 3 ego cars with full vECU stacks (real ECU code)
- N additional AI traffic cars (scripted waypoint followers, no Docker)
- Godot physics handles collision between all cars natively
- Collision force → accelerometer sensor → vECU impact detection → SC triggers SS-SYSTEM-SHUTDOWN

### 0.5 Multi-Car Test Scenarios

| Scenario | Cars Involved | What's Tested |
|---|---|---|
| Lead car brakes hard | Car 1 (lead) + Car 2 (follow) | ABS (SG-004), distance sensor (SG-007), FTTI 50ms |
| Side cut-in | Car 1 + Car 3 | Emergency steer + brake, compound fault |
| Rear-end collision | Car 2 rear-ends Car 1 | Impact detection → E-Stop → SS-SYSTEM-SHUTDOWN |
| Intersection conflict | Car 1 + Car 2 at crossing | Right-of-way, collision avoidance |
| Convoy (all 3) | Car 1 → Car 2 → Car 3 | Cascading brake reaction, E2E latency through fleet |
| Multi-car pileup | All 3 + AI traffic | Compound faults, multiple SC triggering simultaneously |

### 0.6 Streaming Architecture

```
Main PC (optional)           Laptop (RTX 4060)              Cloud
┌──────────────────┐         ┌───────────────────┐          ┌──────────────┐
│ 12 Docker vECUs  │──UDP──►│ Godot render      │──NVENC──►│ WebRTC relay │──► Browser
│ if RAM needed    │◄──UDP──│ + physics (GPU)   │          │              │
└──────────────────┘         └───────────────────┘          └──────────────┘
     LAN 192.168.0.x              192.168.0.158          sim.taktflow-systems.com
```

- NVENC hardware encode: ~1% GPU overhead
- Viewer can inject faults via web UI (WebRTC data channel)
- All 3 cars visible simultaneously with camera switching

---

## 1. Vehicle Physics Model (Godot VehicleBody3D)

### 1.1 Base Vehicle
- 4-wheel VehicleBody3D with configurable mass, wheelbase, track width
- Suspension: spring rate, damping, travel per wheel
- Tire model: simplified Pacejka (lateral + longitudinal slip)
- Drivetrain: rear-wheel drive (matching our RZC motor controller)
- Steering: front axle, rack-and-pinion geometry

### 1.2 Actuator Mapping (vECU → Godot Physics)
| vECU Output | Godot Physics Input |
|---|---|
| Motor PWM duty (0–100%) | Engine torque applied to rear wheels |
| Brake force (0–100%) | Per-wheel brake torque |
| Steering angle (°) | Front wheel steer angle |
| Kill relay signal | All torques → 0, brakes → max |

### 1.3 Sensor Simulation (Godot → vECU)
| Godot Physics Output | vECU Input |
|---|---|
| Wheel RPM (per wheel) | Wheel speed sensors → CVC |
| Vehicle speed (km/h) | Speedometer signal |
| Steering angle (°) | Steering encoder → FZC |
| Motor current (derived from torque) | Current sensor → RZC |
| Motor temperature (thermal model) | Temp sensor → RZC |
| Battery voltage (load model) | Voltage ADC → all ECUs |
| Distance to obstacle (raycast) | Ultrasonic/LiDAR → FZC |
| Pedal position (user input) | Pedal ADC → CVC |

---

## 2. Road Environment

### 2.1 Track Layout
- Closed test track (oval + technical section)
- Straight sections for acceleration/braking tests
- Curves for steering tests
- Obstacle zone for distance sensor tests
- Gradient section (uphill/downhill) for load tests

### 2.2 Road Surface
- Dry asphalt (baseline friction μ = 1.0)
- Wet section (reduced friction μ = 0.5) — tests ABS logic
- Gravel patch (μ = 0.3) — tests traction control

### 2.3 Environmental
- Day/night cycle (headlight test for body control)
- Rain effect (wiper test for body control)

---

## 3. Fault Injection System

All faults injectable via a Godot UI panel or automated test script.

### 3.1 Sensor Faults (from HARA MB-001 to MB-027)

| Fault ID | Scenario | Godot Implementation | Safety Goal | FTTI |
|---|---|---|---|---|
| F-PED-01 | Both pedal sensors read high | Override pedal ADC → 100% | SG-001 | 50 ms |
| F-PED-02 | Both pedal sensors read low | Override pedal ADC → 0% | SG-002 | 200 ms |
| F-PED-03 | Pedal sensor disagreement | Send split values (ADC1=80%, ADC2=10%) | SG-001 | 50 ms |
| F-STR-01 | Steering sensor oscillation | Inject ±40° at 200°/s (SIL-008) | SG-003 | 100 ms |
| F-STR-02 | Steering sensor complete failure | Freeze steer value → NaN or 0 (SIL-011) | SG-003 | 100 ms |
| F-DST-01 | Distance sensor false negative | Override distance → 999 m (no obstacle) | SG-007 | 200 ms |
| F-DST-02 | Distance sensor false positive | Override distance → 0.1 m | SG-007 | 200 ms |
| F-DST-03 | Distance sensor stuck | Freeze last distance value | SG-007 | 200 ms |

### 3.2 Actuator Faults

| Fault ID | Scenario | Godot Implementation | Safety Goal | FTTI |
|---|---|---|---|---|
| F-MOT-01 | Motor stuck at full power | Ignore vECU motor command, apply 100% torque | SG-001 | 50 ms |
| F-MOT-02 | Motor unresponsive | Ignore vECU motor command, apply 0% torque | SG-002 | 200 ms |
| F-MOT-03 | Motor direction reversal | Negate torque direction | SG-001 | 50 ms |
| F-MOT-04 | Motor overcurrent | Set current sensor → 150% rated (SIL-007) | SG-006 | 500 ms |
| F-MOT-05 | Motor overtemperature | Ramp temp sensor → 120°C (SIL-010) | SG-006 | 500 ms |
| F-BRK-01 | Loss of braking | Ignore brake command, 0% brake force | SG-004 | 50 ms |
| F-BRK-02 | Unintended braking | Override brake → 100% regardless of command | SG-005 | 200 ms |
| F-BRK-03 | Insufficient brake force | Scale brake command to 20% | SG-004 | 50 ms |

### 3.3 Network Faults

| Fault ID | Scenario | Godot Implementation | Safety Goal | FTTI |
|---|---|---|---|---|
| F-CAN-01 | CAN bus-off (SIL-004) | Drop all messages from one ECU | SG-008 | 100 ms |
| F-CAN-02 | CRC corruption (SIL-009) | Flip bits in E2E CRC field | SG-008 | 100 ms |
| F-CAN-03 | Babbling node | Flood bus with invalid messages | SG-008 | 100 ms |
| F-CAN-04 | Sequence counter gap | Skip N messages in counter | SG-008 | 100 ms |

### 3.4 System Faults

| Fault ID | Scenario | Godot Implementation | Safety Goal | FTTI |
|---|---|---|---|---|
| F-SYS-01 | CVC watchdog timeout (SIL-005) | Kill CVC container | SG-008 | 500 ms |
| F-SYS-02 | Battery undervoltage (SIL-006) | Ramp battery voltage → 8V | SG-008 | 100 ms |
| F-SYS-03 | E-Stop pressed (SIL-003) | Send E-Stop signal | All | immediate |
| F-SYS-04 | Power cycle (SIL-015) | Restart all vECU containers | All | — |

### 3.5 Compound Faults

| Fault ID | Scenario | Godot Implementation | SIL Ref |
|---|---|---|---|
| F-CMP-01 | Overcurrent + steering fault (SIL-012) | F-MOT-04 + F-STR-01 simultaneously | SIL-012 |
| F-CMP-02 | Steer fault + E-Stop escalation (SIL-011) | F-STR-02 then F-SYS-03 if no response | SIL-011 |

---

## 4. Safe State Verification

The simulation must visually confirm these safe states:

| Safe State | Visual Indicator | Verification |
|---|---|---|
| SS-MOTOR-OFF | Car decelerates to stop, motor sound off, brake lights on | Speed → 0 within expected time |
| SS-CONTROLLED-STOP | Car gradually slows, steering locked, hazard lights | Smooth decel profile, no jerk |
| SS-SYSTEM-SHUTDOWN | All lights flash, car stops immediately, "SHUTDOWN" overlay | Kill relay activated, all actuators off |

### FTTI Verification
- On-screen timer starts when fault is injected
- Timer stops when safe state is reached
- **Red** if FTTI exceeded, **green** if within budget
- All timings logged to CSV for evidence

---

## 5. UDP Bridge Protocol

### 5.1 Sensor Frame (Godot → vECU, 60 Hz)
```
{
  "timestamp_ms": uint64,
  "pedal_pct": float32,        // 0.0–1.0
  "brake_pedal_pct": float32,  // 0.0–1.0
  "steer_angle_deg": float32,  // -45.0 to +45.0
  "wheel_rpm": [float32; 4],   // FL, FR, RL, RR
  "vehicle_speed_kmh": float32,
  "motor_current_a": float32,
  "motor_temp_c": float32,
  "battery_voltage_v": float32,
  "obstacle_distance_m": float32,
  "estop_pressed": bool
}
```

### 5.2 Actuator Frame (vECU → Godot, 60 Hz)
```
{
  "timestamp_ms": uint64,
  "motor_torque_pct": float32,   // -1.0 to 1.0 (negative = reverse)
  "brake_force_pct": [float32; 4], // per-wheel
  "steer_cmd_deg": float32,
  "kill_relay": bool,
  "headlights": bool,
  "wipers": bool,
  "hazard_lights": bool,
  "dtc_active": [uint32]          // active DTC codes
}
```

### 5.3 Fault Injection Frame (Godot UI → Bridge, on demand)
```
{
  "fault_id": string,    // e.g. "F-MOT-01"
  "active": bool,
  "params": {}           // fault-specific overrides
}
```

---

## 6. Dashboard Overlay (HUD)

Rendered in Godot as 2D overlay on the 3D view:

- **Speedometer** — current speed from physics
- **Tachometer** — motor RPM
- **Battery gauge** — voltage + SOC
- **Motor temp gauge** — with red zone
- **ECU status grid** — 7 boxes (CVC, RZC, FZC, BMS, BCM, GW, SC), green/yellow/red
- **DTC panel** — active fault codes with descriptions
- **Safe state indicator** — current state (RUN / DEGRADED / SAFE_STOP / SHUTDOWN)
- **FTTI timer** — starts on fault injection, shows elapsed time
- **CAN bus activity** — scrolling message log

---

## 7. Implementation Phases

### Phase 1: Static Vehicle + Bridge (Week 1–2)
- [ ] Godot project setup with VehicleBody3D
- [ ] Simple test track (flat oval)
- [ ] UDP bridge (Godot GDScript ↔ Python relay ↔ Docker vECU)
- [ ] Keyboard controls for pedal/brake/steer (bypass vECU for testing)
- [ ] Verify physics: car drives, steers, brakes

### Phase 2: vECU Integration (Week 3–4)
- [ ] Connect bridge to existing Docker SIL containers
- [ ] Map sensor frame → CAN signals (reuse existing DBC)
- [ ] Map CAN actuator signals → actuator frame
- [ ] Car driven by real vECU code
- [ ] Basic dashboard overlay (speed, RPM, state)

### Phase 3: Fault Injection + Safe States (Week 5–6)
- [ ] Fault injection UI panel (dropdown + activate button)
- [ ] Implement all F-PED, F-STR, F-DST faults
- [ ] Implement all F-MOT, F-BRK faults
- [ ] Implement F-CAN, F-SYS faults
- [ ] Safe state visual feedback (SS-MOTOR-OFF, SS-CONTROLLED-STOP, SS-SYSTEM-SHUTDOWN)
- [ ] FTTI timer with pass/fail indicator

### Phase 4: Evidence + Polish (Week 7–8)
- [ ] FTTI logging to CSV (fault → safe state timing evidence)
- [ ] Compound fault scenarios (F-CMP-01, F-CMP-02)
- [ ] Track improvements (wet section, gradient, obstacles)
- [ ] Camera modes (follow, cockpit, top-down)
- [ ] DTC panel, CAN bus activity log
- [ ] Screen recording automation for portfolio

### Phase 5: Web Export (Optional)
- [ ] Export to WebGL for portfolio site integration
- [ ] Lightweight mode (reduced physics, pre-recorded vECU data)
- [ ] Interactive demo at sim.taktflow-systems.com

---

## 8. File Structure

```
taktflow-vehicle-sim/
├── godot/
│   ├── project.godot
│   ├── scenes/
│   │   ├── main.tscn          — main scene
│   │   ├── vehicle.tscn       — VehicleBody3D + wheels
│   │   ├── track.tscn         — test track environment
│   │   ├── dashboard.tscn     — 2D HUD overlay
│   │   └── fault_panel.tscn   — fault injection UI
│   ├── scripts/
│   │   ├── vehicle_controller.gd  — receives actuator commands
│   │   ├── sensor_emitter.gd      — sends sensor data
│   │   ├── fault_injector.gd      — fault injection logic
│   │   ├── dashboard.gd           — HUD update logic
│   │   ├── udp_client.gd          — UDP socket handling
│   │   └── ftti_timer.gd          — fault timing measurement
│   └── assets/
│       ├── car/                — 3D car model
│       ├── track/              — track textures/meshes
│       └── ui/                 — dashboard icons
├── bridge/
│   ├── bridge.py              — UDP relay: Godot ↔ Docker vECU
│   ├── can_mapping.py         — DBC signal ↔ JSON field mapping
│   ├── fault_controller.py    — fault injection state machine
│   └── docker-compose.yml     — vECU container orchestration
├── docs/
│   ├── plan-vehicle-sim.md    — this file
│   └── fault-matrix.md        — fault ID ↔ SIL ↔ HARA traceability
├── evidence/
│   └── ftti_logs/             — CSV timing evidence per scenario
├── .gitignore
├── LICENSE
└── README.md
```

---

## 9. Traceability: Fault ID → SIL → Safety Goal → HARA

| Fault ID | SIL Scenario | Safety Goal | HARA MB | ASIL |
|---|---|---|---|---|
| F-PED-01 | SIL-002 | SG-001 | MB-001 | D |
| F-PED-02 | SIL-002 | SG-002 | MB-002 | B |
| F-PED-03 | SIL-002 | SG-001 | MB-003 | D |
| F-STR-01 | SIL-008 | SG-003 | MB-013 | D |
| F-STR-02 | SIL-011 | SG-003 | MB-014 | D |
| F-DST-01 | — | SG-007 | MB-017 | C |
| F-DST-02 | — | SG-007 | MB-018 | C |
| F-MOT-01 | — | SG-001 | MB-006 | D |
| F-MOT-02 | — | SG-002 | MB-008 | B |
| F-MOT-03 | — | SG-001 | MB-009 | D |
| F-MOT-04 | SIL-007 | SG-006 | MB-007 | A |
| F-MOT-05 | SIL-010 | SG-006 | MB-007 | A |
| F-BRK-01 | — | SG-004 | MB-015 | D |
| F-BRK-02 | — | SG-005 | MB-016 | A |
| F-CAN-01 | SIL-004 | SG-008 | MB-021 | C |
| F-CAN-02 | SIL-009 | SG-008 | MB-022 | C |
| F-SYS-01 | SIL-005 | SG-008 | MB-019 | C |
| F-SYS-02 | SIL-006 | SG-008 | MB-024 | C |
| F-SYS-03 | SIL-003 | All | MB-020 | D |
| F-CMP-01 | SIL-012 | SG-001+SG-003 | MB-007+MB-013 | D |
| F-CMP-02 | SIL-011 | SG-003 | MB-014+MB-020 | D |

---

## 10. Dependencies

| Component | Version | License | Purpose |
|---|---|---|---|
| Godot Engine | 4.3+ | MIT | Physics + rendering |
| Python 3.12 | — | PSF | UDP bridge |
| Docker | — | Apache-2.0 | vECU containers |
| Existing SIL containers | — | proprietary | Real ECU code (CVC, RZC, FZC, SC × 3 cars = 12) |

---

## 11. Open Questions

1. **Car 3D model** — use a free model from Sketchfab/OpenGameArt, or build a simple box car?
2. **Web export** — Godot WebGL + WebSocket bridge to hosted Docker vECUs? Feasibility TBD.
3. **Performance target** — 60 Hz physics + 60 fps rendering on RTX 4060 should be easy for a single car.
4. **Audio** — engine sound mapped to RPM? Nice-to-have for demos.
