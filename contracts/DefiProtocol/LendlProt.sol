// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

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
        
        // Approve the lending pool to spend our tokens
        //IERC20(_tokenIn).safeApprove(_lendingPool, _amount); //! qui deve essere gia approvato non devo approvare sempre 
        
        // Deposit to Lendle
        ILendingPool(_lendingPool).deposit(_tokenIn, _amount, address(this), 0);
        
        uint256 balanceAfter = IERC20(_lToken).balanceOf(address(this));
        share = balanceAfter - balanceBefore;
        
        require(share > 0, "No lTokens received");
    }

    /**
     * @notice Withdraw `_amount` of lTokens from Lendle.
     * @param lendingPool Address of the lending pool.
     * @param _lToken Address of the lToken to withdraw.
     * @param amount Amount of lTokens to withdraw.
     * @return received Amount of underlying asset received.
     */
    function withdrawLendl(
        address lendingPool,
        address _lToken,
        uint256 amount
    ) internal returns (uint256 received) {
        // For Aave/Lendle, we withdraw by specifying the underlying asset and amount of lTokens
        // The lToken contract handles the burning automatically
        received = ILendingPool(lendingPool).withdraw(_lToken, amount, address(this));
        require(received > 0, "No assets received from withdrawal");
    }
}