# WebRTC & Twilio RTC Infrastructure Integration

This document provides a low-level network and protocol breakdown of how the Twilio Video SDK interacts with standard WebRTC protocols to establish secure real-time communication sessions.

---

## 1. WebRTC Protocol Mechanics: A Primer

WebRTC (Web Real-Time Communication) is a collection of open-source protocols designed to transmit media directly between browser or mobile peers with minimal latency. It relies on four primary mechanisms:

```
[ Mobile Client A ] <--- Signaling Handshake (SDP) ---> [ Twilio Signal Gateways ] <--- SDP ---> [ Mobile Client B ]
        │                                                                                              │
        ├─────────── STUN/TURN Discovery (ICE Candidates) ─────────────────────────────────────────────┤
        │                                                                                              │
        ▼                                                                                              ▼
[ Decrypted Media ] <────────────── Direct Secure Transport (SRTP) ──────────────────────────────> [ Decrypted Media ]
```

### Protocol Pipeline:
1. **Signaling:** The exchange of session metadata (capabilities, resolutions, connection profiles). In our app, this is coordinated by Twilio's signaling servers using WebSockets.
2. **SDP (Session Description Protocol) Exchange:** Both mobile endpoints generate cryptographic and audio/video capability descriptions (SDP offers/answers) outlining what formats they support (e.g., Opus for audio, VP8/H.264 for video).
3. **ICE (Interactive Connectivity Establishment):** Since mobile devices operate behind private router NATs (Network Address Translation) and firewalls, they cannot communicate directly using local IP addresses. ICE coordinates finding a valid public IP and port combination.
   - **STUN (Session Traversal Utilities for NAT):** Discovers the client's public-facing IP address and port.
   - **TURN (Traversal Using Relays around NAT):** If direct Peer-to-Peer packets are completely blocked by strict firewall policies, TURN servers act as encrypted data relays.
4. **Media Security (SRTP & DTLS):** Once the connection path is resolved, WebRTC performs a DTLS (Datagram Transport Layer Security) handshake to negotiate session encryption keys. Raw audio/video data packets are encrypted and transported securely via SRTP (Secure Real-time Transport Protocol).

---

## 2. Twilio Video Signaling Infrastructure

Rather than forcing developers to host and maintain their own signaling and STUN/TURN servers—which require complex scaling configurations—Twilio provides a centralized, geo-routing infrastructure.

When `Video.connect(context, connectOptions, listener)` is invoked in Kotlin:

1. **Gateway Authentication:** The client presents the signed Access Token (JWT) to Twilio's gateway.
2. **Topology Allocation:** Depending on your configuration, Twilio assigns:
   - **Peer-to-Peer Room:** Direct connection between two users. Twilio is only used for signaling and STUN/TURN routing.
   - **Group Room:** Relies on Twilio's centralized **SFU (Selective Forwarding Unit)**. Rather than sending individual streams to every single participant, each client publishes a *single* upstream media track to Twilio's servers, which then replicate and push downstream tracks to the other participants.
3. **Downstream Subscription:** By setting `enableAutomaticSubscription(true)`, the native SDK automatically establishes SRTP downlinks for any new participants discovered in the room.

---

## 3. Codec Profiling & Quality of Service (QoS)

Media transport operates over UDP to prioritize speed over reliability. This means packets can be dropped or arrive out of order during network congestion.

To preserve call quality, our Twilio integration implements several QoS and media negotiation controls:

- **Audio Track Profile:**
  Opus is negotiated as the primary audio codec. It features dynamic bitrate adjustments (from 6 kbps to 510 kbps) and built-in Forward Error Correction (FEC) to reconstruct lost audio packets dynamically.
- **Video Track Profile:**
  VP8 or H.264 is negotiated for video rendering. VP8 is optimized for software encoding and has excellent CPU scaling.
- **Bandwidth Constraints & Adaptability:**
  The native layer monitors network performance and quality levels continuously. If bandwidth degrades, the Twilio SFU gateway throttles the downstream video quality, preserving the audio track to prevent call drops.
