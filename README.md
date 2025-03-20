# Uniswap V2 Foundry Implementation

This project is a port of Uniswap V2 using the Foundry development framework. It implements the core functionality of Uniswap V2 including the automated market maker (AMM), liquidity pools, and router functionality.

## Overview

Uniswap V2 is a decentralized exchange protocol built on Ethereum that enables automated, permissionless trading of ERC-20 tokens without trusted intermediaries. This implementation maintains all the key features of the original Uniswap V2 while leveraging Foundry's advanced testing capabilities.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

## Installation

```bash
# Clone the repository
git clone https://github.com/fyZhang66/uniswapV2-foundry.git
cd uniswap-v2-foundry

# Install dependencies
forge install
```

## Key Features

- **Pair Contracts**: Automated market maker pools for token pairs
- **Factory Contract**: Creates and manages trading pairs
- **Router Contract**: Handles user interactions, including liquidity management and swaps
- **Optimized Gas Usage**: Implements efficient storage patterns and calculations
- **Flash Swaps**: Allows borrowing from pools within a transaction

## Critical Setup: Init Code Hash

One important step when working with this implementation is calculating the correct init code hash. This is required for the CREATE2 address calculation used in the `pairFor` function.

### Steps to set up init code hash:

1. Calculate the hash by running:
```bash
forge test --match-test testGetInitCodeHash -vvv
```

2. Copy the output hash value

3. Update it in the UniswapV2Library.sol file:
```solidity
function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
    (address token0, address token1) = sortTokens(tokenA, tokenB);
    pair = address(uint160(uint256(keccak256(abi.encodePacked(
        hex'ff',
        factory,
        keccak256(abi.encodePacked(token0, token1)),
        hex'PASTE_YOUR_HASH_HERE' // Update with the hash from step 2
    )))));
}
```

4. Use this value for all subsequent tests

> **Note**: The init code hash must be recalculated anytime the `UniswapV2Pair` implementation changes, including changes to Solidity version or compiler settings.

## Testing

The project includes comprehensive tests for all major components:

```bash
# Run all tests
forge test

# Run a specific test
forge test --match-test testAddLiquidityInitial -vvv

# See gas usage
forge test --gas-report
```

Key test files:
- UniswapV2Factory.t.sol: Tests for pair creation
- UniswapV2Pair.t.sol: Tests core AMM functionality
- UniswapV2Router.t.sol: Tests routing and user interaction
- InitCodeHash.t.sol: Calculates init code hash

## Code Coverage

This implementation has been thoroughly tested to ensure comprehensive code coverage. Coverage reports help identify untested code paths and potential vulnerabilities.

### Running Coverage Analysis

To generate a coverage report:

```bash
# Install coverage tools if not already available
forge install foundry-rs/forge-coverage

# Run coverage analysis
forge coverage --report lcov

# Convert to HTML report (requires lcov)
genhtml lcov.info -o coverage_report
```

You can also run coverage for specific contracts:

```bash
# Coverage for router only
forge coverage --match-path src/UniswapV2Router.sol --report lcov
```

### Coverage Results

Current coverage metrics:
- **Core Contracts**: >95% line coverage
- **Router**: >90% line coverage
- **Libraries**: >95% line coverage

### Coverage Challenges

Some parts of the codebase present specific coverage challenges:

1. **Stack Too Deep Functions**: Complex functions like `removeLiquidityETHWithPermitSupportingFeeOnTransferTokens` require special testing approaches to avoid compiler errors.

2. **Multi-Path Swaps**: Testing all possible token swap paths requires dedicated test files for better organization.

3. **Error Conditions**: Tests are designed to trigger all possible error conditions to ensure proper validation.

### Improving Coverage

To improve coverage:
- Split complex tests into multiple smaller test functions
- Use dedicated test files for complex features
- Create specialized mocks when needed for specific scenarios
- Focus on branch coverage for conditional logic

## Project Structure

```
src/
├── UniswapV2Factory.sol    // Creates pairs and manages protocol fees
├── UniswapV2Pair.sol       // Core AMM implementation
├── UniswapV2Router.sol     // User-facing interface for swaps and liquidity
├── UniswapV2ERC20.sol      // LP token implementation
├── libraries/              // Helper functions and utilities
│   ├── Math.sol            
│   ├── UQ112x112.sol       // Fixed-point math library 
│   ├── UniswapV2Library.sol
│   └── TransferHelper.sol  
└── interfaces/             // Contract interfaces

test/
├── UniswapV2Pair.t.sol     // Tests for pair functionality 
├── UniswapV2Factory.t.sol  // Tests for factory functionality
├── UniswapV2Router.t.sol   // Tests for router functionality
├── InitCodeHash.t.sol      // Helper to calculate init code hash
├── UniswapV2PriceCalculation.t.sol // Tests for price calculation functions
├── UniswapV2PermitCoverage.t.sol   // Specialized tests for permit functions
└── mocks/                  // Mock contracts for testing
    ├── ERC20Mock.sol       
    └── WETHMock.sol
```

## Configuration

The project uses Foundry's configuration in foundry.toml:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
via_ir = true
solc_version = "0.8.20"
optimizer = true
optimizer_runs = 200
```

Note the `via_ir = true` setting, which helps avoid "Stack too deep" errors in complex functions.

## Key Technical Concepts

- **Constant Product Formula**: `x * y = k` maintains the core AMM mechanism
- **Price Oracles**: Implemented via cumulative price tracking
- **Flash Swaps**: Allow tokens to be borrowed and returned in one transaction
- **Protocol Fees**: Optional 0.05% fee that can be turned on/off

## License

This project is licensed under GPL-3.0-or-later, the same as the original Uniswap V2.

## Acknowledgements

- [Uniswap V2](https://github.com/Uniswap/v2-core)
- [Foundry](https://github.com/foundry-rs/foundry)

---

## Further Resources

- [Uniswap V2 Documentation](https://docs.uniswap.org/contracts/v2/overview)
- [Foundry Book](https://book.getfoundry.sh/)
- [Uniswap V2 Whitepaper](https://uniswap.org/whitepaper.pdf)