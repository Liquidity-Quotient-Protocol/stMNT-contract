// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ILendingPool} from "../interface/ILendl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Lendl
 * @dev Utility contract for interacting with a Lendle/Aave-like lending pool.
 */
contract Lendl {
    using SafeERC20 for IERC20;

    /**
     * @notice Deposit `_tokenIn` into Lendle and receive lTokens.
     * @param _lendingPool Address of the lending pool (e.g., LendingPool).
     * @param _tokenIn Token to deposit (e.g., WMNT).
     * @param _amount Amount to deposit.
     * @param _lToken Address of the lToken corresponding to `_tokenIn`.
     * @return share Amount of lTokens received.
     */
    function depositLendl(
        address _lendingPool,
        address _tokenIn,
        uint256 _amount,
        address _lToken
    ) internal returns (uint256 share) {
        uint256 balanceBefore = IERC20(_lToken).balanceOf(address(this));
        ILendingPool(_lendingPool).deposit(_tokenIn, _amount, address(this), 0);
        uint256 balanceAfter = IERC20(_lToken).balanceOf(address(this));
        share = balanceAfter - balanceBefore;
    }

    /**
     * @notice Withdraw `_amount` of `_asset` from Lendle.
     * @param lendingPool Address of the lending pool.
     * @param asset Underlying asset to withdraw.
     * @param amount Amount to withdraw.
     * @return received Amount of underlying asset received.
     */
    function withdrawLendl(
        address lendingPool,
        address asset,
        uint256 amount
    ) internal returns (uint256 received) {
        received = ILendingPool(lendingPool).withdraw(asset, amount, address(this));
    }
}
