// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {DN404, MockDN404Slim} from "./utils/mocks/MockDN404Slim.sol";
import {DN404Mirror} from "../src/DN404Mirror.sol";

abstract contract Ownable {
    event OwnershipTransferred(address indexed user, address indexed newOwner);

    error Unauthorized();
    error InvalidOwner();

    address public owner;

    modifier onlyOwner() virtual {
        if (msg.sender != owner) revert Unauthorized();

        _;
    }

    constructor(address _owner) {
        if (_owner == address(0)) revert InvalidOwner();

        owner = _owner;

        emit OwnershipTransferred(address(0), _owner);
    }

    function transferOwnership(address _owner) public virtual onlyOwner {
        if (_owner == address(0)) revert InvalidOwner();

        owner = _owner;

        emit OwnershipTransferred(msg.sender, _owner);
    }

    function revokeOwnership() public virtual onlyOwner {
        owner = address(0);

        emit OwnershipTransferred(msg.sender, address(0));
    }
}

abstract contract ERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        return ERC721Receiver.onERC721Received.selector;
    }
}

/// @notice ERC404
///         A gas-efficient, mixed ERC20 / ERC721 implementation
///         with native liquidity and fractionalization.
///
///         This is an experimental standard designed to integrate
///         with pre-existing ERC20 / ERC721 support as smoothly as
///         possible.
///
/// @dev    In order to support full functionality of ERC20 and ERC721
///         supply assumptions are made that slightly constraint usage.
///         Ensure decimals are sufficiently large (standard 18 recommended)
///         as ids are effectively encoded in the lowest range of amounts.
///
///         NFTs are spent on ERC20 functions in a FILO queue, this is by
///         design.
///
abstract contract ERC404 is Ownable {
    // Events
    event ERC20Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event ERC721Approval(address indexed owner, address indexed spender, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // Errors
    error NotFound();
    error AlreadyExists();
    error InvalidRecipient();
    error InvalidSender();
    error UnsafeRecipient();

    // Metadata
    /// @dev Token name
    string public name;

    /// @dev Token symbol
    string public symbol;

    /// @dev Decimals for fractional representation
    uint8 public immutable decimals;

    /// @dev Total supply in fractionalized representation
    uint256 public immutable totalSupply;

    /// @dev Current mint counter, monotonically increasing to ensure accurate ownership
    uint256 public minted;

    // Mappings
    /// @dev Balance of user in fractional representation
    mapping(address => uint256) public balanceOf;

    /// @dev Allowance of user in fractional representation
    mapping(address => mapping(address => uint256)) public allowance;

    /// @dev Approval in native representation
    mapping(uint256 => address) public getApproved;

    /// @dev Approval for all in native representation
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /// @dev Owner of id in native representation
    mapping(uint256 => address) internal _ownerOf;

    /// @dev Array of owned ids in native representation
    mapping(address => uint256[]) internal _owned;

    /// @dev Tracks indices for the _owned mapping
    mapping(uint256 => uint256) internal _ownedIndex;

    /// @dev Addresses whitelisted from minting / burning for gas savings (pairs, routers, etc)
    mapping(address => bool) public whitelist;

    // Constructor
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _totalNativeSupply,
        address _owner
    ) Ownable(_owner) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _totalNativeSupply * (10 ** _decimals);
    }

    /// @notice Initialization function to set pairs / etc
    ///         saving gas by avoiding mint / burn on unnecessary targets
    function setWhitelist(address target, bool state) public onlyOwner {
        whitelist[target] = state;
    }

    /// @notice Function to find owner of a given native token
    function ownerOf(uint256 id) public view virtual returns (address owner) {
        owner = _ownerOf[id];

        if (owner == address(0)) {
            revert NotFound();
        }
    }

    /// @notice tokenURI must be implemented by child contract
    function tokenURI(uint256 id) public view virtual returns (string memory);

    /// @notice Function for token approvals
    /// @dev This function assumes id / native if amount less than or equal to current max id
    function approve(address spender, uint256 amountOrId) public virtual returns (bool) {
        if (amountOrId <= minted && amountOrId > 0) {
            address owner = _ownerOf[amountOrId];

            if (msg.sender != owner && !isApprovedForAll[owner][msg.sender]) {
                revert Unauthorized();
            }

            getApproved[amountOrId] = spender;

            emit Approval(owner, spender, amountOrId);
        } else {
            allowance[msg.sender][spender] = amountOrId;

            emit Approval(msg.sender, spender, amountOrId);
        }

        return true;
    }

    /// @notice Function native approvals
    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @notice Function for mixed transfers
    /// @dev This function assumes id / native if amount less than or equal to current max id
    function transferFrom(address from, address to, uint256 amountOrId) public virtual {
        if (amountOrId <= minted) {
            if (from != _ownerOf[amountOrId]) {
                revert InvalidSender();
            }

            if (to == address(0)) {
                revert InvalidRecipient();
            }

            if (
                msg.sender != from && !isApprovedForAll[from][msg.sender]
                    && msg.sender != getApproved[amountOrId]
            ) {
                revert Unauthorized();
            }

            balanceOf[from] -= _getUnit();

            unchecked {
                balanceOf[to] += _getUnit();
            }

            _ownerOf[amountOrId] = to;
            delete getApproved[amountOrId];

            // update _owned for sender
            uint256 updatedId = _owned[from][_owned[from].length - 1];
            _owned[from][_ownedIndex[amountOrId]] = updatedId;
            // pop
            _owned[from].pop();
            // update index for the moved id
            _ownedIndex[updatedId] = _ownedIndex[amountOrId];
            // push token to to owned
            _owned[to].push(amountOrId);
            // update index for to owned
            _ownedIndex[amountOrId] = _owned[to].length - 1;

            emit Transfer(from, to, amountOrId);
            emit ERC20Transfer(from, to, _getUnit());
        } else {
            uint256 allowed = allowance[from][msg.sender];

            if (allowed != type(uint256).max) {
                allowance[from][msg.sender] = allowed - amountOrId;
            }

            _transfer(from, to, amountOrId);
        }
    }

    /// @notice Function for fractional transfers
    function transfer(address to, uint256 amount) public virtual returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    /// @notice Function for native transfers with contract support
    function safeTransferFrom(address from, address to, uint256 id) public virtual {
        transferFrom(from, to, id);

        if (
            to.code.length != 0
                && ERC721Receiver(to).onERC721Received(msg.sender, from, id, "")
                    != ERC721Receiver.onERC721Received.selector
        ) {
            revert UnsafeRecipient();
        }
    }

    /// @notice Function for native transfers with contract support and callback data
    function safeTransferFrom(address from, address to, uint256 id, bytes calldata data)
        public
        virtual
    {
        transferFrom(from, to, id);

        if (
            to.code.length != 0
                && ERC721Receiver(to).onERC721Received(msg.sender, from, id, data)
                    != ERC721Receiver.onERC721Received.selector
        ) {
            revert UnsafeRecipient();
        }
    }

    /// @notice Internal function for fractional transfers
    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        uint256 unit = _getUnit();
        uint256 balanceBeforeSender = balanceOf[from];
        uint256 balanceBeforeReceiver = balanceOf[to];

        balanceOf[from] -= amount;

        unchecked {
            balanceOf[to] += amount;
        }

        // Skip burn for certain addresses to save gas
        if (!whitelist[from]) {
            uint256 tokens_to_burn = (balanceBeforeSender / unit) - (balanceOf[from] / unit);
            for (uint256 i = 0; i < tokens_to_burn; i++) {
                _burn(from);
            }
        }

        // Skip minting for certain addresses to save gas
        if (!whitelist[to]) {
            uint256 tokens_to_mint = (balanceOf[to] / unit) - (balanceBeforeReceiver / unit);
            for (uint256 i = 0; i < tokens_to_mint; i++) {
                _mint(to);
            }
        }

        emit ERC20Transfer(from, to, amount);
        return true;
    }

    // Internal utility logic
    function _getUnit() internal view returns (uint256) {
        return 10 ** decimals;
    }

    function _mint(address to) internal virtual {
        if (to == address(0)) {
            revert InvalidRecipient();
        }

        unchecked {
            minted++;
        }

        uint256 id = minted;

        if (_ownerOf[id] != address(0)) {
            revert AlreadyExists();
        }

        _ownerOf[id] = to;
        _owned[to].push(id);
        _ownedIndex[id] = _owned[to].length - 1;

        emit Transfer(address(0), to, id);
    }

    function _burn(address from) internal virtual {
        if (from == address(0)) {
            revert InvalidSender();
        }

        uint256 id = _owned[from][_owned[from].length - 1];
        _owned[from].pop();
        delete _ownedIndex[id];
        delete _ownerOf[id];
        delete getApproved[id];

        emit Transfer(from, address(0), id);
    }

    function _setNameSymbol(string memory _name, string memory _symbol) internal {
        name = _name;
        symbol = _symbol;
    }
}

contract Pandora is ERC404 {
    string public dataURI;
    string public baseTokenURI;

    constructor(address _owner) ERC404("Pandora", "PANDORA", 18, 10000, _owner) {
        balanceOf[_owner] = 10000 * 10 ** 18;
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract BenchTest is SoladyTest {
    Pandora pandora;
    MockDN404Slim dn;
    DN404Mirror mirror;

    function setUp() public {
        pandora = new Pandora(address(this));
        dn = new MockDN404Slim();
        mirror = new DN404Mirror(address(this));

        pandora.setWhitelist(address(this), true);
        dn.initializeDN404(10000 * 10 ** 18, address(this), address(mirror));
    }

    modifier mint(address a, uint256 amount) {
        unchecked {
            address alice = address(111);
            IERC20(a).transfer(alice, amount * 10 ** 18);
        }
        _;
    }

    function testMintPandora_01() public mint(address(pandora), 1) {}
    function testMintDN404_01() public mint(address(dn), 1) {}
    function testMintPandora_02() public mint(address(pandora), 2) {}
    function testMintDN404_02() public mint(address(dn), 2) {}
    function testMintPandora_03() public mint(address(pandora), 3) {}
    function testMintDN404_03() public mint(address(dn), 3) {}
    function testMintPandora_04() public mint(address(pandora), 4) {}
    function testMintDN404_04() public mint(address(dn), 4) {}
    function testMintPandora_05() public mint(address(pandora), 5) {}
    function testMintDN404_05() public mint(address(dn), 5) {}
    function testMintPandora_06() public mint(address(pandora), 6) {}
    function testMintDN404_06() public mint(address(dn), 6) {}
    function testMintPandora_07() public mint(address(pandora), 7) {}
    function testMintDN404_07() public mint(address(dn), 7) {}
    function testMintPandora_08() public mint(address(pandora), 8) {}
    function testMintDN404_08() public mint(address(dn), 8) {}
    function testMintPandora_09() public mint(address(pandora), 9) {}
    function testMintDN404_09() public mint(address(dn), 9) {}
    function testMintPandora_10() public mint(address(pandora), 10) {}
    function testMintDN404_10() public mint(address(dn), 10) {}
    function testMintPandora_11() public mint(address(pandora), 11) {}
    function testMintDN404_11() public mint(address(dn), 11) {}
    function testMintPandora_12() public mint(address(pandora), 12) {}
    function testMintDN404_12() public mint(address(dn), 12) {}
    function testMintPandora_13() public mint(address(pandora), 13) {}
    function testMintDN404_13() public mint(address(dn), 13) {}
    function testMintPandora_14() public mint(address(pandora), 14) {}
    function testMintDN404_14() public mint(address(dn), 14) {}
    function testMintPandora_15() public mint(address(pandora), 15) {}
    function testMintDN404_15() public mint(address(dn), 15) {}
    function testMintPandora_16() public mint(address(pandora), 16) {}
    function testMintDN404_16() public mint(address(dn), 16) {}

    modifier mintAndTransfer(address a, uint256 amount) {
        unchecked {
            address alice = address(111);
            address bob = address(222);
            IERC20(a).transfer(alice, amount * 10 ** 18);
            vm.prank(alice);
            IERC20(a).transfer(bob, amount * 10 ** 18);
        }
        _;
    }

    function testMintAndTransferPandora_01() public mintAndTransfer(address(pandora), 1) {}
    function testMintAndTransferDN404_01() public mintAndTransfer(address(dn), 1) {}
    function testMintAndTransferPandora_02() public mintAndTransfer(address(pandora), 2) {}
    function testMintAndTransferDN404_02() public mintAndTransfer(address(dn), 2) {}
    function testMintAndTransferPandora_03() public mintAndTransfer(address(pandora), 3) {}
    function testMintAndTransferDN404_03() public mintAndTransfer(address(dn), 3) {}
    function testMintAndTransferPandora_04() public mintAndTransfer(address(pandora), 4) {}
    function testMintAndTransferDN404_04() public mintAndTransfer(address(dn), 4) {}
    function testMintAndTransferPandora_05() public mintAndTransfer(address(pandora), 5) {}
    function testMintAndTransferDN404_05() public mintAndTransfer(address(dn), 5) {}
    function testMintAndTransferPandora_06() public mintAndTransfer(address(pandora), 6) {}
    function testMintAndTransferDN404_06() public mintAndTransfer(address(dn), 6) {}
    function testMintAndTransferPandora_07() public mintAndTransfer(address(pandora), 7) {}
    function testMintAndTransferDN404_07() public mintAndTransfer(address(dn), 7) {}
    function testMintAndTransferPandora_08() public mintAndTransfer(address(pandora), 8) {}
    function testMintAndTransferDN404_08() public mintAndTransfer(address(dn), 8) {}
    function testMintAndTransferPandora_09() public mintAndTransfer(address(pandora), 9) {}
    function testMintAndTransferDN404_09() public mintAndTransfer(address(dn), 9) {}
    function testMintAndTransferPandora_10() public mintAndTransfer(address(pandora), 10) {}
    function testMintAndTransferDN404_10() public mintAndTransfer(address(dn), 10) {}
    function testMintAndTransferPandora_11() public mintAndTransfer(address(pandora), 11) {}
    function testMintAndTransferDN404_11() public mintAndTransfer(address(dn), 11) {}
    function testMintAndTransferPandora_12() public mintAndTransfer(address(pandora), 12) {}
    function testMintAndTransferDN404_12() public mintAndTransfer(address(dn), 12) {}
    function testMintAndTransferPandora_13() public mintAndTransfer(address(pandora), 13) {}
    function testMintAndTransferDN404_13() public mintAndTransfer(address(dn), 13) {}
    function testMintAndTransferPandora_14() public mintAndTransfer(address(pandora), 14) {}
    function testMintAndTransferDN404_14() public mintAndTransfer(address(dn), 14) {}
    function testMintAndTransferPandora_15() public mintAndTransfer(address(pandora), 15) {}
    function testMintAndTransferDN404_15() public mintAndTransfer(address(dn), 15) {}
    function testMintAndTransferPandora_16() public mintAndTransfer(address(pandora), 16) {}
    function testMintAndTransferDN404_16() public mintAndTransfer(address(dn), 16) {}
}
