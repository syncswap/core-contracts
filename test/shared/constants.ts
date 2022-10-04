import { BigNumber } from 'ethers';
import {
    keccak256,
    toUtf8Bytes,
} from 'ethers/lib/utils'

export abstract class Constants {
    public static PERMIT_TYPEHASH = keccak256(
        toUtf8Bytes('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)')
    );

    public static CHAIN_ID = 280;

    public static UINT256_MAX = BigNumber.from(2).pow(256).sub(1);

    public static ETH_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE';

    public static ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
}