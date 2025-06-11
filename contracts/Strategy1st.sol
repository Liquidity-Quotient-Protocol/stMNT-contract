// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.12;

import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";
import {Address} from "@openzeppelin-contract@5.3.0/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20 as IERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20 as SafeERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/utils/SafeERC20.sol";

import {Iinit} from "./DefiProtocol/InitProt.sol";
import {ILendingPool} from "./interface/IInitCore.sol";

/**
 * @title Strategy1st
 * @author LiQ Quotient Protocol Team
 * @notice A Yearn V2 strategy that deposits WMNT tokens into the Init Protocol lending pool to earn yield
 * @dev This strategy inherits from BaseStrategy (Yearn V2) and Iinit (Init protocol interaction)
 *      The strategy accepts WMNT as the want token and deposits it into Init lending pools to generate yield
 *      Uses Init Protocol's specific mechanisms for deposit/withdrawal and requires accrueInterest() calls
 *      for accurate yield calculation and reporting
 */
contract Strategy1st is BaseStrategy, Iinit {
    using SafeERC20 for IERC20;
    using SafeERC20v4 for IERC20v4;
    using Address for address;

    /// @notice Immutable address of the Init protocol's core/router contract.
    address public constant _initAddr =
        0x972BcB0284cca0152527c4f70f8F689852bCAFc5;
    /// @notice Immutable address of the WMNT (Wrapped MNT) token, the 'want' token for this strategy.
    address public constant WMNT = 0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8;

    /// @notice Address of the Init Protocol lending pool where funds are deposited
    /// @dev Must be set by authorized users via setLendingPool() before strategy can function
    address public lendingPool;

    /// @notice Address of the Init Protocol lending pool where funds are deposited
    /// @dev Must be set by authorized users via setLendingPool() before strategy can function
    uint256 private balanceShare;

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
        Iinit(_initAddr)
    {
        // Initialization is handled by parent constructors.
    }

    /**
     * @notice Sets the address of the Init Protocol lending pool
     * @dev Only callable by authorized users (governance, management, or strategist)
     * @param _lendingPool The address of the lending pool contract
     */
    function setLendingPool(address _lendingPool) external onlyAuthorized {
        require(
            _lendingPool != address(0),
            "Strategy1st: Invalid LendingPool address."
        );
        lendingPool = _lendingPool;
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
     * @notice Updates the want token allowance for the Init protocol's core contract
     * @dev Necessary if the Init core contract executes transferFrom on this strategy's want tokens
     * @param _approve If true, grants maximum allowance; otherwise, sets allowance to 0
     */
    function updateUnlimitedSpendingInit(
        bool _approve
    ) external onlyAuthorized {
        if (_approve) {
            // Original code approved address(vault) then _initAddr. Assuming intent is to approve _initAddr.
            SafeERC20v4.safeApprove(IERC20v4(want), _initAddr, 0);
            SafeERC20v4.safeApprove(
                IERC20v4(want),
                _initAddr,
                type(uint256).max
            );
        } else {
            SafeERC20v4.safeApprove(IERC20v4(want), _initAddr, 0);
        }
    }

    /**
     * @notice Approves the lending pool contract to spend the strategy's want token
     * @dev Required for direct interaction with lending pool if it needs to pull want tokens
     */
    function approveLendingPool() external onlyAuthorized {
        require(
            lendingPool != address(0),
            "Strategy1st: LendingPool not set for approval."
        );
        SafeERC20v4.safeApprove(IERC20v4(want), lendingPool, 0);
        SafeERC20v4.safeApprove(IERC20v4(want), lendingPool, type(uint256).max);
    }

    /**
     * @notice Returns the display name of this strategy
     * @return The human-readable name of the strategy
     */
    function name() external view override returns (string memory) {
        return "Strategy StMantle defi steaking";
    }

    /**
     * @notice Estimates the total assets managed by this strategy, valued in want tokens
     * @dev Includes liquid want tokens and the value of want tokens deposited in the lending pool
     *      Contains a strict check for internal vs on-chain share balance consistency
     * @return The total estimated value of assets in want token terms
     */
    function estimatedTotalAssets() public view override returns (uint256) {
        if (lendingPool == address(0)) {
            // Prevent calls to address(0) if not set
            return want.balanceOf(address(this));
        }
        require(
            balanceShare == ILendingPool(lendingPool).balanceOf(address(this)),
            "Balance share mismatch"
        );

        uint256 _amountInShare = ILendingPool(lendingPool).toAmt(balanceShare);
        uint256 wantBal = want.balanceOf(address(this));
        return wantBal + _amountInShare;
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
        if (lendingPool != address(0)) {
            ILendingPool(lendingPool).accrueInterest();
        }
        (
            uint256 currentProfit,
            uint256 currentLoss,

        ) = _returnDepositPlatformValue();
        _profit = currentProfit;
        _loss = currentLoss;

        if (_debtOutstanding > 0) {
            _debtPayment = _debtOutstanding;
            uint256 neededLiquid = _debtPayment + _profit;
            uint256 currentLiquid = want.balanceOf(address(this));

            if (currentLiquid < neededLiquid) {
                uint256 amountToLiquidate = neededLiquid - currentLiquid;
                (, uint256 lossOnLiq) = liquidatePosition(amountToLiquidate);
                _loss += lossOnLiq;
            }
        } else {
            _debtPayment = 0;
            uint256 currentLiquid = want.balanceOf(address(this));
            if (currentLiquid < _profit) {
                uint256 amountToLiquidate = _profit - currentLiquid;
                (, uint256 lossOnLiq) = liquidatePosition(amountToLiquidate);
                _loss += lossOnLiq;
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
                bool success = _investInStrategy(_amountToInvest);
                require(
                    success,
                    "Strategy1st: Investment failed in adjustPosition."
                );
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
        if (balanceShare > 0) {
            _totalRecall();
        }
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
        require(
            lendingPool != address(0),
            "Strategy1st: LendingPool not set for _investInStrategy."
        );

        uint256 share = depositInit(lendingPool, WMNT, _amount, address(this));
        require(
            share > 0,
            "Strategy1st: depositInit returned zero shares for a non-zero deposit."
        );
        balanceShare += share;
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
        require(
            lendingPool != address(0),
            "Strategy1st: LendingPool not set for _withdrawSingleAmount."
        );
        require(
            balanceShare > 0,
            "Strategy1st: No shares to withdraw in _withdrawSingleAmount."
        );

        uint256 sharesToWithdraw = ILendingPool(lendingPool).toShares(_amount);

        if (sharesToWithdraw == 0 && _amount > 0) {
            return (0, _amount);
        }

        if (sharesToWithdraw > balanceShare) {
            sharesToWithdraw = balanceShare;
        }

        balanceShare -= sharesToWithdraw;
        returnAmount_ = withdrawInit(
            lendingPool,
            sharesToWithdraw,
            address(this)
        );

        uint256 expectedWantForSharesProcessed = ILendingPool(lendingPool)
            .toAmt(sharesToWithdraw);

        if (returnAmount_ < (expectedWantForSharesProcessed * 999) / 1000) {
            // 0.1% tolerance
            loss_ = expectedWantForSharesProcessed - returnAmount_;
        } else {
            loss_ = 0;
        }
    }

    /**
     * @notice Internal function to withdraw all assets from the Init Protocol lending pool
     * @dev Accrues interest for accurate accounting, then burns all held shares to recover want tokens
     *      Sets balanceShare to 0 and transfers all recovered assets to the strategy
     * @return success True if the operation completed (doesn't guarantee full recovery if pool has issues)
     */
    function _totalRecall() internal returns (bool success) {
        if (lendingPool == address(0)) {
            return true;
        }

        if (balanceShare > 0) {
            uint256 sharesToWithdrawAll = balanceShare;

            try ILendingPool(lendingPool).accrueInterest() {} catch {}

            withdrawInit(lendingPool, sharesToWithdrawAll, address(this));

            balanceShare = 0;
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
        if (lendingPool == address(0)) return 0;
        return ILendingPool(lendingPool).debtShareToAmtStored(balanceShare);
    }

    /**
     * @notice Returns the strategy's internal count of its shares in the lending pool.
     * @dev Primarily for testing and off-chain monitoring.
     * @return The current value of the private `balanceShare` state variable.
     */
    function getBalanceShare() external view returns (uint256) {
        return balanceShare;
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
}
