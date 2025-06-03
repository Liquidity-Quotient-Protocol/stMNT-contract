// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";

import {Address} from "@openzeppelin-contract@5.3.0/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contract@5.3.0/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20 as IERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20 as SafeERC20v4} from "@openzeppelin-contracts@4.5.0/contracts/token/ERC20/utils/SafeERC20.sol";

import {Lendl} from "./DefiProtocol/LendlProt.sol";
import {IProtocolDataProvider, ILendingPool} from "./interface/ILendl.sol";
import {Ownable} from "@openzeppelin-contract@5.3.0/contracts/access/Ownable.sol";

contract Strategy2nd is BaseStrategy, Ownable, Lendl {
    using SafeERC20 for IERC20;
    using SafeERC20v4 for IERC20v4; 
    using Address for address;

    address public immutable lendlAddress =
        0x972BcB0284cca0152527c4f70f8F689852bCAFc5; //! mock
    address public immutable WMNT = 0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8; // Fixed to real WMNT
    address public immutable lendlDataProvider =
        0x1234567890AbcdEF1234567890aBcdef12345678; //!mock
    address public lendingPool; 
    address public lToken;

    uint private balanceShare; // Tracks our lToken shares

    // solhint-disable-next-line no-empty-blocks
    constructor(
        address _vault,
        address _owner
    ) BaseStrategy(_vault) Ownable(_owner) {}

    // Management functions
    /**
     * @notice Sets the address of the Lendle lending pool used by the strategy.
     * @param _lendingPool Address of the lending pool contract.
     */
    function setLendingPool(address _lendingPool) external onlyOwner {
        require(_lendingPool != address(0), "Set correct Address");
        lendingPool = _lendingPool;
    }

    function setlToken(address _lToken) external onlyOwner {
        require(_lToken != address(0), "Set correct Address");
        lToken = _lToken;
    }

    /**
     * @notice Updates unlimited spending allowance for the vault on the `want` token.
     * @param _approve If true, grants max allowance; otherwise revokes.
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
     * @notice Updates unlimited spending allowance for Lendle on the `want` token.
     * @param _approve If true, grants max allowance; otherwise revokes.
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

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************
    /**
     * @notice Returns the strategy name.
     * @return The strategy's display name.
     */
    function name() external view override returns (string memory) {
        return "Strategy StMantle defi staking Lendle deposit";
    }

    function lTokenToWant(uint256 lTokenAmount) public view returns (uint256) {
        if (lTokenAmount == 0) return 0;
        uint256 rate = IProtocolDataProvider(lendlDataProvider)
            .getReserveNormalizedIncome(address(want));
        return (lTokenAmount * rate) / 1e27;
    }

    function wantToLToken(uint256 wantAmount) public view returns (uint256) {
        if (wantAmount == 0) return 0;
        uint256 rate = IProtocolDataProvider(lendlDataProvider)
            .getReserveNormalizedIncome(address(want));
        require(rate > 0, "Invalid rate");
        return (wantAmount * 1e27) / rate;
    }

    /**
     * @notice Estimates the total assets held by the strategy in terms of `want`.
     * @return The estimated total value of managed assets.
     */
    function estimatedTotalAssets() public view override returns (uint256) {
        // Verify our internal tracking matches actual lToken balance
        uint256 actualLTokenBalance = IERC20(lToken).balanceOf(address(this));
        require(
            balanceShare == actualLTokenBalance,
            "Balance share mismatch"
        );

        uint256 wantConv = lTokenToWant(balanceShare);
        uint256 wantBal = want.balanceOf(address(this));
        return wantBal + wantConv;
    }

    /**
     * @notice Prepares performance report data for the vault.
     * @param _debtOutstanding Amount needed to be made available to the vault.
     * @return _profit Reported profit.
     * @return _loss Reported loss.
     * @return _debtPayment Amount repaid to the vault.
     */
    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {
        // Get current profit/loss calculation
        (_profit, _loss, _debtPayment) = _returnDepositPlatformValue();

        // If we need to liquidate for the profit reporting
        if (want.balanceOf(address(this)) < _profit) {
            uint256 _amountNeeded = _profit - want.balanceOf(address(this));
            (uint256 liquidated, uint256 loss) = liquidatePosition(_amountNeeded);
            _loss += loss;
        }

        // Small rounding protection
        if (_profit > 0) {
            _profit = _profit - 1;
        }
    }

    /**
     * @notice Adjusts the strategy's position by depositing available funds into Lendle.
     * @param _debtOutstanding Amount that may be withdrawn in the next harvest.
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
     * @notice Attempts to free up enough capital to satisfy a withdrawal.
     * @param _amountNeeded Amount to be withdrawn from the strategy.
     * @return _liquidatedAmount Actual amount withdrawn.
     * @return _loss Any incurred loss during withdrawal.
     */
    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        uint256 balance = want.balanceOf(address(this));
        if (balance >= _amountNeeded) {
            return (_amountNeeded, 0);
        }

        uint256 amountToWithdraw = _amountNeeded - balance;
        uint256 amountFreed = _withdrawTokenFromStrategy(amountToWithdraw);

        _liquidatedAmount = balance + amountFreed;
        if (_liquidatedAmount < _amountNeeded) {
            _loss = _amountNeeded - _liquidatedAmount;
        }
    }

    /**
     * @notice Attempts to exit all positions and retrieve funds.
     * @return The total amount recovered to the strategy contract.
     */
    function liquidateAllPositions() internal override returns (uint256) {
        bool success = _totalRecall();
        require(success, "Error in total recall");
        return want.balanceOf(address(this));
    }

    /**
     * @notice Prepares the strategy for migration to a new contract.
     * @param _newStrategy Address of the new strategy contract.
     */
    function prepareMigration(address _newStrategy) internal override {
        // Transfer any lTokens that might be held
        // migrate() will handle want tokens automatically
    }

    /**
     * @notice Returns a list of tokens to be protected from `sweep` operations.
     * @return tokens The list of addresses considered protected.
     */
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory tokens)
    {
        tokens = new address[](1);
        tokens[0] = lToken; // Protect our lTokens
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     */
    function ethToWant(
        uint256 _amtInWei
    ) public view virtual override returns (uint256) {
        return _amtInWei;
    }

    // INTERNAL HELPER FUNCTIONS

    /**
     * @notice Withdraws funds from the Lendle strategy.
     * @param _amount Amount to withdraw in `want`.
     * @return returnAmount Amount received.
     */
    function _withdrawTokenFromStrategy(
        uint256 _amount
    ) internal returns (uint256 returnAmount) {
        (returnAmount, ) = _withdrawSingleAmount(_amount);
    }

    /**
     * @notice Calculates the value of the current position and liquid assets.
     * @return _profit Total estimated profit.
     * @return _loss Total estimated loss.
     * @return _debtPayment Available liquid `want`.
     */
    function _returnDepositPlatformValue()
        internal
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {
        uint256 prevDebt = vault.strategies(address(this)).totalDebt;
        uint256 currentAssetsFromFunc = estimatedTotalAssets();

        if (currentAssetsFromFunc > prevDebt) {
            _profit = currentAssetsFromFunc - prevDebt;
        } else {
            _loss = prevDebt - currentAssetsFromFunc;
        }

        _debtPayment = want.balanceOf(address(this));
    }

    /**
     * @notice Deposits funds into the Lendle lending market.
     * @param _amount Amount of `want` to invest.
     * @return success Whether the deposit was successful.
     */
    function _investInStrategy(
        uint256 _amount
    ) internal returns (bool success) {
        uint256 share = depositLendl(lendingPool, address(want), _amount, lToken);
        balanceShare += share;
        success = true;
    }

    event ProblemWithWithdrawStrategy(uint time, uint share, uint balanceShare);

    /**
     * @notice Withdraws a specific amount of `want` from Lendle.
     * @param _amount Amount of `want` to retrieve.
     * @return returnAmount Actual amount returned.
     * @return _loss Any loss incurred during withdrawal.
     */
    function _withdrawSingleAmount(
        uint256 _amount
    ) internal returns (uint256 returnAmount, uint256 _loss) {
        uint256 share = wantToLToken(_amount);
        
        if (share > balanceShare) {
            emit ProblemWithWithdrawStrategy(
                block.timestamp,
                share,
                balanceShare
            );
            revert("ProblemWithWithdrawStrategy");
        }
        
        balanceShare -= share;
        uint256 _returnamount = withdrawLendl(lendingPool, lToken, share);
        require(_returnamount >= (_amount * 999) / 1000, "Returned too little"); // tolerance 0.1%
        
        returnAmount = _amount;
        _loss = 0;
    }

    /**
     * @notice Withdraws all assets from Lendle and resets position.
     * @return success Whether the recall was successful.
     */
    function _totalRecall() internal returns (bool success) {
        if (balanceShare > 0) {
            uint256 sharesToWithdraw = balanceShare;
            uint256 amountReceived = withdrawLendl(lendingPool, lToken, sharesToWithdraw);
            balanceShare = 0; // Reset after withdrawal
        }
        success = true;
    }

    /**
     * @notice Returns the current debt value of the shares held in the Lendle pool.
     * @return The amount of `want` represented by `balanceShare`.
     */
    function getCurrentDebtValue() external view returns (uint256) {
        return lTokenToWant(balanceShare);
    }

    /// @notice Returns the current lToken balance of the strategy
    function currentLendleShare() public view returns (uint256) {
        return IERC20(lToken).balanceOf(address(this));
    }

    // TEST GETTERS (like Strategy1st)
    function getBalanceShare() external view returns (uint256) {
        return balanceShare;
    }

    function getEmergencyExitFlag() external view returns (bool) {
        return emergencyExit;
    }
}