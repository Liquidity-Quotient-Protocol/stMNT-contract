// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ILBRouter, ILBPair} from "../interface/Agni.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MoeContract {
    using SafeERC20 for IERC20;

    enum Version {
        V1,
        V2_0,
        V2_1,
        V2_2
    }

    constructor() {}

    function _swapExactTokensForTokens(
        address _router,
        uint256 amountIn,
        address tokenIn,
        uint256 minAmountOut,
        address[] memory tokenPath,
        address to
    ) internal returns (uint256 amountOutReal) {
        ILBRouter router = ILBRouter(_router);

        IERC20(tokenIn).approve(_router, 0);
        IERC20(tokenIn).approve(_router, amountIn);

        amountOutReal = router.swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            tokenPath,
            to
        );
    }
}
