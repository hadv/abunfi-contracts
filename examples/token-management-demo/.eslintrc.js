module.exports = {
    env: {
        node: true,
        es2021: true,
    },
    extends: [
        'eslint:recommended',
    ],
    parserOptions: {
        ecmaVersion: 12,
        sourceType: 'module',
    },
    rules: {
        // Allow require() in demo code
        'import/no-dynamic-require': 'off',
        
        // Allow console.log in demo code
        'no-console': 'off',
        
        // Demo code specific rules
        'no-unused-vars': 'warn',
        'prefer-const': 'warn',
    },
    overrides: [
        {
            files: ['demo.js'],
            rules: {
                // Specifically allow require() in demo files
                'import/no-dynamic-require': 'off',
                'global-require': 'off',
            },
        },
    ],
};
