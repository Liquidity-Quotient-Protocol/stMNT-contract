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


interface IMoneyMarketHook {
    struct RebaseHelperParams {
        address helper; // wrap helper address if address(0) then not wrap
        address tokenIn; // token to use in rebase helper
    }

    struct DepositParams {
        address pool; // lending pool to deposit
        uint amt; // token amount to deposit
        RebaseHelperParams rebaseHelperParams; // wrap params
    }

    struct WithdrawParams {
        address pool; // lending pool to withdraw
        uint shares; // shares to withdraw
        RebaseHelperParams rebaseHelperParams; // wrap params
        address to; // receiver to receive withdraw tokens
    }

    struct RepayParams {
        address pool; // lending pool to repay
        uint shares; // shares to repay
    }

    struct BorrowParams {
        address pool; // lending pool to borrow
        uint amt; // token amount to borrow
        address to; // receiver to receive borrow tokens
    }

    struct OperationParams {
        uint posId; // position id to execute (0 to create new position)
        address viewer; // address to view position
        uint16 mode; // position mode to be used
        DepositParams[] depositParams; // deposit parameters
        WithdrawParams[] withdrawParams; // withdraw parameters
        BorrowParams[] borrowParams; // borrow parameters
        RepayParams[] repayParams; // repay parameters
        uint minHealth_e18; // minimum health to maintain after execute
        bool returnNative; // return native token or not
    }

    function execute(
        OperationParams calldata _params
    )
        external
        payable
        returns (uint256 posId, uint256 initPosId, bytes[] memory results);

    function lastPosIds(
        address _user
    ) external view returns (uint256 lastPosId);

    function initPosIds(
        address user,
        uint256 posId
    ) external view returns (uint256 initPosId);
}
interface IPosManager {
    function getPosBorrInfo(uint _posId) external view returns (
        address[] memory pools, 
        uint[] memory debtShares
    );
    
    function getPosCollInfo(uint _posId) external view returns (
        address[] memory pools,
        uint[] memory amts,
        address[] memory wLps,
        uint[][] memory ids,
        uint[][] memory wLpAmts
    );
}