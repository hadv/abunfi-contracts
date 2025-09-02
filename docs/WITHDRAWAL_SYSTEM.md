# Withdrawal System Documentation

## Overview

The Abunfi withdrawal system implements a secure, two-phase withdrawal mechanism that balances user convenience with vault liquidity management. The system consists of two main components: `AbunfiVault` and `WithdrawalManager`.

## Architecture

### Component Interaction Flow

```
User → AbunfiVault → WithdrawalManager → AbunfiVault
  ↓         ↓              ↓               ↓
Request → Validate → Process Logic → Execute Transfer
```

### Key Components

1. **AbunfiVault**: User-facing interface for withdrawal requests
2. **WithdrawalManager**: Business logic for withdrawal processing
3. **IAbunfiVault**: Interface for callback communication

## Withdrawal Types

### 1. Delayed Withdrawal (Recommended)

**Process:**
1. User calls `vault.requestWithdrawal(shares)`
2. System creates withdrawal request with timestamp
3. User waits for withdrawal window period (typically 24-48 hours)
4. User calls `vault.processWithdrawal(requestId)` to complete

**Benefits:**
- No fees charged
- Helps vault manage liquidity
- Prevents bank run scenarios

**Use Cases:**
- Regular fund withdrawals
- Planned liquidity needs
- Cost-conscious users

### 2. Instant Withdrawal

**Process:**
1. User calls `vault.instantWithdrawal(shares)`
2. System immediately processes withdrawal with fee deduction
3. User receives net amount (withdrawal - fee)

**Trade-offs:**
- Immediate access to funds
- Fee charged (typically 0.5-2%)
- May impact vault liquidity

**Use Cases:**
- Emergency fund access
- Time-sensitive opportunities
- Convenience over cost

## Technical Implementation

### New Functions Added

#### WithdrawalManager

1. **`requestWithdrawalForUser(address user, uint256 shares)`**
   - Called by vault to create withdrawal requests
   - Handles user context properly
   - Updates interest and creates request

2. **`processWithdrawalForUser(address user, uint256 requestId)`**
   - Processes delayed withdrawals after window period
   - Validates timing and request status
   - Calls back to vault for execution

3. **`instantWithdrawalForUser(address user, uint256 shares)`**
   - Processes instant withdrawals with fee calculation
   - Immediate execution without waiting period
   - Fee deduction and transfer

#### AbunfiVault

1. **`processVaultWithdrawal(address user, uint256 shares, uint256 amount)`**
   - Callback function for withdrawal execution
   - Updates user shares and total shares
   - Ensures liquidity and transfers tokens
   - Only callable by withdrawal manager

### Security Features

1. **Access Control**: Only withdrawal manager can call vault's withdrawal execution
2. **Reentrancy Protection**: All external functions protected
3. **Input Validation**: Comprehensive parameter checking
4. **Interest Updates**: Automatic interest accrual before processing

### Gas Optimization

1. **Batch Processing**: Support for multiple withdrawal requests
2. **Efficient Storage**: Optimized data structures
3. **Minimal External Calls**: Reduced cross-contract communication

## Configuration

### Withdrawal Window
- Default: 24-48 hours
- Configurable by admin
- Prevents immediate large withdrawals

### Instant Withdrawal Fee
- Default: 0.5-2% of withdrawal amount
- Configurable by admin
- Revenue for protocol

## Error Handling

### Common Errors

1. **"Insufficient shares"**: User doesn't have enough shares
2. **"Withdrawal window not met"**: Trying to process before waiting period
3. **"Invalid request ID"**: Request doesn't exist or wrong user
4. **"Only vault can call"**: Unauthorized access to internal functions

### Recovery Mechanisms

1. **Request Cancellation**: Users can cancel pending requests
2. **Emergency Withdrawal**: Admin emergency functions
3. **Liquidity Management**: Automatic strategy withdrawals

## Usage Examples

### Delayed Withdrawal

```solidity
// Step 1: Request withdrawal
uint256 requestId = vault.requestWithdrawal(1000e18); // 1000 shares

// Step 2: Wait for withdrawal window (24-48 hours)
// ...

// Step 3: Process withdrawal
vault.processWithdrawal(requestId);
```

### Instant Withdrawal

```solidity
// Single step: Instant withdrawal with fee
vault.instantWithdrawal(500e18); // 500 shares, fee deducted
```

## Monitoring and Events

### Key Events

1. **WithdrawalRequested**: New withdrawal request created
2. **WithdrawalProcessed**: Delayed withdrawal completed
3. **InstantWithdrawal**: Instant withdrawal completed
4. **InterestAccrued**: Interest updated for user

### Metrics to Track

1. Total withdrawal volume
2. Instant vs delayed withdrawal ratio
3. Average withdrawal window wait time
4. Fee revenue from instant withdrawals

## Best Practices

### For Users

1. Use delayed withdrawals for planned liquidity needs
2. Use instant withdrawals only when necessary
3. Monitor withdrawal windows and plan accordingly
4. Check gas costs before processing

### For Developers

1. Always update tests when modifying withdrawal logic
2. Validate user permissions before processing
3. Handle edge cases (zero amounts, invalid requests)
4. Monitor vault liquidity levels

## Future Enhancements

1. **Dynamic Pricing**: Share value based on vault performance
2. **Batch Processing**: Multiple requests in single transaction
3. **Partial Withdrawals**: Allow partial processing of requests
4. **Advanced Fee Models**: Time-based or volume-based fees
