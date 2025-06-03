// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;

import {console} from "forge-std/Test.sol";
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

    address public immutable WMNT = 0x78c1b0C915c4FAA5FffA6CAbf0219DA63d7f4cb8; // Fixed to real WMNT
    address public immutable lendlDataProvider =
        0x552b9e4bae485C4B7F540777d7D25614CdB84773;

    address public constant lendingPool =
        0xCFa5aE7c2CE8Fadc6426C1ff872cA45378Fb7cF3;
    address public lToken;

    uint private balanceShare; // Tracks our lToken shares

    address public lTokenWMNT; // Questo sarà l'lWMNT token

    // solhint-disable-next-line no-empty-blocks
    constructor(
        address _vault,
        address _owner
    ) BaseStrategy(_vault) Ownable(_owner) {
        (address aTokenAddress, , ) = IProtocolDataProvider(lendlDataProvider)
            .getReserveTokensAddresses(WMNT);
        lTokenWMNT = aTokenAddress;

        IERC20(WMNT).approve(lendingPool, type(uint256).max);
    }

    // Management functions

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

        // In Aave/Lendle, il tasso è normalizedIncome
        uint256 rate = ILendingPool(lendingPool).getReserveNormalizedIncome(
            address(want)
        );
        console.log("Rate:", rate);
        return (lTokenAmount * rate) / 1e27; // Rate è in ray (1e27)
    }

    function wantToLToken(uint256 wantAmount) public view returns (uint256) {
        if (wantAmount == 0) return 0;
        uint256 rate = ILendingPool(lendingPool).getReserveNormalizedIncome(
            WMNT
        );

        require(rate > 0, "Invalid rate");
        return (wantAmount * 1e27) / rate;
    }


    function verita()external view returns(uint256){
          uint256 actualLTokenBalance = IERC20(lTokenWMNT).balanceOf(
            address(this)
        );
        return actualLTokenBalance;
    }



    /**
     * @notice Estimates the total assets held by the strategy in terms of `want`.
     * @return The estimated total value of managed assets.
     */
    function estimatedTotalAssets() public view override returns (uint256) {
        // Verifica che il nostro tracking interno sia corretto
        uint256 actualLTokenBalance = IERC20(lTokenWMNT).balanceOf(
            address(this)
        );
        console.log("Effective lToken balance:", actualLTokenBalance);
        uint256 valueInLending = lTokenToWant(actualLTokenBalance);
        uint256 liquidWant = want.balanceOf(address(this));

        return liquidWant + valueInLending;
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
            (uint256 liquidated, uint256 loss) = liquidatePosition(
                _amountNeeded
            );
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
        // Deposita WMNT e ricevi lWMNT
        
        uint256 balanceBefore = IERC20(lTokenWMNT).balanceOf(address(this));

        ILendingPool(lendingPool).deposit(
            WMNT, // asset to deposit
            _amount, // amount
            address(this), // onBehalfOf
            0 // referralCode
        );

        uint256 balanceAfter = IERC20(lTokenWMNT).balanceOf(address(this));
        require(balanceBefore<balanceAfter, "Deposit failed, no lTokens received");
        success = true;
    }

    event ProblemWithWithdrawStrategy(uint time, uint share, uint balanceAfter);

  
    function _withdrawSingleAmount(
        uint256 _amountWantToWithdraw // Quantità di WMNT che si vuole prelevare
    ) internal returns (uint256 actualAmountReceived, uint256 _loss) {
        console.log(
            "Strategy _withdrawSingleAmount: Inizio prelievo per %s want",
            _amountWantToWithdraw
        );

        if (_amountWantToWithdraw == 0) {
            return (0, 0);
        }

        uint256 lTokensHeldBeforeWithdraw = IERC20(lTokenWMNT).balanceOf(
            address(this)
        );

        // Non possiamo prelevare più del valore delle quote che abbiamo.
        uint256 maxValueOfOurLTokens = lTokenToWant(lTokensHeldBeforeWithdraw);
        uint256 amountToActuallyAttemptWithdraw = _amountWantToWithdraw;

        if (amountToActuallyAttemptWithdraw > maxValueOfOurLTokens) {
            console.log(
                "Strategy _withdrawSingleAmount: Richiesta di prelievo (%s) maggiore del valore delle quote (%s). Prelevo il massimo.",
                amountToActuallyAttemptWithdraw,
                maxValueOfOurLTokens
            );
            amountToActuallyAttemptWithdraw = maxValueOfOurLTokens;
        }

        if (
            amountToActuallyAttemptWithdraw == 0 &&
            lTokensHeldBeforeWithdraw > 0
        ) {
            // Abbiamo lTokens ma valgono 0. Per Aave, per ritirare lTokens con valore 0 (e bruciarli),
            // si può chiamare withdraw con type(uint256).max per ritirare "tutto il possibile".
            // Se il valore è davvero 0, actualAmountReceived sarà 0.
            console.log(
                "Strategy _withdrawSingleAmount: lTokens hanno valore 0, tentativo di ritirare tutto (type(uint256).max)."
            );
            actualAmountReceived = ILendingPool(lendingPool).withdraw(
                WMNT,
                type(uint256).max, // Tentativo di prelevare tutto l'underlying possibile per le quote detenute
                address(this)
            );
        } else if (amountToActuallyAttemptWithdraw > 0) {
            actualAmountReceived = ILendingPool(lendingPool).withdraw(
                WMNT, // asset sottostante (WMNT)
                amountToActuallyAttemptWithdraw, // quantità di WMNT da prelevare
                address(this) // a chi inviare
            );
        } else {
            // amountToActuallyAttemptWithdraw è 0 e lTokensHeldBeforeWithdraw è 0
            actualAmountReceived = 0;
        }

        uint256 lTokensHeldAfterWithdraw = IERC20(lTokenWMNT).balanceOf(
            address(this)
        );
   

        // Calcola la perdita se abbiamo ricevuto meno di quanto tentato (con tolleranza)
        if (
            actualAmountReceived <
            (amountToActuallyAttemptWithdraw * 999) / 1000
        ) {
            // Tolleranza 0.1%
            _loss = amountToActuallyAttemptWithdraw - actualAmountReceived;
        } else {
            _loss = 0;
        }

        console.log(
            "Strategy _withdrawSingleAmount: Ricevuti %s want, perdita calcolata: %s",
            actualAmountReceived,
            _loss
        );
        return (actualAmountReceived, _loss);
    }

    /**
     * @notice Withdraws all assets from Lendle and resets position.
     * @return success Whether the recall was successful.
     */
    function _totalRecall() internal returns (bool success) {
      
        uint256 currentActualLTokenBalance = IERC20(lTokenWMNT).balanceOf(
            address(this)
        );
    
        if (currentActualLTokenBalance > 0) {
            uint256 balanceWantBeforeWithdraw = want.balanceOf(address(this));

            ILendingPool(lendingPool).withdraw(
                WMNT, // L'asset sottostante (WMNT)
                type(uint256).max, // Indica di prelevare tutto l'underlying possibile per le quote detenute
                address(this) // A chi inviare i fondi
            );

            uint256 balanceWantAfterWithdraw = want.balanceOf(address(this));
            uint256 amountEffectivelyWithdrawn = balanceWantAfterWithdraw -
                balanceWantBeforeWithdraw;
        } else {
            console.log(
                "Strategy _totalRecall: Nessuna balanceShare (lTokens) da prelevare."
            );
        }
        success = true;
    }

    /**
     * @notice Returns the current debt value of the shares held in the Lendle pool.
     * @return The amount of `want` represented by `balanceShare`.
     */
    function getCurrentDebtValue() external view returns (uint256) {
        return lTokenToWant(IERC20(lTokenWMNT).balanceOf(address(this)));
    }

    /// @notice Returns the current lToken balance of the strategy
    function currentLendleShare() public view returns (uint256) {
        return IERC20(lToken).balanceOf(address(this));
    }

    // TEST GETTERS (like Strategy1st)
    function getBalanceShare() external view returns (uint256) {
        return IERC20(lTokenWMNT).balanceOf(address(this));
    }

    function getEmergencyExitFlag() external view returns (bool) {
        return emergencyExit;
    }
}
