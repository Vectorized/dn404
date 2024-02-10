# <img src="logo.svg" alt="soledge" height="70"/>

[![NPM][npm-shield]][npm-url]
[![CI][ci-shield]][ci-url]

Solidity snippets too edgy to be in [**Solady**](https://github.com/Vectorized/solady). 

For a future of EVMs fragmentation, where the latest opcodes are not supported on most L2s for years even after their inception on mainnet.

## Installation

To install with [**Foundry**](https://github.com/gakonst/foundry):

```sh
forge install vectorized/soledge
```

To install with [**Hardhat**](https://github.com/nomiclabs/hardhat):

```sh
npm install soledge
```

## Contracts

The Solidity smart contracts are located in the `src` directory.

```ml
utils
├─ LibT — "Transient storage helper"
├─ ReentrancyGuard — "Reentrancy guard mixin"
└─ LibString - "Library for converting numbers into strings and other string operations"
```

## Directories

```ml
src — "Solidity smart contracts"
test — "Foundry Forge tests"
```

## Contributing

Feel free to make a pull request.

Guidelines same as [Solady's](https://github.com/Vectorized/solady/issues/19).

## Safety

This is **experimental software** and is provided on an "as is" and "as available" basis.

We **do not give any warranties** and **will not be liable for any loss** incurred through any use of this codebase.

While Soledge has been heavily tested, there may be parts that may exhibit unexpected emergent behavior when used with other code, or may break in future Solidity versions.  

Please always include your own thorough tests when using Soledge to make sure it works correctly with your code.  

## Upgradability

Most contracts in Soledge are compatible with both upgradeable and non-upgradeable (i.e. regular) contracts. 

Please call any required internal initialization methods accordingly.

## EVM Compatibility

Some parts of Soledge may not be compatible with chains with partial EVM equivalence.

Please always check and test for compatibility accordingly.

## Acknowledgements

This repository is inspired by or directly modified from many sources, primarily:

- [Solmate](https://github.com/transmissions11/solmate)
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts)
- [ERC721A](https://github.com/chiru-labs/ERC721A)
- [Zolidity](https://github.com/z0r0z/zolidity)
- [🐍 Snekmate](https://github.com/pcaversaccio/snekmate)
- [Femplate](https://github.com/abigger87/femplate)

[npm-shield]: https://img.shields.io/npm/v/soledge.svg
[npm-url]: https://www.npmjs.com/package/soledge

[ci-shield]: https://img.shields.io/github/actions/workflow/status/vectorized/soledge/ci.yml?branch=main&label=build
[ci-url]: https://github.com/vectorized/soledge/actions/workflows/ci.yml
