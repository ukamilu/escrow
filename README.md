# STX Escrow Smart Contract

A Clarity smart contract implementing secure STX token escrow with dispute resolution.

## Features
- Create escrow with buyer, seller and arbitrator
- Release funds to seller (by buyer or arbitrator)
- Dispute handling system
- Resolution mechanism for disputed transactions
- Read-only query functions

## Core Functions

### State-Changing Operations
- `create-escrow`: Create new escrow with STX deposit
- `release`: Release funds to seller
- `dispute`: Raise dispute on active escrow
- `resolve-dispute`: Resolve dispute and release funds

### Read-Only Functions
- `get-escrow`: Get full escrow details
- `get-escrow-state`: Get escrow state
- `get-escrow-amount`: Get escrow amount

## Security Features
- Input validation for all parameters
- Principal validation to prevent self-transactions
- Amount limits (1-1000 STX)
- State transition controls
- Authorization checks for all operations

## Constants
- Minimum amount: 1 STX
- Maximum amount: 1000 STX
- Maximum escrow ID: 999,999,999

## Error Codes
- `ERR-NOT-FOUND` (u1)
- `ERR-ALREADY-EXISTS` (u2)
- `ERR-INVALID-STATE` (u3)
- `ERR-UNAUTHORIZED` (u4)
- `ERR-INVALID-AMOUNT` (u5)
- `ERR-INVALID-PRINCIPAL` (u6)
- `ERR-INVALID-ID` (u7)

## States
- `0`: Funded
- `1`: Released
- `2`: Disputed

## Requirements
- Stacks blockchain
- Clarity smart contract support
