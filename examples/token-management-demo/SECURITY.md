# Security Notice for Demo Code

## Overview

This directory contains demonstration and testing code for the RISC Zero social verification system. The code is designed for **educational and testing purposes only** and should not be used in production environments.

## Security Considerations

### Code Scanning Alerts

GitHub's CodeQL scanner may flag this demo code for the following reasons:

1. **`require()` Usage**: The demo uses Node.js `require()` statements to import built-in modules
2. **Dynamic Execution**: Some testing scenarios simulate dynamic behavior

### Why These Are Safe in This Context

#### ✅ **Safe `require()` Usage**
```javascript
const crypto = require('crypto');  // Built-in Node.js module
```

- **Static Imports**: All `require()` calls use static string literals
- **Built-in Modules**: Only imports Node.js built-in modules (`crypto`)
- **No User Input**: No dynamic module names or user-controlled input
- **No `eval()`**: No use of `eval()`, `Function()`, or similar dynamic execution

#### ✅ **Demo Code Context**
- **Testing Only**: Code is for demonstration and testing purposes
- **No Network Access**: No external API calls or network requests
- **Controlled Environment**: Runs in isolated demo environment
- **Educational Purpose**: Designed to show token management concepts

### Production Recommendations

If adapting this code for production use:

1. **Remove Demo Code**: Don't include demo files in production deployments
2. **Use ES Modules**: Consider using `import` statements instead of `require()`
3. **Input Validation**: Add proper input validation for any user data
4. **Security Audit**: Conduct thorough security review
5. **Dependency Scanning**: Use tools like `npm audit` for dependency vulnerabilities

### CodeQL Configuration

To suppress false positives for demo code, the repository includes:

```yaml
# .github/codeql/codeql-config.yml
paths-ignore:
  - "examples/**"
  - "risc0-social-verifier/**"
  - "docs/**"
  - "test/**"

query-filters:
  - exclude:
      id: js/code-injection
      reason: "Demo and test files use require() for legitimate purposes"
```

## File-by-File Analysis

### `demo.js`
- **Purpose**: Interactive demonstration of token management
- **Security**: Uses only built-in Node.js modules
- **Risk Level**: ✅ Low (demo code only)

### `README.md`
- **Purpose**: Documentation and usage instructions
- **Security**: Static documentation
- **Risk Level**: ✅ None

## Running Safely

### Prerequisites
```bash
# Ensure you're in a safe environment
cd examples/token-management-demo

# Check Node.js version (recommended: 16+)
node --version

# No external dependencies required
```

### Execution
```bash
# Run the demo (safe, no network access)
node demo.js

# Or run specific scenarios
node -e "
const Demo = require('./demo.js');
const demo = new Demo();
demo.runTokenExpirationDemo();
"
```

## Security Best Practices

### For Developers
1. **Review Code**: Always review demo code before running
2. **Isolated Environment**: Run demos in isolated/sandboxed environments
3. **No Production Data**: Never use real OAuth tokens or production data
4. **Regular Updates**: Keep demo code updated with security best practices

### For Security Teams
1. **Whitelist Demo Paths**: Configure security scanners to ignore demo directories
2. **Separate Scanning**: Use different security policies for demo vs. production code
3. **Documentation**: Maintain clear documentation about demo code purpose
4. **Regular Review**: Periodically review demo code for security implications

## Reporting Security Issues

If you find security issues in the demo code:

1. **Create Issue**: Open a GitHub issue with details
2. **Label Appropriately**: Use "security" and "demo" labels
3. **Provide Context**: Explain the potential impact
4. **Suggest Fixes**: Propose improvements if possible

## Disclaimer

This demo code is provided "as is" for educational purposes. It is not intended for production use and should not be deployed in production environments without proper security review and modifications.

---

**Note**: This security notice applies specifically to demo and testing code. The main RISC Zero social verification system (smart contracts and core components) follows production security standards.
