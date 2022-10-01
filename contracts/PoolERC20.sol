// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import './libraries/SignatureChecker.sol';
import './interfaces/IPoolERC20.sol';

/**
 * @dev A simple ERC20 implementation for pool's liquidity token, supports permit by both ECDSA signatures from
 * externally owned accounts (EOAs) as well as ERC1271 signatures from smart contract wallets like Argent.
 *
 * Based on Solmate's ERC20.
 * https://github.com/transmissions11/solmate/blob/bff24e835192470ed38bf15dbed6084c2d723ace/src/tokens/ERC20.sol
 */
contract PoolERC20 is IPoolERC20 {
    string public constant override name = 'SyncSwap SLP Token';
    string public constant override symbol = 'SLP';
    uint8 public constant override decimals = 18;

    uint public override totalSupply;
    mapping(address => uint) public override balanceOf;
    mapping(address => mapping(address => uint)) public override allowance;
    
    bytes32 private immutable DOMAIN_SEPARATOR;
    bytes32 private constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9; // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    mapping(address => uint) public override nonces;

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f, // keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')
                0xf217daa25f50651e072a913278858c2bfea9576ad0ab9d0a2cd31744cea22cbe, // keccak256(bytes('SyncSwap SLP Token'))
                0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6, // keccak256(bytes('1'))
                280, // TESTNET
                address(this)
            )
        );
    }

    function _approve(address _owner, address _spender, uint _amount) private {
        allowance[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    function approve(address _spender, uint _amount) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _to, uint _amount) external override returns (bool) {
        balanceOf[msg.sender] -= _amount;

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[_to] += _amount;
        }

        emit Transfer(msg.sender, _to, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint _amount) external override returns (bool) {
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

    function permit(address _owner, address _spender, uint _amount, uint _deadline, uint8 _v, bytes32 _r, bytes32 _s) external override {
        require(_deadline >= block.timestamp, 'X'); // EXPIRED
        bytes32 _hash = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _amount, nonces[_owner]++, _deadline))
            )
        );
        address _recoveredAddress = ecrecover(_hash, _v, _r, _s);
        require(_recoveredAddress != address(0) && _recoveredAddress == _owner, 'S'); // SIGNATURE
        _approve(_owner, _spender, _amount);
    }

    function permit2(address _owner, address _spender, uint _amount, uint _deadline, bytes calldata _signature) external override {
        require(_deadline >= block.timestamp, 'X'); // EXPIRED
        bytes32 _hash = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _amount, nonces[_owner]++, _deadline))
            )
        );
        require(SignatureChecker.isValidSignatureNow(_owner, _hash, _signature), 'S'); // SIGNATURE
        _approve(_owner, _spender, _amount);
    }
}