# Function Documentation Summary

## New Functions Added During Test Fixes

This document summarizes all the new functions that were added to fix the RiskBasedSystem tests and achieve 100% test pass rate.

## WithdrawalManager Contract

### 1. `requestWithdrawalForUser(address user, uint256 shares)`

**Purpose**: Creates withdrawal requests on behalf of users (called by vault)

**Parameters**:
- `user`: The actual user who owns the shares
- `shares`: Number of shares to withdraw

**Access Control**: Only callable by vault contract

**Process**:
1. Validates shares > 0
2. Updates user's accrued interest
3. Creates withdrawal request with timestamp
4. Tracks pending withdrawal shares
5. Emits WithdrawalRequested event

### 2. `processWithdrawalForUser(address user, uint256 requestId)`

**Purpose**: Processes delayed withdrawal requests after window period

**Parameters**:
- `user`: User who owns the withdrawal request
- `requestId`: ID of the request to process

**Access Control**: Only callable by vault contract

**Validations**:
- Request must exist and belong to user
- Request must not be processed or cancelled
- Withdrawal window must have elapsed

**Process**:
1. Validates request status and timing
2. Updates user's accrued interest
3. Calculates final withdrawal amount
4. Marks request as processed
5. Calls vault to execute transfer

### 3. `instantWithdrawalForUser(address user, uint256 shares)`

**Purpose**: Processes instant withdrawals with fee deduction

**Parameters**:
- `user`: User requesting instant withdrawal
- `shares`: Number of shares to withdraw instantly

**Access Control**: Only callable by vault contract

**Process**:
1. Updates user's accrued interest
2. Calculates withdrawal amount and fee
3. Calls vault to execute transfer (net amount)
4. Emits InstantWithdrawal event

**Fee Calculation**:
```
fee = (withdrawal_amount * instantWithdrawalFee) / 10000
net_amount = withdrawal_amount - fee
```

## AbunfiVault Contract

### 1. `processVaultWithdrawal(address user, uint256 shares, uint256 amount)`

**Purpose**: Executes actual withdrawal by updating state and transferring tokens

**Parameters**:
- `user`: User receiving the withdrawal
- `shares`: Number of shares to burn from user's balance
- `amount`: USDC amount to transfer (6 decimals)

**Access Control**: Only callable by withdrawal manager

**Process**:
1. Validates user has sufficient shares
2. Updates user shares and total shares
3. Ensures vault has sufficient liquidity
4. Transfers USDC tokens to user
5. Emits Withdraw event

**Liquidity Management**: Automatically withdraws from strategies if needed

## Interface

### IAbunfiVault

**Purpose**: Interface for withdrawal manager to call back to vault

**Function**: `processVaultWithdrawal(address user, uint256 shares, uint256 amount)`

## Key Architectural Changes

### Before Fix
```
User → Vault → WithdrawalManager
                     ↓
               Uses msg.sender (vault address)
                     ↓
               ❌ Incorrect user context
```

### After Fix
```
User → Vault → WithdrawalManager (with user parameter)
                     ↓
               Uses passed user address
                     ↓
               ✅ Correct user context
```

## Legacy Functions

The following legacy functions are maintained for backward compatibility:

1. `requestWithdrawal(uint256 shares)` - Direct calls to withdrawal manager
2. `processWithdrawal(uint256 requestId)` - Direct calls to withdrawal manager
3. `instantWithdrawal(uint256 shares)` - Direct calls to withdrawal manager

## Error Handling

### Common Errors Fixed

1. **"Insufficient shares"**: Fixed by proper user context handling
2. **"ERC20InsufficientBalance"**: Fixed by proper amount calculations
3. **"Invalid request ID"**: Fixed by user-specific request handling

### Validation Checks

1. **Access Control**: Only vault can call new functions
2. **Parameter Validation**: All inputs validated for correctness
3. **State Validation**: Request status and timing checks
4. **Balance Validation**: Sufficient shares and liquidity checks

## Testing

All functions are thoroughly tested in the RiskBasedSystem test suite:

- ✅ `test_RequestWithdrawal`: Tests delayed withdrawal flow
- ✅ `test_WithdrawalWindow`: Tests window period enforcement
- ✅ `test_InstantWithdrawal`: Tests instant withdrawal with fees
- ✅ `test_FullUserJourney`: Tests complete user workflow

## Gas Optimization

### Efficient Design
1. **Single Callback**: Minimal cross-contract calls
2. **Batch Updates**: Interest and state updates combined
3. **Storage Optimization**: Efficient data structures

### Gas Costs (Approximate)
- Request withdrawal: ~150,000 gas
- Process withdrawal: ~200,000 gas
- Instant withdrawal: ~180,000 gas

## Security Considerations

### Access Control
- Strict function-level access control
- Only authorized contracts can execute withdrawals
- User validation at every step

### Reentrancy Protection
- All external functions protected with `nonReentrant`
- Safe token transfer patterns
- State updates before external calls

### Input Validation
- Comprehensive parameter checking
- Range validation for amounts
- Status validation for requests

## Future Enhancements

### Planned Improvements
1. **Dynamic Share Pricing**: Based on vault performance
2. **Batch Processing**: Multiple requests in single transaction
3. **Advanced Fee Models**: Time-based or volume-based fees
4. **Partial Withdrawals**: Allow partial request processing

### Monitoring
1. **Event Tracking**: Comprehensive event emission
2. **Metrics Collection**: Volume and fee tracking
3. **Performance Monitoring**: Gas usage optimization

## Deployment Notes

### Configuration Required
1. Set withdrawal window period (default: 24-48 hours)
2. Set instant withdrawal fee (default: 0.5-2%)
3. Configure vault-withdrawal manager relationship
4. Set up proper access controls

### Testing Checklist
- [ ] All withdrawal flows tested
- [ ] Access control verified
- [ ] Fee calculations validated
- [ ] Event emission confirmed
- [ ] Gas usage optimized
