# Sorites

This repository contains the smart contracts for the Sorites protocol: a fixed yield wrapper for a variable yield protocols 💰🔒⏰.

## Contracts

### Sorites Core

This contract is the central managing contract of the protocol. It is used to perform certain tasks, e.g. deploy new Sorites pools for a supported protocol, and as central source of information.

### Sorites Pools

Each variable yield earning protocol that protocol that Sorites wraps has an associated fixed yield liquidity pool. These can be located in the `src/pools` directory. Users provide the relevant liquidity into these pools and are guaranteed a fixed return. This return is calculated at deposit-time based on the current state of the protocol.
