// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../SyncSwapRouter.sol";
import "../interfaces/IRouter.sol";

contract RouterEventEmitter is IRouter {

    address public immutable vault;
    address public immutable wETH;
    address private constant NATIVE_ETH = address(0);

    constructor(address _vault, address _wETH) {
        vault = _vault;
        wETH = _wETH;
    }

    event Amounts(uint amount);

    receive() external payable {}

    function swap(
        address payable router,
        SwapPath[] memory paths,
        uint amountOutMin,
        uint deadline
    ) external {
        (bool success, bytes memory returnData) = router.delegatecall(abi.encodeWithSelector(
            SyncSwapRouter(router).swap.selector,
            paths,
            amountOutMin,
            deadline
        ));
        assert(success);
        emit Amounts(abi.decode(returnData, (uint)));
    }
}