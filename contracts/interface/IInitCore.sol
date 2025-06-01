pragma solidity ^0.8.0;

interface IInitCore {
    function createPos(
        uint16 mode,
        address viewer
    ) external returns (uint256 posId);

    function mintTo(
        address lendingPool,
        address receiver
    ) external returns (uint256 shares);

    function burnTo(
        address lendingPool,
        address receiver
    ) external returns (uint256 amount);

    function collateralize(uint256 posId, address lendingPool) external;

    function decollateralize(
        uint256 posId,
        address lendingPool,
        uint256 shares,
        address receiver
    ) external;

    function borrow(
        address lendingPool,
        uint256 amount,
        uint256 posId,
        address receiver
    ) external returns (uint256 debtShares);

    function repay(
        address lendingPool,
        uint256 repayShares,
        uint256 posId
    ) external returns (uint256 repaidAmount);

    function setPosMode(uint256 posId, uint16 newMode) external;

    function balanceOf(address user) external view returns (uint256);
    function exchangeRate() external view returns (uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILendingPool {
    function debtAmtToShareStored(
        uint256 amount
    ) external view returns (uint256 shares);
    function debtAmtToShareCurrent(
        uint256 amount
    ) external returns (uint256 shares);
    function debtShareToAmtStored(
        uint256 shares
    ) external view returns (uint256 amount);
    function debtShareToAmtCurrent(
        uint256 shares
    ) external returns (uint256 amount);
    function toAmt(uint _shares) external view returns (uint256 _amt);
    function toShares(uint _amt) external view returns (uint256 _shares);
    function balanceOf(address user) external view returns (uint256);
    function toAmtCurrent(uint _shares) external returns (uint256 _amt);
    function accrueInterest() external ;
}

interface ILBFactory {
    function getBinStep(address pair) external view returns (uint256);
}

interface ILBPair {
    function getActiveId() external view returns (uint24);
}
