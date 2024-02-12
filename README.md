# DN404 🥜

[![NPM][npm-shield]][npm-url]
[![CI][ci-shield]][ci-url]

DN404 is an implementation of a co-joined ERC20 and ERC721 pair.

- Full compliance with the ERC20 and ERC721 specifications.
- Transfers on one side will be reflected on the other side.
- Pretty optimized.

## Installation

To install with [**Foundry**](https://github.com/gakonst/foundry):

```sh
forge install vectorized/dn404
```

To install with [**Hardhat**](https://github.com/nomiclabs/hardhat):

```sh
npm install dn404
```

## Contracts

The Solidity smart contracts are located in the `src` directory.

```ml
src
├─ DN404 — "ERC20 contract for DN404"
├─ DN404Mirror — "ERC721 contract for DN404"
└─ example
   └─ SimpleDN404 — "Simple DN404 example"
```

## Contributing

Feel free to make a pull request.

Guidelines same as [Solady's](https://github.com/Vectorized/solady/issues/19).

## Safety

This is **experimental software** and is provided on an "as is" and "as available" basis.

We **do not give any warranties** and **will not be liable for any loss** incurred through any use of this codebase.

While DN404 has been heavily tested, there may be parts that may exhibit unexpected emergent behavior when used with other code, or may break in future Solidity versions.  

Please always include your own thorough tests when using DN404 to make sure it works correctly with your code.  

## Upgradability

Most contracts in DN404 are compatible with both upgradeable and non-upgradeable (i.e. regular) contracts. 

Please call any required internal initialization methods accordingly.

## Acknowledgements

This repository is inspired by various sources:

- [Serec](https://twitter.com/SerecThunderson)
- [Solady](https://github.com/vectorized/solady)
- [ERC721A](https://github.com/chiru-labs/ERC721A)

[npm-shield]: https://img.shields.io/npm/v/dn404.svg
[npm-url]: https://www.npmjs.com/package/dn404

[ci-shield]: https://img.shields.io/github/actions/workflow/status/vectorized/dn404/ci.yml?branch=main&label=build
[ci-url]: https://github.com/vectorized/dn404/actions/workflows/ci.yml
