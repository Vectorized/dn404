# DN404: ERC20/ERC721 Co-Joined Implementation

[![NPM][npm-shield]][npm-url]
[![CI][ci-shield]][ci-url]

Welcome to DN404, an experimental implementation of co-joined ERC20 and ERC721 contracts. 
DN404 aims to provide seamless interoperability between ERC20 and ERC721 tokens, ensuring full compliance with their respective specifications while offering optimized functionality. 

## Overview 
DN404 enables transfers between ERC20 and ERC721 tokens, ensuring that actions performed on one side are reflected on the other side. 
This project is designed to facilitate easy integration of ERC20 and ERC721 tokens within a single ecosystem, providing developers with a robust foundation for building decentralized applications. 

## Installation

With [**Foundry**](https://github.com/gakonst/foundry):
```sh
To install DN404 using Foundry, execute the following command: forge install vectorized/dn404 
```

With [**Hardhat**](https://github.com/nomiclabs/hardhat):

```sh
To install DN404 using Hardhat, execute the following command: npm install dn404
```

## Contracts

The DN404 repository contains the following Solidity smart contracts:

#### DN404: This contract represents the ERC20 functionality within DN404.

#### DN404Mirror: This contract represents the ERC721 functionality within DN404.

#### SimpleDN404: A simple example demonstrating DN404 as an ERC20 token.

#### NFTMintDN404: A simple example demonstrating DN404 as an ERC721 token.

These contracts are located in the src directory of the repository. Navigation of the branch to access the contracts is shown below.


```ml
src
├─ DN404 — "ERC20 contract for DN404"
├─ DN404Mirror — "ERC721 contract for DN404"
└─ example
   ├─ SimpleDN404 — "Simple DN404 example as ERC20"
   └─ NFTMintDN404 — "Simple DN404 example as ERC721"
```

## Contributing

Contributions to DN404 are highly encouraged! 
To contribute, please adhere to the guidelines outlined [here](https://github.com/Vectorized/solady/issues/19). 
You can contribute by submitting pull requests for new features, enhancements, or bug fixes.


## Safety

It's essential to note that DN404 is experimental software provided on an **as is** and **as available** basis. 
While the contracts have undergone thorough testing, there may still be unforeseen issues/emergent behavior, especially when used in conjunction with other code or future Solidity versions. 

**Always** conduct comprehensive testing to ensure compatibility with your codebase.

## Upgradability

Most contracts within DN404 support both upgradeable and non-upgradeable (regular) implementations. 
If utilizing upgradeable contracts, ensure to call any required internal initialization methods accordingly..

## Acknowledgements

DN404 draws inspiration from various sources, including:
- [Serec](https://twitter.com/SerecThunderson)
- [Solady](https://github.com/vectorized/solady)
- [ERC721A](https://github.com/chiru-labs/ERC721A)
  
These sources have played a significant role in shaping the design and functionality of DN404.


[npm-shield]: https://img.shields.io/npm/v/dn404.svg
[npm-url]: https://www.npmjs.com/package/dn404

[ci-shield]: https://img.shields.io/github/actions/workflow/status/vectorized/dn404/ci.yml?branch=main&label=build
[ci-url]: https://github.com/vectorized/dn404/actions/workflows/ci.yml
