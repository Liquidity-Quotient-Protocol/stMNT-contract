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
import {Ownable} from "@openzeppelin-contract@5.3.0/contracts/access/Ownable.sol";

/**
 * @title Strategy2nd
 * @author Your Team
 * @notice A Yearn V2 strategy that deposits WMNT tokens into the Lendle lending protocol to earn yield
 * @dev This strategy inherits from BaseStrategy (Yearn V2), Ownable, and Lendl (Lendle protocol interaction)
 *      The strategy accepts WMNT as the want token and deposits it into Lendle lending pools to generate yield
 *      Uses Lendle's Aave-like architecture with lTokens representing deposited positions
 */
contract Strategy2nd is BaseStrategy, Ownable, Lendl {
    using SafeERC20 for IERC20;
    using SafeERC20v4 for IERC20v4;
    using Address for address;

    /// @notice Address of Wrapped Mantle token (the want token for this strategy)
    address public constant WMNT = 0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8;
    
    /// @notice Address of the Lendle protocol data provider for getting reserve information
    address public constant lendlDataProvider = 0x552b9e4bae485C4B7F540777d7D25614CdB84773;

    /// @notice Address of the Lendle lending pool where funds are deposited
    address public constant lendingPool = 0xCFa5aE7c2CE8Fadc6426C1ff872cA45378Fb7cF3;
    
    /// @notice Address of the lToken contract (can be set by owner)
    address public lToken;

    /// @notice Address of the lWMNT token received when depositing WMNT into Lendle
    /// @dev This is the receipt token representing our position in the Lendle pool
    address public immutable lTokenWMNT;

    /**
     * @notice Constructs the Strategy2nd contract
     * @dev Automatically fetches the lWMNT token address from Lendle's data provider
     *      and sets up unlimited approval for the lending pool
     * @param _vault Address of the Yearn vault that will use this strategy
     * @param _owner Address that will own this strategy contract
     */
    constructor(
        address _vault,
        address _owner
    ) BaseStrategy(_vault) Ownable(_owner) {
        (address aTokenAddress, , ) = IProtocolDataProvider(lendlDataProvider)
            .getReserveTokensAddresses(WMNT);
        lTokenWMNT = aTokenAddress;

        IERC20(WMNT).approve(lendingPool, type(uint256).max);
    }

    /// @notice Event emitted when the lToken address is updated
    event SetNewLToken(
        address indexed oldLToken,
        address indexed newLToken
    );

    /**
     * @notice Sets the address of the LToken contract
     * @dev Only callable by the strategy owner, emits SetNewLToken event
     * @param _lToken The address of the LToken contract
     */
    function setlToken(address _lToken) external onlyOwner {
        require(_lToken != address(0), "Set correct Address");
        address oldLToken = lToken;
        lToken = _lToken;
        emit SetNewLToken(oldLToken, _lToken);
    }

    /**
     * @notice Updates unlimited spending allowance for the vault on the want token
     * @dev This allows the vault to pull funds from the strategy during withdrawals
     * @param _approve If true, grants max allowance; otherwise revokes
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
     * @notice Updates unlimited spending allowance for Lendle on the want token
     * @dev This allows the strategy to deposit funds into the Lendle protocol
     * @param _approve If true, grants max allowance; otherwise revokes
     */
    function updateUnlimitedSpendingLendl(bool _approve) external onlyOwner {
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
     * @notice Returns the strategy name for identification
     * @return The human-readable name of this strategy
     */
    function name() external view override returns (string memory) {
        return "Strategy StMantle defi staking Lendle deposit";
    }

    /**
     * @notice Converts lToken amount to equivalent want token amount
     * @dev Uses Lendle's normalized income rate to calculate the conversion
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
     * @dev Calculates the sum of liquid want tokens and lWMNT tokens held
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
     * @notice Prepares performance report data for the vault
     * @dev Called by the vault during harvest to assess strategy performance
     * @param _debtOutstanding Amount needed to be made available to the vault
     * @return _profit Reported profit generated by the strategy
     * @return _loss Reported loss incurred by the strategy
     * @return _debtPayment Amount available for immediate repayment to vault
     */
    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {
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
     * @notice Adjusts the strategy's position by depositing available funds into Lendle
     * @dev Invests excess want tokens while maintaining required liquidity for debt outstanding
     * @param _debtOutstanding Amount that may be withdrawn in the next harvest
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
     * @notice Attempts to free up enough capital to satisfy a withdrawal request
     * @dev First uses available liquid funds, then withdraws from Lendle if needed
     * @param _amountNeeded Amount to be withdrawn from the strategy
     * @return _liquidatedAmount Actual amount withdrawn and made available
     * @return _loss Any loss incurred during the withdrawal process
     */
    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
  

        (uint256 amountFreed ,)= _withdrawSingleAmount(_amountNeeded);

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
     * @notice Exits all positions and retrieves all funds to the strategy
     * @dev Used during strategy migration or emergency situations
     * @return The total amount recovered to the strategy contract
     */
    function liquidateAllPositions() internal override returns (uint256) {
        bool success = _totalRecall();
        require(success, "Error in total recall");
        return want.balanceOf(address(this));
    }

    /**
     * @notice Prepares the strategy for migration to a new contract
     * @dev Transfer logic for lTokens would be implemented here if needed
     * @param _newStrategy Address of the new strategy contract
     */
    function prepareMigration(address _newStrategy) internal override {
        // Migration logic would be implemented here if needed
    }

    /**
     * @notice Returns a list of tokens to be protected from sweep operations
     * @dev These tokens are considered part of the strategy's core functionality
     * @return tokens Array of protected token addresses
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
     * @notice Converts ETH amount to want token equivalent
     * @dev For WMNT, this is a 1:1 conversion as both use 18 decimals
     * @param _amtInWei The amount in wei (1e-18 ETH) to convert to want
     * @return The equivalent amount in want token
     */
    function ethToWant(
        uint256 _amtInWei
    ) public view virtual override returns (uint256) {
        return _amtInWei;
    }

  

    /**
     * @notice Calculates the current value of strategy positions and determines profit/loss
     * @dev Compares current total assets with previous debt to determine performance
     * @return _profit Total estimated profit since last report
     * @return _loss Total estimated loss since last report
     * @return _debtPayment Available liquid want tokens for debt repayment
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
     * @notice Deposits funds into the Lendle lending market
     * @dev Deposits WMNT and receives lWMNT tokens in return
     * @param _amount Amount of want token to invest
     * @return success Whether the deposit operation was successful
     */
    function _investInStrategy(
        uint256 _amount
    ) internal returns (bool success) {
        if (_amount == 0) return true;
        uint256 balanceBefore = IERC20(lTokenWMNT).balanceOf(address(this));

        ILendingPool(lendingPool).deposit(
            WMNT,
            _amount,
            address(this),
            0
        );

        uint256 balanceAfter = IERC20(lTokenWMNT).balanceOf(address(this));
        require(
            balanceBefore < balanceAfter,
            "Deposit failed, no lTokens received"
        );
        success = true;
    }

    /// @notice Event emitted when there's an issue with strategy withdrawal
    event ProblemWithWithdrawStrategy(uint time, uint share, uint balanceAfter);

    /**
     * @notice Withdraws a specific amount of want tokens from Lendle
     * @dev Handles both partial and full withdrawals from the lending pool
     * @param _amountWantToWithdraw Amount of want token to retrieve
     * @return actualAmountReceived Actual amount returned from the withdrawal
     * @return _loss Any loss incurred during the withdrawal (typically 0)
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
     * @notice Withdraws all assets from Lendle and resets the strategy position
     * @dev Used for complete exit from the lending protocol
     * @return success Whether the total recall operation was successful
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
     * @notice Returns the current Lendle share balance for the configured lToken
     * @dev This function uses the lToken address set by setlToken()
     * @return The current balance of lTokens held by this strategy
     */
    function currentLendleShare() public view returns (uint256) {
        return IERC20(lToken).balanceOf(address(this));
    }

    /**
     * @notice Returns the balance of lWMNT tokens held by this strategy
     * @dev Test getter function to inspect strategy's lWMNT holdings
     * @return The current lWMNT token balance
     */
    function getBalanceWant() public view returns (uint256) {
        return IERC20(lTokenWMNT).balanceOf(address(this));
    }

    /**
     * @notice Returns the emergency exit flag status
     * @dev Test getter function to check if strategy is in emergency mode
     * @return Whether the strategy is in emergency exit mode
     */
    function getEmergencyExitFlag() external view returns (bool) {
        return emergencyExit;
    }
}