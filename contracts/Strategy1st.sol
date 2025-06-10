// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.12;

// console import is for debugging and should be removed for production.
 import {console} from "forge-std/Test.sol";

// These are the core Yearn libraries
import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";
// StrategyParams import removed as it's not directly used for type declarations here
// and BaseStrategy itself likely handles its own context for it via VaultAPI.

import {Address} from "@openzeppelin-contract@5.3.0/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20 as IERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20 as SafeERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/utils/SafeERC20.sol";

import {Iinit} from "./DefiProtocol/InitProt.sol";
import {ILendingPool} from "./interface/IInitCore.sol"; // Combined IInitCore parts into ILendingPool for this import.

import {Ownable} from "@openzeppelin-contract@5.3.0/contracts/access/Ownable.sol";

/**
 * @title Strategy1st
 * @author [Your Name/Team Name]
 * @notice Strategy for depositing 'want' tokens (WMNT) into an Init Protocol LendingPool.
 * @dev Implements Yearn's BaseStrategy and interacts with a custom Init Protocol.
 * It assumes the Init Protocol's LendingPool requires `accrueInterest()` calls
 * and uses specific mechanisms for deposit/withdrawal via an `Iinit` interface.
 */
contract Strategy1st is BaseStrategy, Iinit, Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20v4 for IERC20v4;
    using Address for address;

    /// @notice Immutable address of the Init protocol's core/router contract.
    address public immutable _initAddr =
        0x972BcB0284cca0152527c4f70f8F689852bCAFc5;
    /// @notice Immutable address of the WMNT (Wrapped MNT) token, the 'want' token for this strategy.
    address public immutable WMNT = 0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8;

    /// @notice Address of the Init Protocol Lending Pool where funds are deposited.
    /// @dev Must be set by the owner via `setLendingPool()`.
    address public lendingPool;

    /// @notice Internal accounting of the shares (or equivalent units) held by the strategy in the `lendingPool`.
    uint256 private balanceShare;

    /**
     * @notice Event emitted if an issue occurs during a withdrawal attempt from the strategy's underlying positions.
     * @param time The block timestamp of the event.
     * @param share The amount of shares involved in the problematic operation.
     * @param balanceShare The strategy's internal `balanceShare` at the time.
     */
    event ProblemWithWithdrawStrategy(
        uint256 time,
        uint256 share,
        uint256 balanceShare
    );

    /**
     * @notice Constructs the Strategy1st contract.
     * @param _vault The address of the Yearn Vault this strategy reports to.
     * @param _owner The initial owner of this strategy contract.
     */
    constructor(
        address _vault,
        address _owner
    )
        // Removed explicit _initAddr param here as Iinit parent likely takes it from state or constant.
        // If your Iinit constructor *requires* it, it should be:
        // constructor(address _vault, address _owner, address __initAddr) BaseStrategy(_vault) Iinit(__initAddr) Ownable(_owner) {}
        // For now, assuming Iinit(_initAddr) works with the state variable.
        BaseStrategy(_vault)
        Iinit(_initAddr)
        Ownable(_owner)
    {
        // Initialization is handled by parent constructors.
    }

    /**
     * @notice Sets the address of the Init Protocol Lending Pool.
     * @dev Can only be called by the contract owner.
     * @param _lendingPool The address of the LendingPool contract.
     */
    function setLendingPool(address _lendingPool) external onlyOwner {
        require(
            _lendingPool != address(0),
            "Strategy1st: Invalid LendingPool address."
        );
        lendingPool = _lendingPool;
    }

    /**
     * @notice Updates the 'want' token allowance for the Vault contract.
     * @dev Allows the Vault to pull 'want' tokens from this strategy. Owner-only.
     * @param _approve If true, grants maximum allowance; otherwise, sets allowance to 0.
     */
    function updateUnlimitedSpending(bool _approve) external onlyOwner {
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
     * @notice Updates the 'want' token allowance for the Init protocol's core contract (`_initAddr`).
     * @dev Necessary if `_initAddr` executes `transferFrom` on this strategy's 'want' tokens. Owner-only.
     * @param _approve If true, grants maximum allowance; otherwise, sets allowance to 0.
     */
    function updateUnlimitedSpendingInit(bool _approve) external onlyOwner {
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
     * @notice Approves the `lendingPool` contract to spend the strategy's 'want' token.
     * @dev Owner-only. Use if direct interaction with `lendingPool` requires it to pull 'want' tokens.
     */
    function approveLendingPool() external onlyOwner {
        require(
            lendingPool != address(0),
            "Strategy1st: LendingPool not set for approval."
        );
        SafeERC20v4.safeApprove(IERC20v4(want), lendingPool, 0);
        SafeERC20v4.safeApprove(IERC20v4(want), lendingPool, type(uint256).max);
    }

    /**
     * @notice Returns the display name of this strategy.
     * @return The strategy's name.
     */
    function name() external view override returns (string memory) {
        return "Strategy StMantle defi steaking"; // User's original name
    }

    /**
     * @notice Estimates the total assets managed by this strategy, valued in 'want' tokens.
     * @dev Includes liquid 'want' and the value of 'want' in the `lendingPool`.
     * Contains a strict check for internal vs. on-chain share balance consistency.
     * @return The total estimated value of assets in 'want' tokens.
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
     * @notice Prepares data for reporting to the Vault.
     * @dev Called during `harvest`. Accrues interest in the `lendingPool`, calculates
     * profit/loss, and determines liquid assets. May liquidate from the pool if
     * liquid 'want' is less than calculated profit. Applies a 1 wei reduction to
     * profit for precision issue mitigation with the Vault.
     * @param _debtOutstanding Amount Vault expects strategy to repay or its over-limit amount.
     * @return _profit The calculated profit to report.
     * @return _loss The calculated loss to report.
     * @return _debtPayment The amount of 'want' made available for debt repayment.
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
        (uint256 currentProfit, uint256 currentLoss, ) = _returnDepositPlatformValue();
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
        }else{
            _debtPayment = 0;
            uint256 currentLiquid = want.balanceOf(address(this));
            if (currentLiquid < _profit) {
                uint256 amountToLiquidate = _profit - currentLiquid;
                (, uint256 lossOnLiq) = liquidatePosition(amountToLiquidate);
                _loss += lossOnLiq;
            }
        }

        if (_profit > 0) {
            _profit = _profit - 1;
        }
    }

    /**
     * @notice Adjusts the strategy's investment position.
     * @dev Called by `harvest` after reporting to the Vault. Invests excess liquid 'want'
     * (funds received from Vault minus `_debtOutstanding`) into the `lendingPool`.
     * @param _debtOutstanding Debt amount the Vault might recall or the strategy is over its limit.
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
     * @notice Makes `_amountNeeded` of 'want' tokens liquid, withdrawing from `lendingPool` if necessary.
     * @dev Checks current liquid 'want'. If insufficient, calls `_withdrawTokenFromStrategy`.
     * @param _amountNeeded Target amount of liquid 'want'.
     * @return _liquidatedAmount Actual 'want' amount liquid after operations.
     * @return _loss Loss incurred during withdrawal from the `lendingPool`.
     */
    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {


        (uint256 amountFreed, uint256 lossFromWithdraw) = _withdrawSingleAmount(
            _amountNeeded
        ); // Use both return values
        _loss = lossFromWithdraw; // Assign loss from withdrawal

        _liquidatedAmount =amountFreed;

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
     * @notice Liquidates all assets from the `lendingPool` and holds them as 'want' in this strategy.
     * @dev Calls `_totalRecall`. The actual transfer to the Vault happens during `Vault.report`.
     * @return The total 'want' balance of this strategy after liquidation.
     */
    function liquidateAllPositions() internal override returns (uint256) {
        bool success = _totalRecall();
        require(success, "Strategy1st: Total recall failed.");
        return want.balanceOf(address(this));
    }

    /**
     * @notice Prepares this strategy for migration to a new strategy.
     * @dev For this strategy, this involves liquidating all assets into 'want' tokens.
     * Any other non-'want' tokens specific to this strategy would be transferred here.
     * @param _newStrategy The address of the new strategy contract.
     */
    function prepareMigration(address _newStrategy) internal override {
        if (balanceShare > 0) {
            _totalRecall(); // Ensure all assets are converted to 'want'
        }
    }

    /**
     * @notice Specifies ERC20 tokens managed by this strategy that should be protected from `Vault.sweep()`.
     * @dev `want` and Vault shares are protected by default in `BaseStrategy`.
     * For this strategy, `balanceShare` represents units in a custom pool, not a distinct ERC20 lToken.
     * The `lendingPool` itself is a contract, not an ERC20 token to be swept.
     */
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory tokens)
    {
        // The user's original code had:
        // tokens = new address[](1);
        // tokens[0] = lendingPool;
        // This is incorrect if lendingPool is the pool contract address itself, as sweep targets ERC20s.
        // If InitProt LENDING_POOL_ADDRESS is an ERC20 (e.g. a LP token for a DEX that this strategy uses), then it's correct.
        // Assuming balanceShare are internal pool shares and lendingPool is the main contract:
        tokens = new address[](0);
    }

    /**
     * @notice Converts an amount from the native gas token's smallest unit (wei) to 'want' tokens.
     * @dev Assumes a 1:1 value relationship if 'want' is the wrapped native token (e.g., WMNT for MNT).
     * Used by Yearn infrastructure (keepers) to price gas costs.
     * @param _amtInWei The amount in wei (native gas token).
     * @return The equivalent amount in 'want' tokens.
     */
    function ethToWant(
        uint256 _amtInWei
    ) public view virtual override returns (uint256) {
        return _amtInWei;
    }

    /**
     * @notice Internal: Withdraws 'want' tokens from the underlying protocol positions.
     * @dev Wrapper for `_withdrawSingleAmount`.
     * @param _amount The amount of 'want' to withdraw from positions.
     * @return returnAmount_ The actual amount of 'want' received.
     */
    function _withdrawTokenFromStrategy(
        uint256 _amount
    ) internal returns (uint256 returnAmount_) {
        (returnAmount_, ) = _withdrawSingleAmount(_amount);
    }

    /**
     * @notice Internal: Calculates profit/loss based on current assets vs. debt to Vault.
     * @dev `_debtPayment` is set to the current liquid 'want' balance of this strategy.
     * @return profit_ Calculated profit.
     * @return loss_ Calculated loss.
     * @return debtPayment_ Liquid 'want' currently held by the strategy.
     */
    function _returnDepositPlatformValue()
        internal
        view
        returns (uint256 profit_, uint256 loss_, uint256 debtPayment_)
    {
        uint256 prevDebt = vault.strategies(address(this)).totalDebt;
        uint256 currentAssets = estimatedTotalAssets();

        console.log("currentAssets -> ",currentAssets);
        console.log("prevDebt -> ",prevDebt);
        

        if (currentAssets > prevDebt) {
            profit_ = currentAssets - prevDebt;
            loss_ = 0;
        } else {
            loss_ = prevDebt - currentAssets;
            profit_ = 0;
        }
        debtPayment_ = 0;
        //debtPayment_ = want.balanceOf(address(this));
    }

    /**
     * @notice Internal: Deposits `_amount` of 'want' (WMNT) into the Init Protocol's `lendingPool`.
     * @dev Calls `depositInit` via the `Iinit` interface. Updates `balanceShare`.
     * @param _amount The amount of 'want' tokens to invest.
     * @return success True if the investment operation was successful.
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
     * @notice Internal: Withdraws a specific `_amount` of 'want' from the Init Protocol `lendingPool`.
     * @dev Converts `_amount` of 'want' to pool shares, then calls `withdrawInit` to burn shares.
     * Updates `balanceShare`. Includes a slippage check.
     * @param _amount The target amount of 'want' tokens to withdraw.
     * @return returnAmount_ The actual amount of 'want' tokens received.
     * @return loss_ Loss incurred if `returnAmount_` is significantly less than expected.
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
            // Cannot get the desired amount as it translates to 0 shares.
            // This can be treated as a failure to retrieve the amount, hence a loss of that amount.
            return (0, _amount);
        }

        if (sharesToWithdraw > balanceShare) {
            // If calculated shares for the desired '_amount' exceed current 'balanceShare',
            // only process the available 'balanceShare'.
            sharesToWithdraw = balanceShare;
        }

        balanceShare -= sharesToWithdraw;
        returnAmount_ = withdrawInit(
            lendingPool,
            sharesToWithdraw,
            address(this)
        );

        // Calculate the expected 'want' amount for the 'sharesToWithdraw' that were actually processed.
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
     * @notice Internal: Withdraws all assets from the Init Protocol `lendingPool`.
     * @dev Calls `withdrawInit` with all currently held `balanceShare`. Sets `balanceShare` to 0.
     * Ensures interest is accrued before withdrawal.
     * @return success True if the operation completed (does not guarantee full recovery if pool had issues).
     */
    function _totalRecall() internal returns (bool success) {
        if (lendingPool == address(0)) {
            return true; // No pool set, nothing to recall.
        }

        if (balanceShare > 0) {
            uint256 sharesToWithdrawAll = balanceShare;

            try ILendingPool(lendingPool).accrueInterest() {} catch {
                // Optional: Log or handle. Continue recall even if accrue fails.
            }

            // Call withdrawInit to burn all shares held by the strategy.
            // The amount received will be reflected in this contract's 'want' balance.
            /* uint256 amountReceived = */ withdrawInit(
                lendingPool,
                sharesToWithdrawAll,
                address(this)
            );

            balanceShare = 0; // All shares are considered withdrawn from strategy's perspective.
        }
        success = true;
    }

    /**
     * @notice Returns a value from the lending pool, possibly related to the current value of shares.
     * @dev The function `debtShareToAmtStored` is specific to the `IInitCore` interface for this pool.
     * Its precise meaning depends on the Init Protocol's implementation.
     * @return The value as determined by `debtShareToAmtStored(balanceShare)`.
     */
    function getCurrentDebtValue() external view returns (uint256) {
        if (lendingPool == address(0)) return 0;
        return ILendingPool(lendingPool).debtShareToAmtStored(balanceShare);
    }

    //! TEST GETTER
    /**
     * @notice Returns the strategy's internal count of its shares in the lending pool.
     * @dev Primarily for testing and off-chain monitoring.
     * @return The current value of the private `balanceShare` state variable.
     */
    function getBalanceShare() external view returns (uint256) {
        return balanceShare;
    }

    /**
     * @notice Returns the current state of the `emergencyExit` flag.
     * @dev `emergencyExit` is a public variable inherited from `BaseStrategy`.
     * This getter provides convenient access for testing.
     * @return True if the strategy is in emergency exit mode, false otherwise.
     */
    function getEmergencyExitFlag() external view returns (bool) {
        return emergencyExit;
    }
}
