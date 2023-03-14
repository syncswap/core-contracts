// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/token/IERC165.sol";
import "../interfaces/token/IERC20Permit2.sol";

import "./SignatureChecker.sol";

error Expired();
error InvalidSignature();

/**
 * @dev A simple ERC20 implementation for pool's liquidity token, supports permit by both ECDSA signatures from
 * externally owned accounts (EOAs) as well as ERC1271 signatures from smart contract wallets like Argent.
 *
 * Based on Solmate's ERC20.
 * https://github.com/transmissions11/solmate/blob/bff24e835192470ed38bf15dbed6084c2d723ace/src/tokens/ERC20.sol
 */
contract ERC20Permit2 is IERC165, IERC20Permit2 {
    uint8 public immutable override decimals = 18;

    uint public override totalSupply;
    mapping(address => uint) public override balanceOf;
    mapping(address => mapping(address => uint)) public override allowance;

    bytes32 private constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9; // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    mapping(address => uint) public override nonces;

    // These members are actually immutable as
    // `_initialize` will only indent to be called once.
    string public override name;
    string public override symbol;
    uint private INITIAL_CHAIN_ID;
    bytes32 private INITIAL_DOMAIN_SEPARATOR;

    function _initialize(string memory _name, string memory _symbol) internal {
        name = _name;
        symbol = _symbol;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
    }

    function supportsInterface(bytes4 interfaceID) external pure override returns (bool) {
        return
            interfaceID == this.supportsInterface.selector || // ERC-165
            interfaceID == this.permit.selector || // ERC-2612
            interfaceID == this.permit2.selector; // Permit2
    }

    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : _computeDomainSeparator();
    }

    function _computeDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                keccak256(bytes(name)),
                // keccak256(bytes("1"))
                0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6,
                block.chainid,
                address(this)
            )
        );
    }

    function _approve(address _owner, address _spender, uint _amount) private {
        allowance[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    function approve(address _spender, uint _amount) public override returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _to, uint _amount) public override returns (bool) {
        balanceOf[msg.sender] -= _amount;

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[_to] += _amount;
        }

        emit Transfer(msg.sender, _to, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint _amount) public override returns (bool) {
        uint256 _allowed = allowance[_from][msg.sender]; // Saves gas for limited approvals.
        if (_allowed != type(uint).max) {
            allowance[_from][msg.sender] = _allowed - _amount;
        }

        balanceOf[_from] -= _amount;
        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[_to] += _amount;
        }

        emit Transfer(_from, _to, _amount);
        return true;
    }

    function _mint(address _to, uint _amount) internal {
        totalSupply += _amount;

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[_to] += _amount;
        }

        emit Transfer(address(0), _to, _amount);
    }

    function _burn(address _from, uint _amount) internal {
        balanceOf[_from] -= _amount;

        // Cannot underflow because a user's balance will never be larger than the total supply.
        unchecked {
            totalSupply -= _amount;
        }

        emit Transfer(_from, address(0), _amount);
    }

    modifier ensures(uint _deadline) {
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > _deadline) {
            revert Expired();
        }
        _;
    }

    function _permitHash(
        address _owner,
        address _spender,
        uint _amount,
        uint _deadline
    ) private returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _amount, nonces[_owner]++, _deadline))
            )
        );
    }

    function permit(
        address _owner,
        address _spender,
        uint _amount,
        uint _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public override ensures(_deadline) {
        bytes32 _hash = _permitHash(_owner, _spender, _amount, _deadline);
        address _recoveredAddress = ecrecover(_hash, _v, _r, _s);

        if (_recoveredAddress != _owner) {
            revert InvalidSignature();
        }
        if (_recoveredAddress == address(0)) {
            revert InvalidSignature();
        }

        _approve(_owner, _spender, _amount);
    }

    function permit2(
        address _owner,
        address _spender,
        uint _amount,
        uint _deadline,
        bytes calldata _signature
    ) public override ensures(_deadline) {
        bytes32 _hash = _permitHash(_owner, _spender, _amount, _deadline);

        if (!SignatureChecker.isValidSignatureNow(_owner, _hash, _signature)) {
            revert InvalidSignature();
        }

        _approve(_owner, _spender, _amount);
    }
}