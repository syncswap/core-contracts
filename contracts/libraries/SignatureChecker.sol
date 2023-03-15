// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./ECDSA.sol";

/**
 * @dev Signature verification helper that can be used instead of `ECDSA.recover` to seamlessly support both ECDSA
 * signatures from externally owned accounts (EOAs) as well as ERC1271 signatures from smart contract wallets like
 * Argent and Gnosis Safe.
 *
 * Based on OpenZeppelin's SignatureChecker library.
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/561d1061fc568f04c7a65853538e834a889751e8/contracts/utils/cryptography/SignatureChecker.sol
 */
library SignatureChecker {

    bytes4 constant internal MAGICVALUE = 0x1626ba7e; // bytes4(keccak256("isValidSignature(bytes32,bytes)")

    /** 
     * @dev Checks if a signature is valid for a given signer and data hash. If the signer is a smart contract, the
     * signature is validated against that smart contract using ERC1271, otherwise it's validated using `ECDSA.recover`.
     *
     * NOTE: Unlike ECDSA signatures, contract signatures are revocable, and the outcome of this function can thus
     * change through time. It could return true at block N and false at block N+1 (or the opposite).
     */
    function isValidSignatureNow(
        address signer,
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool) {
        (address recovered) = ECDSA.recover(hash, signature);
        if (recovered == signer) {
            if (recovered != address(0)) {
                return true;
            }
        }

        (bool success, bytes memory result) = signer.staticcall(
            abi.encodeWithSelector(MAGICVALUE, hash, signature)
        );
        return (
            success &&
            result.length == 32 &&
            abi.decode(result, (bytes32)) == bytes32(MAGICVALUE)
        );
    }
}