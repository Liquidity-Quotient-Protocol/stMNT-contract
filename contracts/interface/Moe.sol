// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILBRouter {
    enum Version {
        V1,
        V2_0,
        V2_1,
        V2_2
    }

    struct LiquidityParameters {
        address tokenX;
        address tokenY;
        uint256 binStep;
        uint256 amountX;
        uint256 amountY;
        uint256 amountXMin;
        uint256 amountYMin;
        uint256 activeIdDesired;
        uint256 idSlippage;
        int256[] deltaIds;
        uint256[] distributionX;
        uint256[] distributionY;
        address to;
        address refundTo;
        uint256 deadline;
    }

    struct Path {
        uint256[] pairBinSteps;
        Version[] versions;
        address[] tokenPath;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Path calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOutReal);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        Path calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountOutReal);

    function getSwapOut(
        address pair,
        uint256 amountIn,
        bool swapForY
    )
        external
        view
        returns (uint128 amountOut, uint128 amountInLeft, uint128 fee);

    function addLiquidity(
        LiquidityParameters memory liquidityParameters
    )
        external
        returns (
            uint256 amountXAdded,
            uint256 amountYAdded,
            uint256 amountXLeft,
            uint256 amountYLeft,
            uint256[] memory depositIds,
            uint256[] memory liquidityMinted
        );

    function removeLiquidity(
        IERC20 tokenX,
        IERC20 tokenY,
        uint16 binStep,
        uint256 amountXMin,
        uint256 amountYMin,
        uint256[] memory ids,
        uint256[] memory amounts,
        address to,
        uint256 deadline
    ) external returns (uint256 amountX, uint256 amountY);

    function getBinStep(address pair) external view returns (uint256);
    function weth() external view returns (address);
}

interface ILBFactory {
    function getBinStep(address pair) external view returns (uint256);
}

interface ILBPair {
    function getActiveId() external view returns (uint24);
    function setApprovalForAll(address operator, bool approved) external;
    function getBin(uint24 id) external view returns (uint256 x, uint256 y);
    function totalSupply(uint24 id) external view returns (uint256);
    function getTokenX() external view returns (address);
    function getTokenY() external view returns (address);
    function balanceOf(
        address account,
        uint256 id
    ) external view returns (uint256);
    // Puoi aggiungere altre funzioni se necessarie
}