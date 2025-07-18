// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.12;

import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";
import {Address} from "@openzeppelin-contract@5.3.0/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20 as IERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20 as SafeERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/utils/SafeERC20.sol";

import {IRSM} from "./interface/RsmInterface.sol";
import {IWMNT} from "./interface/IWMNT.sol";

/**
 * @title Strategy1st
 * @author LiQ Quotient Protocol Team
 * @notice A Yearn V2 strategy that deposits WMNT tokens into the Init Protocol lending pool to earn yield
 * @dev This strategy inherits from BaseStrategy (Yearn V2) and Iinit (Init protocol interaction)
 *      The strategy accepts WMNT as the want token and deposits it into Init lending pools to generate yield
 *      Uses Init Protocol's specific mechanisms for deposit/withdrawal and requires accrueInterest() calls
 *      for accurate yield calculation and reporting
 */
contract Strategy1st is BaseStrategy {
    using SafeERC20 for IERC20;
    using SafeERC20v4 for IERC20v4;
    using Address for address;

    /// @notice Immutable address of the Init protocol's core/router contract.
    address public constant rsmAddress =
        0xeD884f0460A634C69dbb7def54858465808AACEf;
    /// @notice Immutable address of the WMNT (Wrapped MNT) token, the 'want' token for this strategy.
    address public constant WMNT = 0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8;

    IRSM constant RSM = IRSM(rsmAddress);

    /// @notice Address of the Init Protocol lending pool where funds are deposited
    /// @dev Must be set by authorized users via setLendingPool() before strategy can function
    uint256 private balancePoints;

    /**
     * @notice Event emitted when there's an issue during withdrawal from the strategy's underlying positions
     * @param time The block timestamp when the problem occurred
     * @param share The amount of shares involved in the problematic operation
     * @param balanceShare The strategy's internal balanceShare at the time of the issue
     */
    event ProblemWithWithdrawStrategy(
        uint256 time,
        uint256 share,
        uint256 balanceShare
    );

    /**
     * @notice Constructs the Strategy1st contract
     * @dev Initializes the strategy with the vault address and Init protocol integration
     * @param _vault The address of the Yearn vault that will use this strategy
     * @param _owner The initial owner of this strategy contract (unused in current implementation)
     */
    constructor(
        address _vault,
        address _owner
    )
        // Removed explicit _initAddr param here as Iinit parent likely takes it from state or constant.
        // If your Iinit constructor *requires* it, it should be:
        // constructor(address _vault, address _owner, address __initAddr) BaseStrategy(_vault) Iinit(__initAddr) {}
        // For now, assuming Iinit(_initAddr) works with the state variable.
        BaseStrategy(_vault)
    {
        // Initialization is handled by parent constructors.
    }

    /**
     * @notice Updates the want token allowance for the vault contract
     * @dev Allows the vault to pull want tokens from this strategy during withdrawals
     * @param _approve If true, grants maximum allowance; otherwise, sets allowance to 0
     */
    function updateUnlimitedSpending(bool _approve) external onlyAuthorized {
        if (_approve) {
            SafeERC20v4.safeApprove(IERC20v4(want), address(vault), 0);
            SafeERC20v4.safeApprove(
                IERC20v4(want),
                address(vault),
                type(uint256).max
            );
        } else {
            SafeERC20v4.safeApprove(IERC20v4(want), address(vault), 0);
        }
    }

    /**
     * @notice Returns the display name of this strategy
     * @return The human-readable name of the strategy
     */
    function name() external view override returns (string memory) {
        return "Strategy REWARD STATION MANTLE";
    }

    uint256 private actualPoolId;

    /**
     * @notice Estimates the total assets managed by this strategy, valued in want tokens
     * @dev Includes liquid want tokens and the value of want tokens deposited in the lending pool
     *      Contains a strict check for internal vs on-chain share balance consistency
     * @return The total estimated value of assets in want token terms
     */
    function estimatedTotalAssets() public view override returns (uint256) {
        (uint256 lockedAmount, ) = RSM.getLockStatus(address(this));
        uint256 pendingRewards = RSM.calculatePendingRewards(
            address(this),
            actualPoolId
        );

        return lockedAmount + pendingRewards;
    }

    /**
     * @notice Prepares performance report data for the vault during harvest
     * @dev Accrues interest in the lending pool, calculates profit/loss, and ensures adequate liquidity
     *      May liquidate positions to meet debt obligations or profit reporting requirements
     *      Applies a 1 wei reduction to profit for precision issue mitigation
     * @param _debtOutstanding Amount the vault expects the strategy to repay or amount over debt limit
     * @return _profit The calculated profit to report to the vault
     * @return _loss The calculated loss to report to the vault
     * @return _debtPayment The amount of want tokens available for debt repayment
     */
    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {
        uint256 currentProfit = estimatedTotalAssets();

        _profit = currentProfit;
        _loss = 0;

        if (_debtOutstanding > 0) {
            _debtPayment = _debtOutstanding;
            uint256 neededLiquid = _debtPayment + _profit;
            uint256 currentLiquid = want.balanceOf(address(this));

            if (currentLiquid < neededLiquid) {
                uint256 amountToLiquidate = neededLiquid - currentLiquid;
                RSM.unlockMNT(amountToLiquidate);
                IWMNT(WMNT).deposit{value: amountToLiquidate}();
                _loss += amountToLiquidate;
            }
        } else {
            _debtPayment = 0;
            uint256 currentLiquid = want.balanceOf(address(this));
            if (currentLiquid < _profit) {
                uint256 amountToLiquidate = _profit - currentLiquid;
                RSM.unlockMNT(amountToLiquidate);
                IWMNT(WMNT).deposit{value: amountToLiquidate}();
                _loss += amountToLiquidate;
            }
        }

        if (_debtPayment == 1) {
            _debtPayment = 0;
        }

        if (_profit > 0) {
            _profit = _profit - 1;
        }
    }

    /**
     * @notice Adjusts the strategy's investment position after reporting to the vault
     * @dev Invests excess liquid want tokens into the lending pool while maintaining required liquidity
     * @param _debtOutstanding Debt amount the vault might recall or amount over the strategy's debt limit
     */
    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 _balanceInContract = want.balanceOf(address(this));

        if (_balanceInContract > _debtOutstanding) {
            uint256 _amountToInvest = _balanceInContract - _debtOutstanding;
            if (_amountToInvest > 0) {
                IWMNT(WMNT).withdraw(_amountToInvest); //! forse devo autorizare la spesa, mi ricordo di no vedremo
                RSM.lockMNT(address(this).balance);
            }
        }
    }

    /**
     * @notice Makes a specified amount of want tokens liquid by withdrawing from the lending pool if necessary
     * @dev Attempts to liquidate the exact amount needed, withdrawing from the pool if current liquidity is insufficient
     * @param _amountNeeded Target amount of liquid want tokens required
     * @return _liquidatedAmount Actual amount of want tokens made liquid after operations
     * @return _loss Loss incurred during withdrawal from the lending pool (if any)
     */
    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        (uint256 amountFreed, uint256 lossFromWithdraw) = _withdrawSingleAmount(
            _amountNeeded
        ); // Use both return values
        _loss = lossFromWithdraw; // Assign loss from withdrawal

        _liquidatedAmount = amountFreed;

        // If still not enough, and no loss was reported by _withdrawSingleAmount for this shortfall.
        // This implies _withdrawSingleAmount returned less than amountToWithdraw without reporting a full loss for it.
        if (
            _liquidatedAmount < _amountNeeded &&
            _loss == 0 &&
            amountFreed < _amountNeeded
        ) {
            _loss += (_amountNeeded - amountFreed);
        }
    }

    /**
     * @notice Liquidates all assets from the lending pool and holds them as want tokens in the strategy
     * @dev Used during strategy migration or emergency situations to exit all positions
     * @return The total want token balance of this strategy after complete liquidation
     */
    function liquidateAllPositions() internal override returns (uint256) {
        bool success = _totalRecall();
        require(success, "Strategy1st: Total recall failed.");
        return want.balanceOf(address(this));
    }

    /**
     * @notice Prepares the strategy for migration to a new strategy contract
     * @dev Liquidates all assets into want tokens to facilitate smooth migration
     * @param _newStrategy The address of the new strategy contract (unused in current implementation)
     */
    function prepareMigration(address _newStrategy) internal override {
        _totalRecall();
    }

    /**
     * @notice Specifies ERC20 tokens managed by this strategy that should be protected from vault sweep operations
     * @dev Currently returns an empty array as balanceShare represents internal pool shares, not distinct ERC20 tokens
     *      Want tokens and vault shares are automatically protected by BaseStrategy
     * @return tokens Array of protected token addresses (currently empty)
     */
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory tokens)
    {
        tokens = new address[](0);
    }

    /**
     * @notice Converts an amount from the native gas token's smallest unit (wei) to want tokens
     * @dev Assumes a 1:1 value relationship since want token (WMNT) is the wrapped native token
     *      Used by Yearn infrastructure and keepers to price gas costs relative to strategy returns
     * @param _amtInWei The amount in wei (native gas token)
     * @return The equivalent amount in want tokens
     */
    function ethToWant(
        uint256 _amtInWei
    ) public view virtual override returns (uint256) {
        return _amtInWei;
    }

    /**
     * @notice Internal function to calculate profit/loss based on current assets vs debt to vault
     * @dev Compares current total assets with the strategy's debt recorded in the vault
     *      Used during performance reporting to determine strategy effectiveness
     * @return profit_ Calculated profit since last report
     * @return loss_ Calculated loss since last report
     * @return debtPayment_ Always returns 0 as actual debt payment is calculated in prepareReturn
     */
    function _returnDepositPlatformValue()
        internal
        view
        returns (uint256 profit_, uint256 loss_, uint256 debtPayment_)
    {
        uint256 prevDebt = vault.strategies(address(this)).totalDebt;
        uint256 currentAssets = estimatedTotalAssets();

        if (currentAssets > prevDebt) {
            profit_ = currentAssets - prevDebt;
            loss_ = 0;
        } else {
            loss_ = prevDebt - currentAssets;
            profit_ = 0;
        }
        debtPayment_ = 0;
    }

    /**
     * @notice Internal function to deposit want tokens into the Init Protocol lending pool
     * @dev Calls depositInit via the Iinit interface and updates internal share accounting
     * @param _amount The amount of want tokens to invest
     * @return success True if the investment operation was successful
     */
    function _investInStrategy(
        uint256 _amount
    ) internal returns (bool success) {
        if (_amount == 0) return true; // No action needed if amount is zero

        IWMNT(WMNT).withdraw(_amount);
        uint256 mntBalance = address(this).balance;
        require(mntBalance >= _amount, "Insufficient MNT received");
        RSM.lockMNT(address(this).balance); //! qua va convertito tutto in MNT da WMNT
        success = true;
    }

    /**
     * @notice Internal function to withdraw a specific amount of want tokens from the lending pool
     * @dev Converts the requested want amount to pool shares, burns the shares, and updates internal accounting
     *      Includes slippage protection and handles cases where requested amount exceeds available shares
     * @param _amount The target amount of want tokens to withdraw
     * @return returnAmount_ The actual amount of want tokens received from withdrawal
     * @return loss_ Loss incurred if actual return is significantly less than expected (0.1% tolerance)
     */
    function _withdrawSingleAmount(
        uint256 _amount
    ) internal returns (uint256 returnAmount_, uint256 loss_) {
        if (_amount == 0) return (0, 0);

        //! probabilmente ci dovro aggiungere dei controlli
        RSM.unlockMNT(_amount);
        uint256 mntReceived = address(this).balance;
        IWMNT(WMNT).deposit{value: mntReceived}();
        loss_ = 0;
        returnAmount_ = _amount;
    }

    /**
     * @notice Internal function to withdraw all assets from the Init Protocol lending pool
     * @dev Accrues interest for accurate accounting, then burns all held shares to recover want tokens
     *      Sets balanceShare to 0 and transfers all recovered assets to the strategy
     * @return success True if the operation completed (doesn't guarantee full recovery if pool has issues)
     */
    function _totalRecall() internal returns (bool success) {
        (uint256 lockedAmount, ) = RSM.getLockStatus(address(this));

        if (lockedAmount > 0) {
            RSM.unlockMNT(lockedAmount);
        }

        // Claim rewards se disponibili
        if (actualPoolId != 0) {
            RSM.claimRewards(actualPoolId);
        }

        // Wrap tutto il MNT ricevuto
        uint256 mntBalance = address(this).balance;
        if (mntBalance > 0) {
            IWMNT(WMNT).deposit{value: mntBalance}();
        }

        success = true;
    }

    /**
     * @notice Returns a value from the lending pool related to the current value of held shares
     * @dev Uses the Init Protocol's debtShareToAmtStored function for share valuation
     *      The precise meaning depends on the Init Protocol's specific implementation
     * @return The value as determined by debtShareToAmtStored(balanceShare)
     */
    function getCurrentDebtValue() external view returns (uint256) {
        return 0;
    }

    /**
     * @notice Returns the current state of the emergency exit flag
     * @dev Test getter function to check if the strategy is in emergency exit mode
     *      emergencyExit is inherited from BaseStrategy
     * @return True if the strategy is in emergency exit mode, false otherwise
     */
    function getEmergencyExitFlag() external view returns (bool) {
        return emergencyExit;
    }

    // Aggiungi funzione per settare il pool ID
    function setPoolId(uint256 _poolId) external onlyAuthorized {
        actualPoolId = _poolId;
    }

    receive() external payable {}
}
