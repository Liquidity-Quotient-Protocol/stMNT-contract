// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";
import {Address} from "@openzeppelin-contract@5.3.0/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20 as IERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20 as SafeERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/utils/SafeERC20.sol";
import {Lendl} from "./DefiProtocol/LendlProt.sol";
import {IProtocolDataProvider, ILendingPool} from "./interface/ILendl.sol";

/**
 * @title Strategy2nd
 * @author LiQ Quotient Protocol Team
 * @notice A Yearn V2 strategy that deposits WMNT tokens into the Lendle lending protocol to earn yield
 * @dev This strategy inherits from BaseStrategy (Yearn V2) and Lendl (Lendle protocol interaction)
 *      The strategy accepts WMNT as the want token and deposits it into Lendle lending pools to generate yield
 *      Uses Lendle's Aave-like architecture with lTokens representing deposited positions
 *      Automatically fetches the correct lWMNT token address during construction
 */
contract Strategy2nd is BaseStrategy, Lendl {
    using SafeERC20 for IERC20;
    using SafeERC20v4 for IERC20v4;
    using Address for address;

    /// @notice Address of Wrapped Mantle token (the want token for this strategy)
    address public constant WMNT = 0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8;

    /// @notice Address of the Lendle protocol data provider for getting reserve information
    address public constant lendlDataProvider =
        0x552b9e4bae485C4B7F540777d7D25614CdB84773;

    /// @notice Address of the Lendle lending pool where funds are deposited
    address public constant lendingPool =
        0xCFa5aE7c2CE8Fadc6426C1ff872cA45378Fb7cF3;

    /// @notice Address of a configurable lToken contract (can be set by authorized users)
    /// @dev This is separate from lTokenWMNT and can be used for additional functionality
    address public lToken;

    /// @notice Address of the lWMNT token received when depositing WMNT into Lendle
    /// @dev This is the receipt token representing our position in the Lendle pool
    ///      Automatically fetched from Lendle's data provider during construction
    address public immutable lTokenWMNT;

    /**
     * @notice Constructs the Strategy2nd contract
     * @dev Automatically fetches the lWMNT token address from Lendle's data provider
     *      and sets up unlimited approval for the lending pool
     * @param _vault Address of the Yearn vault that will use this strategy
     * @param _owner Address that will own this strategy contract (unused in current implementation)
     */
    constructor(address _vault, address _owner) BaseStrategy(_vault) {
        (address aTokenAddress, , ) = IProtocolDataProvider(lendlDataProvider)
            .getReserveTokensAddresses(WMNT);
        lTokenWMNT = aTokenAddress;

        IERC20(WMNT).approve(lendingPool, type(uint256).max);
    }

    /// @notice Event emitted when the lToken address is updated by authorized users
    event SetNewLToken(address indexed oldLToken, address indexed newLToken);

    /**
     * @notice Sets the address of the configurable lToken contract
     * @dev Only callable by authorized users (governance, management, or strategist)
     *      Emits SetNewLToken event for tracking changes
     * @param _lToken The address of the lToken contract to set
     */
    function setlToken(address _lToken) external onlyAuthorized {
        require(_lToken != address(0), "Set correct Address");
        address oldLToken = lToken;
        lToken = _lToken;
        emit SetNewLToken(oldLToken, _lToken);
    }

    /**
     * @notice Updates the want token allowance for the vault contract
     * @dev Allows the vault to pull want tokens from this strategy during withdrawals
     *      Only callable by authorized users
     * @param _approve If true, grants maximum allowance; otherwise revokes allowance
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
     * @notice Updates the want token allowance for the Lendle lending pool
     * @dev Allows the strategy to deposit funds into the Lendle protocol
     *      Only callable by authorized users
     * @param _approve If true, grants maximum allowance; otherwise revokes allowance
     */
    function updateUnlimitedSpendingLendl(
        bool _approve
    ) external onlyAuthorized {
        if (_approve) {
            SafeERC20v4.safeApprove(IERC20v4(want), lendingPool, 0);
            SafeERC20v4.safeApprove(
                IERC20v4(want),
                lendingPool,
                type(uint256).max
            );
        } else {
            SafeERC20v4.safeApprove(IERC20v4(want), lendingPool, 0);
        }
    }

    /**
     * @notice Returns the display name of this strategy
     * @return The human-readable name of the strategy
     */
    function name() external view override returns (string memory) {
        return "Strategy StMantle defi staking Lendle deposit";
    }

    /**
     * @notice Converts lToken amount to equivalent want token amount
     * @dev Uses Lendle's normalized income rate to calculate the conversion
     *      Rate is expressed in ray units (1e27) following Aave's standard
     * @param lTokenAmount Amount of lTokens to convert
     * @return Equivalent amount in want token terms
     */
    function lTokenToWant(uint256 lTokenAmount) public view returns (uint256) {
        if (lTokenAmount == 0) return 0;

        uint256 rate = ILendingPool(lendingPool).getReserveNormalizedIncome(
            address(want)
        );
        return (lTokenAmount * rate) / 1e27; // Rate is in ray (1e27)
    }

    /**
     * @notice Estimates the total assets held by the strategy in terms of want token
     * @dev Calculates the sum of liquid want tokens and lWMNT tokens held by the strategy
     *      Note: lWMNT tokens naturally appreciate in value over time due to accrued interest
     * @return The estimated total value of managed assets in want token terms
     */
    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 actualLTokenBalance = IERC20(lTokenWMNT).balanceOf(
            address(this)
        );
        uint256 liquidWant = want.balanceOf(address(this));

        return liquidWant + actualLTokenBalance;
    }

    /**
     * @notice Prepares performance report data for the vault during harvest
     * @dev Calculates profit/loss and ensures adequate liquidity for debt obligations
     *      May liquidate positions to meet debt outstanding or profit reporting requirements
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
     * @dev Invests excess liquid want tokens into the Lendle pool while maintaining required liquidity
     * @param _debtOutstanding Amount that may be withdrawn in the next harvest or amount over debt limit
     */
    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 _balanceInContract = want.balanceOf(address(this));

        if (_balanceInContract > _debtOutstanding) {
            uint256 _amountToInvest = _balanceInContract - _debtOutstanding;
            bool success = _investInStrategy(_amountToInvest);
            require(success, "Error in invest");
        }
    }

    /**
     * @notice Makes a specified amount of want tokens liquid by withdrawing from Lendle if necessary
     * @dev Attempts to withdraw the exact amount needed from the lending pool
     *      Calculates loss if the actual amount received is less than requested
     * @param _amountNeeded Target amount of liquid want tokens required
     * @return _liquidatedAmount Actual amount of want tokens made liquid after operations
     * @return _loss Loss incurred if withdrawal returns less than expected
     */
    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        (uint256 amountFreed, ) = _withdrawSingleAmount(_amountNeeded);

        _liquidatedAmount = amountFreed;
        if (
            _liquidatedAmount < _amountNeeded &&
            _loss == 0 &&
            amountFreed < _amountNeeded
        ) {
            _loss += (_amountNeeded - amountFreed);
        }
    }

    /**
     * @notice Liquidates all assets from the Lendle pool and holds them as want tokens in the strategy
     * @dev Used during strategy migration or emergency situations to exit all positions
     * @return The total want token balance of this strategy after complete liquidation
     */
    function liquidateAllPositions() internal override returns (uint256) {
        bool success = _totalRecall();
        require(success, "Error in total recall");
        return want.balanceOf(address(this));
    }

    /**
     * @notice Prepares the strategy for migration to a new strategy contract
     * @dev Currently empty as migration logic for lTokens would be implemented here if needed
     *      Base migration of want tokens is handled automatically by BaseStrategy
     * @param _newStrategy Address of the new strategy contract (unused in current implementation)
     */
    function prepareMigration(address _newStrategy) internal override {
        // Migration logic would be implemented here if needed
    }

    /**
     * @notice Specifies ERC20 tokens managed by this strategy that should be protected from vault sweep operations
     * @dev Protects the configurable lToken from being swept by governance
     *      lWMNT tokens and want tokens are automatically protected by BaseStrategy
     * @return tokens Array of protected token addresses containing the configurable lToken
     */
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory tokens)
    {
        tokens = new address[](1);
        tokens[0] = lToken;
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
     *      Returns current liquid want balance as potential debt payment amount
     * @return _profit Calculated profit since last report
     * @return _loss Calculated loss since last report
     * @return _debtPayment Current liquid want token balance available for repayment
     */
    function _returnDepositPlatformValue()
        internal
        view
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {
        uint256 prevDebt = vault.strategies(address(this)).totalDebt;
        uint256 currentAssetsFromFunc = estimatedTotalAssets();

        if (currentAssetsFromFunc > prevDebt) {
            _profit = currentAssetsFromFunc - prevDebt;
            _loss = 0;
        } else {
            _loss = prevDebt - currentAssetsFromFunc;
            _profit = 0;
        }

        _debtPayment = want.balanceOf(address(this));
    }

    /**
     * @notice Internal function to deposit want tokens into the Lendle lending market
     * @dev Deposits WMNT tokens and receives lWMNT tokens in return representing the position
     *      Verifies that lWMNT tokens were actually received to ensure deposit success
     * @param _amount Amount of want tokens to invest
     * @return success True if the deposit operation was successful
     */
    function _investInStrategy(
        uint256 _amount
    ) internal returns (bool success) {
        if (_amount == 0) return true;
        uint256 balanceBefore = IERC20(lTokenWMNT).balanceOf(address(this));

        ILendingPool(lendingPool).deposit(WMNT, _amount, address(this), 0);

        uint256 balanceAfter = IERC20(lTokenWMNT).balanceOf(address(this));
        require(
            balanceBefore < balanceAfter,
            "Deposit failed, no lTokens received"
        );
        success = true;
    }

    /// @notice Event emitted when there's an issue with strategy withdrawal operations
    event ProblemWithWithdrawStrategy(uint time, uint share, uint balanceAfter);

    /**
     * @notice Internal function to withdraw a specific amount of want tokens from Lendle
     * @dev Handles both partial and full withdrawals from the lending pool
     *      Uses the strategy's lWMNT balance to determine withdrawal limits
     *      If requested amount exceeds available balance, withdraws maximum possible
     * @param _amountWantToWithdraw Amount of want tokens to retrieve
     * @return actualAmountReceived Actual amount of want tokens received from withdrawal
     * @return _loss Any loss incurred during the withdrawal (typically 0 for Lendle)
     */
    function _withdrawSingleAmount(
        uint256 _amountWantToWithdraw
    ) internal returns (uint256 actualAmountReceived, uint256 _loss) {
        if (_amountWantToWithdraw == 0) {
            return (0, 0);
        }

        uint256 totalBal = getBalanceWant();

        if (totalBal <= _amountWantToWithdraw) {
            actualAmountReceived = ILendingPool(lendingPool).withdraw(
                WMNT,
                type(uint256).max,
                address(this)
            );
        } else {
            actualAmountReceived = ILendingPool(lendingPool).withdraw(
                WMNT,
                _amountWantToWithdraw,
                address(this)
            );
        }

        return (actualAmountReceived, _loss);
    }

    /**
     * @notice Internal function to withdraw all assets from Lendle and reset the strategy position
     * @dev Withdraws the maximum possible amount from the lending pool to exit all positions
     *      Used for complete exit from the lending protocol during migration or emergency
     * @return success True if the total recall operation completed successfully
     */
    function _totalRecall() internal returns (bool success) {
        ILendingPool(lendingPool).withdraw(
            WMNT,
            type(uint256).max,
            address(this)
        );

        success = true;
    }

    /**
     * @notice Returns the current balance of the configurable lToken held by this strategy
     * @dev This function uses the lToken address set by setlToken() function
     *      Separate from the main lWMNT position tracking
     * @return The current balance of the configurable lToken held by this strategy
     */
    function currentLendleShare() public view returns (uint256) {
        return IERC20(lToken).balanceOf(address(this));
    }

    /**
     * @notice Returns the balance of lWMNT tokens held by this strategy
     * @dev Test and monitoring getter function to inspect strategy's main lWMNT holdings
     *      These tokens represent the strategy's primary position in the Lendle pool
     * @return The current lWMNT token balance held by the strategy
     */
    function getBalanceWant() public view returns (uint256) {
        return IERC20(lTokenWMNT).balanceOf(address(this));
    }

    /**
     * @notice Returns the current state of the emergency exit flag
     * @dev Test getter function to check if the strategy is in emergency exit mode
     *      emergencyExit flag is inherited from BaseStrategy
     * @return True if the strategy is in emergency exit mode, false otherwise
     */
    function getEmergencyExitFlag() external view returns (bool) {
        return emergencyExit;
    }
}
