// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../../src/DN420.sol";

contract MockDN420OnlyERC20 is DN420 {
    constructor() {
        _initializeDN420(0, address(this));
    }

    function name() public view virtual override returns (string memory) {
        return "name";
    }

    function symbol() public view virtual override returns (string memory) {
        return "SYMBOL";
    }

    function uri(uint256) public view virtual override returns (string memory) {
        return "";
    }

    function _addressData(address a) internal virtual override returns (AddressData storage d) {
        d = DN420._addressData(a);
        d.flags |= _ADDRESS_DATA_SKIP_NFT_FLAG;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount, "");
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}
