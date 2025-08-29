#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// Ensure out directory exists (contracts should be compiled first)
const outDir = path.join(__dirname, '..', 'out');
if (!fs.existsSync(outDir)) {
  console.error('Error: out/ directory not found. Please run "forge build" first.');
  process.exit(1);
}

// Create exports directory
const exportsDir = path.join(__dirname, '..', 'exports');
if (!fs.existsSync(exportsDir)) {
  fs.mkdirSync(exportsDir, { recursive: true });
}

// Contract artifacts to export
const contracts = [
  {
    name: 'AbunfiVault',
    path: 'AbunfiVault.sol/AbunfiVault.json'
  },
  {
    name: 'AaveStrategy', 
    path: 'AaveStrategy.sol/AaveStrategy.json'
  },
  {
    name: 'MockERC20',
    path: 'MockERC20.sol/MockERC20.json'
  }
];

// Export ABIs
const exportedContracts = {};

contracts.forEach(contract => {
  const artifactPath = path.join(outDir, contract.path);
  
  if (fs.existsSync(artifactPath)) {
    try {
      const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
      
      // Extract just the ABI
      const contractData = {
        abi: artifact.abi,
        bytecode: artifact.bytecode.object
      };
      
      // Write individual ABI file
      fs.writeFileSync(
        path.join(exportsDir, `${contract.name}.json`),
        JSON.stringify(contractData, null, 2)
      );
      
      // Add to combined export
      exportedContracts[contract.name] = contractData;
      
      console.log(`✅ Exported ${contract.name}`);
    } catch (error) {
      console.warn(`⚠️  Failed to export ${contract.name}: ${error.message}`);
    }
  } else {
    console.warn(`⚠️  Artifact not found: ${contract.path}`);
  }
});

// Write combined exports file
fs.writeFileSync(
  path.join(exportsDir, 'index.json'),
  JSON.stringify(exportedContracts, null, 2)
);

console.log(`\n🎉 Successfully exported ${Object.keys(exportedContracts).length} contracts to exports/`);
