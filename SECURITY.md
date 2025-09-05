# Security Policy

## Overview

This document outlines the security practices and policies for the Abunfi smart contracts project.

## Scope

### Production Code (Security Critical)
- `src/**` - Smart contracts and core logic
- Main branch deployments
- Production configurations

### Demo/Test Code (Educational Only)
- `examples/**` - Demonstration and educational code
- `test/**` - Test files and fixtures
- `docs/**` - Documentation and guides
- `risc0-social-verifier/**` - RISC Zero components
- `scripts/**` - Development and deployment scripts

## Security Scanning Configuration

### CodeQL Analysis
We use GitHub's CodeQL for security analysis with the following configuration:

#### Included Paths
- `src/**` - Production smart contracts only

#### Excluded Paths
- `examples/**` - Demo code (not production)
- `test/**` - Test files
- `docs/**` - Documentation
- `scripts/**` - Development scripts
- `risc0-social-verifier/**` - RISC Zero components

#### Suppressed Alerts
The following CodeQL alerts are suppressed for demo/test code:

1. **js/code-injection**: Demo files use `require()` with static strings only
2. **js/unsafe-dynamic-method-access**: Demo files are not production code
3. **js/shell-command-injection-from-environment**: Demo files don't execute shell commands

### Rationale for Exclusions

#### Demo Code (`examples/token-management-demo/demo.js`)
- **Purpose**: Educational demonstration of token management concepts
- **Usage**: `require('crypto')` - Node.js built-in module only
- **Risk Level**: Low - No user input, no network access, no dynamic execution
- **Justification**: Demo code is not deployed to production and uses only safe built-in modules

#### Test Files (`test/**`)
- **Purpose**: Unit and integration testing
- **Usage**: Foundry test framework and mock data
- **Risk Level**: Low - Test environment only
- **Justification**: Test files are not deployed and contain only test fixtures

## Security Best Practices

### For Production Code (`src/**`)
1. ✅ **Full security scanning** enabled
2. ✅ **Formal verification** where applicable
3. ✅ **Access control** patterns implemented
4. ✅ **Input validation** on all external calls
5. ✅ **Reentrancy protection** where needed
6. ✅ **Gas optimization** without compromising security

### For Demo Code (`examples/**`)
1. ✅ **Static imports only** - No dynamic `require()`
2. ✅ **Built-in modules only** - No external dependencies
3. ✅ **No user input** - Hardcoded test data only
4. ✅ **No network access** - Local execution only
5. ✅ **Clear documentation** - Purpose and limitations explained
6. ✅ **Separate from production** - Clear isolation

### For Test Code (`test/**`)
1. ✅ **Isolated environment** - No production data
2. ✅ **Mock data only** - No real credentials
3. ✅ **Deterministic behavior** - Reproducible results
4. ✅ **No external dependencies** - Self-contained tests

## Reporting Security Issues

### For Production Code Issues
If you discover a security vulnerability in production code (`src/**`):

1. **DO NOT** create a public issue
2. **Email**: security@abunfi.com (if available) or create a private security advisory
3. **Include**: Detailed description, reproduction steps, potential impact
4. **Response**: We will respond within 48 hours

### For Demo/Test Code Issues
If you find issues in demo or test code:

1. **Create a public issue** with label "security" and "demo"
2. **Describe**: The issue and potential improvements
3. **Note**: These are not security vulnerabilities as they're not production code

## Security Scanning Results

### Current Status
- ✅ **Production code**: Clean security scan
- ⚠️ **Demo code**: Excluded from scanning (by design)
- ✅ **Dependencies**: Regularly audited

### False Positives
The following are known false positives that are safely excluded:

1. **Demo `require()` usage**: Uses only Node.js built-in modules
2. **Test file patterns**: Standard testing patterns, not production code
3. **Development scripts**: Local development tools only

## Compliance

### Standards
- **EIP-7702**: Smart account implementation
- **ERC-4337**: Account abstraction
- **RISC Zero**: Zero-knowledge proof verification
- **Solidity**: Latest stable version with security best practices

### Audits
- **Smart contracts**: Planned professional audit before mainnet
- **RISC Zero components**: Verified against RISC Zero security guidelines
- **Dependencies**: Regular dependency scanning and updates

## Contact

For security-related questions or concerns:
- **General**: Create a GitHub issue with "security" label
- **Vulnerabilities**: Use GitHub Security Advisories
- **Questions**: Discussion in GitHub Discussions

---

**Note**: This security policy applies to the Abunfi smart contracts project. Demo and test code are clearly separated from production code and follow appropriate security practices for their intended use.
