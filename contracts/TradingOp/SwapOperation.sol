// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ILBRouter, ILBFactory, ILBPair} from "../interface/Moe.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MoeContract {
    using SafeERC20 for IERC20;

    address private constant factory =
        0x972BcB0284cca0152527c4f70f8F689852bCAFc5;

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
        address tokenOut,
        uint256 binStep,
        address pair,
        address to
    ) internal returns (uint256 amountOutReal) {
        ILBRouter router = ILBRouter(_router);
        // Approvo il router
        IERC20(tokenIn).approve(_router, 0); // Reset prima
        IERC20(tokenIn).approve(_router, amountIn); // Poi approva
        // Preparo il path
        address[] memory tokenPath = new address[](2);
        tokenPath[0] = tokenIn;
        tokenPath[1] = tokenOut;

        uint256[] memory binSteps = new uint256[](1);
        binSteps[0] = binStep;

        ILBRouter.Version[] memory versions = new ILBRouter.Version[](1);
        versions[0] = ILBRouter.Version.V2_2;

        ILBRouter.Path memory path = ILBRouter.Path({
            pairBinSteps: binSteps,
            versions: versions,
            tokenPath: tokenPath
        });

        // Calcolo amount out con slippage (1%)
        (uint128 expectedOut, , ) = router.getSwapOut(pair, amountIn, true);
        uint256 minAmountOut = (uint256(expectedOut) * 99) / 100;

        // Eseguo lo swap
        amountOutReal = router.swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            to,
            block.timestamp + 300 // 5 minuti
        );
    }

    function provideLiquidity(
        address tokenX,
        address tokenY,
        uint256 amountX,
        uint256 amountY,
        address pair,
        uint256 binStep,
        uint256 activeId,
        address router,
        address receiver
    )
        internal
        returns (uint256[] memory depositIds, uint256[] memory liquidityMinted)
    {
        IERC20(tokenX).approve(router, amountX);
        IERC20(tokenY).approve(router, amountY);

        int256[] memory deltaIds = new int256[](1);
        deltaIds[0] = 0; // Solo bin attivo

        uint256[] memory distributionX = new uint256[](1);
        distributionX[0] = 1e18;

        uint256[] memory distributionY = new uint256[](1);
        distributionY[0] = 1e18;

        ILBRouter.LiquidityParameters memory params = ILBRouter
            .LiquidityParameters({
                tokenX: tokenX,
                tokenY: tokenY,
                binStep: binStep,
                amountX: amountX,
                amountY: amountY,
                amountXMin: (amountX * 99) / 100,
                amountYMin: (amountY * 99) / 100,
                activeIdDesired: activeId,
                idSlippage: 5,
                deltaIds: deltaIds,
                distributionX: distributionX,
                distributionY: distributionY,
                to: receiver,
                refundTo: receiver,
                deadline: block.timestamp + 300
            });

        (, , , , depositIds, liquidityMinted) = ILBRouter(router).addLiquidity(
            params
        );
    }

    function withdrawLiquidity(
        address tokenX,
        address tokenY,
        address router,
        address pair,
        uint256[] memory ids,
        uint256[] memory amounts,
        address to
    ) public returns (uint256 amountX, uint256 amountY) {
        uint256 binStep = ILBFactory(factory).getBinStep(pair);

        uint256 amountXMin = (getTokenTotal(tokenX, pair, ids, amounts) * 99) /
            100;
        uint256 amountYMin = (getTokenTotal(tokenY, pair, ids, amounts) * 99) /
            100;

        ILBPair(pair).setApprovalForAll(router, true); // approva il router per rimuovere LP

        (amountX, amountY) = ILBRouter(router).removeLiquidity(
            IERC20(tokenX),
            IERC20(tokenY),
            uint16(binStep),
            amountXMin,
            amountYMin,
            ids,
            amounts,
            to,
            block.timestamp + 300
        );
    }

    // Funzione di supporto per calcolare stima minima del token nei bin
    function getTokenTotal(
        address token,
        address pair,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal view returns (uint256 total) {
        for (uint256 i = 0; i < ids.length; i++) {
            (uint256 x, uint256 y) = ILBPair(pair).getBin(uint24(ids[i]));
            uint256 supply = ILBPair(pair).totalSupply(uint24(ids[i]));

            uint256 userShare = amounts[i];
            if (token == ILBPair(pair).getTokenX()) {
                total += (userShare * x) / supply;
            } else {
                total += (userShare * y) / supply;
            }
        }
    }
}
